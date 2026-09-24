# SDR Transceiver — System Architecture

## 1. Goals and constraints

- **Widest practical frequency coverage** for both RX and TX, using only
  the hardware already on hand.
- **"All modes"**: CW, SSB, AM, FM, and digital modes. This is a software
  requirement, not a hardware one — it's satisfied by getting clean,
  wideband **I/Q** in and out of the digital backend and doing
  modulation/demodulation in software (PL and/or host DSP), rather than
  building mode-specific hardware demodulators.
- Use every listed part for a role it's actually good at, rather than
  forcing one universal signal path.

### Why "2× ADC" and "2× DAC" drives the whole design

Two ADCs and two DACs is exactly what an **I/Q (quadrature) transceiver**
needs: one converter per channel (I and Q), on both RX and TX. Everything
below is built around that fact. A single-ADC/single-DAC "real-sampling"
SDR is simpler but throws away image rejection and halves usable
instantaneous bandwidth for the same sample rate — with two converters
per direction already in hand, I/Q is strictly better and costs nothing
extra.

## 2. Why one LO chain isn't enough

- **ADF4351**: tunes 34.4 MHz – 4.4 GHz. It **cannot** synthesize below
  ~34 MHz, so it cannot be the LO for HF (0–30 MHz), which is where most
  of the interesting weak-signal/ham/shortwave activity is.
- **AD9850**: clean, agile DDS but only usable to roughly 40 MHz output
  (Nyquist/filtering limited on a 125 MHz clock), and its output level
  and spectral purity are far below the ADF4351's at VHF+.

So the design uses **two front-end paths sharing the same digital
backend and converters**, switched at RF:

```
                         ┌─────────────────────────────┐
   HF antenna ───────────┤   HF direct-conversion path  ├──┐
                         │   LO = AD9850 (0–40 MHz)      │  │
                         └─────────────────────────────┘  │
                                                            ├──► I/Q mux ──► 2×AD9226 (RX)
                         ┌─────────────────────────────┐  │            2×DAC902E (TX)
 VHF/UHF/µW antenna ─────┤  Superheterodyne path         ├──┘
                         │  LO = ADF4351 (34 MHz–4.4 GHz) │
                         │  + RF mixer(s) to fixed IF     │
                         └─────────────────────────────┘
```

This gives continuous-ish coverage from near-DC/HF through microwave,
using each synthesizer only where it's actually good, and reuses the
same pair of ADCs/DACs and the same PL DSP chain for both paths.

## 3. Path A — HF direct-conversion (0–30 MHz, extendable to ~40 MHz)

Zero-IF (direct conversion) quadrature architecture:

```
RX:  BPF/LPF → LNA → I/Q mixer (LO: AD9850, 0°/90° via divide-by-4
     or polyphase network) → I/Q low-pass (anti-alias) → 2×AD9226

TX:  2×DAC902E (I/Q baseband) → reconstruction LPF → I/Q mixer
     (same AD9850 LO, TX side) → BPF → PA → antenna
```

- **LO quadrature generation**: AD9850's DDS core can output sine and
  cosine simultaneously is *not* available on the standard AD9850
  module (single output). Generate quadrature instead with a
  **divide-by-4 flip-flop network** fed from an AD9850 output run at
  4× the desired LO frequency (limits usable LO to ~10 MHz that way), OR
  use a **90° polyphase RC network** at the actual LO frequency (works
  over a narrower band but no 4× multiplication penalty). Recommendation:
  polyphase network per sub-band (e.g. 1.8–2, 3.5–4, 7, 10, 14, 18–21,
  24–28 MHz ham-band-style segments) — simplest and keeps AD9850 output
  frequency equal to the actual LO.
- **Anti-alias filtering**: AD9226 at, say, 50–65 MSPS gives tens of MHz
  of alias-free baseband — plenty for HF I/Q at zero-IF, so a simple
  low-pass around 30–40 MHz ahead of each ADC suffices.
- **Direct-conversion caveats to design around**: DC offset from LO
  leakage self-mixing, and I/Q gain/phase imbalance. Both are corrected
  digitally (DC-notch/servo + I/Q gain-phase calibration) in the PL —
  see §6. This is standard practice (same technique used in most
  low-cost SDR direct-conversion receivers).

## 4. Path B — Superheterodyne (approx. 30 MHz – multiple GHz)

```
RX:  BPF (band-select) → LNA → RF mixer → fixed IF (e.g. 45 or 70 MHz)
     → IF BPF (image reject, done before the mixer + after) → IF amp
     → quadrature sampling (see below) → 2×AD9226

TX:  2×DAC902E (I/Q at low IF, e.g. a few MHz) → reconstruction filter
     → I/Q-to-IF mixer or direct IF DAC output → RF mixer (up-convert
     with ADF4351 LO) → BPF (harmonic/image reject) → PA → antenna
```

- **LO**: ADF4351, fed from a stable reference (TCXO/OCXO recommended;
  the EBAZ4205's onboard oscillator or an external reference into the
  ADF4351's REFIN can be used — phase noise here sets the whole
  receiver's reciprocal-mixing performance, so this is worth a
  higher-grade reference even though it's not in the current BOM).
- **Image rejection**: classic superhet weak point. Since the LO is
  high-side or low-side of a wide RF range, front-end band-pass
  filtering (a switched filter bank keyed to the target band) is
  required ahead of the mixer — this is what the "other filters" in the
  BOM are for. Plan on a bank of BPFs (e.g. covering 30–54, 54–108,
  108–174, 174–450, 450–900, 900–2000+ MHz, chosen based on which
  filters you actually have) selected via RF switch or relay under PL
  GPIO control.
- **Getting I/Q from a single IF with two ADCs — Quadrature Sampling
  Detector (QSD)**: rather than adding a second (IF) mixer stage, clock
  the two AD9226s from clocks that are phase-shifted by 90° of the IF
  period (i.e., clock skew = 1/(4·F_IF)). Sampling the same IF signal on
  both ADCs but staggered by a quarter IF-cycle yields I and Q directly
  in the digital domain — no analog I/Q mixer needed on the IF side.
  This is the same principle used in the Perseus/SDR-IQ/SDR-14 class of
  receivers and reuses the Zynq's clock resources (MMCM/PLL in the PL
  can generate the two phase-shifted ADC clocks precisely). This is the
  **recommended** approach since it needs one mixer per direction
  instead of two, and pushes the I/Q generation into the (easily
  recalibrated) digital domain.
  - Alternative: analog I/Q mixer at IF using a second mixer + 90°
    hybrid, if you'd rather keep the ADC clocks simple. More parts, more
    analog calibration.
- **TX up-conversion**: DAC902E pair synthesizes I/Q at a low IF
  (a few MHz, well within its 125 MSPS Nyquist band), which single-mixer
  up-converts using the same ADF4351 LO used for RX (half-duplex,
  time-shared) or a second ADF4351 channel if full-duplex is later
  desired.

## 5. Frequency plan summary

| Band | Path | LO source | Notes |
|---|---|---|---|
| ~0–30(–40) MHz | A: direct conversion | AD9850 + polyphase | Ham/shortwave/broadcast HF, CW/SSB/AM/digital |
| ~30 MHz – 4.4 GHz | B: superheterodyne | ADF4351 + mixer(s) | VHF/UHF/low microwave; limited by mixer, filter bank, and PA/LNA bandwidth in hand |
| Above ADF4351 range | — | — | Would need an additional external LO/mixer stage; out of scope until parts are added |

TX power and linearity above VHF will realistically be limited by
whatever "other amps" you have on hand — the digital/converter chain
does not limit TX frequency the way it limits RX, since the ADF4351 LO
range is the actual ceiling either way.

## 6. Digital backend (Zynq-7010 on EBAZ4205)

### PL (FPGA fabric)
- ADC capture: 2× parallel-CMOS interfaces from AD9226 into IDDR/ISERDES
  as needed, feeding into a shared AXI-Stream I/Q pair.
- DDC (digital down-conversion): NCO + CIC + FIR decimation chain per RX
  channel pair, to bring the ADC's tens-of-MHz Nyquist band down to a
  host/DSP-manageable I/Q rate (e.g. decimate to 192–1024 kHz complex,
  tunable).
- DUC (digital up-conversion): mirror of the above feeding the two
  DAC902E channels.
- DC-offset removal and I/Q gain/phase calibration blocks for Path A.
- Clock generation: MMCM-derived ADC sample clocks, including the
  90°-shifted pair for Path B's QSD technique (§4).
- Control interfaces: SPI master for ADF4351 and AD9850 register
  writes, GPIO for band-select relays/RF switches and TX/RX (PTT)
  switching.

### PS (Cortex-A9, Linux)
- Linux (PetaLinux/Yocto or an existing EBAZ4205 board support package)
  driving the PL over AXI.
- Streams the decimated I/Q to a host (Ethernet/USB, whichever the
  EBAZ4205 exposes) using a standard SDR I/Q transport so **any**
  mode/protocol can be implemented in host software (GNU Radio,
  SDR#-style app, custom demod) instead of being baked into hardware.
  This is what makes "all modes" a software, not hardware, property of
  the design.
- Alternatively, for a self-contained transceiver (no host PC), run
  mode-specific DSP (SSB/CW/FM/AM demod, digital-mode modems) directly
  on the PS/PL, exposing only audio + control — a later-phase option
  once the RF chain and basic I/Q streaming work.

## 7. Key risks / open design items

1. **I/Q image rejection budget** — both paths depend on I/Q balance;
   plan on a calibration routine (inject a known tone, solve for
   gain/phase correction) rather than expecting analog perfection.
2. **LO phase noise** — a noisy ADF4351 reference will show up directly
   as reciprocal mixing / raised noise floor across the whole
   superheterodyne path; budget for a better reference than a generic
   crystal if performance matters.
3. **Front-end filter bank** — image rejection above 30 MHz is only as
   good as the switched BPFs available; audit what filters you actually
   have and map them to achievable sub-bands before assuming full
   VHF–microwave coverage.
4. **ADC/DAC dynamic range** — 12 bits (~72 dB theoretical, less in
   practice) is modest for a wideband HF receiver sharing a strong
   band with a weak one; front-end attenuation/AGC and careful gain
   distribution will matter more than in a 14/16-bit design.
5. **Half vs. full duplex** — sharing one ADF4351 between RX and TX
   upconversion means half-duplex by default; full duplex needs a
   second synthesizer or careful LO distribution.
6. **DAC902E identification** — "DAC902E" commonly refers to an
   AD9762-based breakout module; confirm the exact DAC part on your
   boards, since output swing, clocking, and Nyquist limit depend on it.

## 8. Phased build & test roadmap

1. **Bring-up**: EBAZ4205 boots Linux/bare-metal, PL loads a trivial
   design, confirm AXI access to a test peripheral.
2. **Converter interfaces**: get one AD9226 sampling a known test tone
   into the PL and one DAC902E outputting a known tone from the PL —
   no RF chain yet, just digital I/O validation.
3. **Synthesizer control**: SPI-control the ADF4351 and AD9850
   independently, verify output frequency/level on a spectrum
   analyzer/counter.
4. **Path A (HF direct conversion) first** — it's the simpler path
   (one mixer stage, lower frequencies, more forgiving filters). Get
   RX I/Q working, verify with a known HF signal, then add DC/IQ
   calibration, then bring up TX.
5. **Path B (superheterodyne)** — validate the QSD clocking technique
   on the bench before committing to it, since it's the least
   conventional piece; fall back to an analog IF I/Q mixer if the
   clock-domain approach proves unreliable on this FPGA.
6. **Software chain / mode support** — once I/Q streams reliably in
   both directions, "all modes" becomes a GNU Radio flowgraph /
   host-DSP exercise rather than further hardware work.
7. **Integration** — band-select switching, PTT sequencing, full RF
   path from antenna to antenna, on-air test.

Each phase should be validated independently before moving to the
next; the two front-end paths are intentionally decoupled so Path A can
produce a working (if narrowband-coverage) transceiver well before
Path B's wider but harder RF chain is complete.
