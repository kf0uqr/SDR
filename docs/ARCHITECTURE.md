# SDR Transceiver — System Architecture

## 0. Prior art this design builds on

Two existing EBAZ4205 projects are the starting point and de-risk the core
receive path:

- [`guido57/EBAZ4205_SDR_spectrum`](https://github.com/guido57/EBAZ4205_SDR_spectrum) —
  0–32 MHz spectrum/waterfall display, HF tuning (AM/LSB/USB), FT8
  decode. PL drives HDMI/DMA; PetaLinux + Qt5 apps do the rest.
- [`wallufo/EBAZ4205_SDR`](https://github.com/wallufo/EBAZ4205_SDR) — the
  simpler of the two: **one AD9226**, clocked at **64 MHz** by the PL,
  sampling 0–32 MHz directly (first Nyquist zone, no mixer, no LO). The
  PS runs a TCP server streaming raw frames (16384 samples/frame) to a
  Python host app that draws spectrum/waterfall.

The key fact both projects confirm: **for HF, you don't need a mixer or
an LO at all.** 32 MHz is comfortably under half of a 64 MSPS clock, so
the AD9226 just direct-samples the antenna signal (after a low-pass
anti-alias filter) and everything from 0–32 MHz shows up undistorted in
the first Nyquist zone. That's a proven, working starting point — this
design extends it rather than replacing it with something unproven.

This supersedes the first draft of this document, which assumed an I/Q
(quadrature) architecture built around a 90°-sampling trick. That's
dropped in favor of the simpler, already-proven **real-sampling**
approach below, which needs less analog hardware and less novel FPGA
work to get right.

See [`docs/WIRING.md`](WIRING.md) for the actual pin-level wiring
(EBAZ4205 header pins ↔ AD9226/AD9850) pulled from these reference
projects' real constraint files and hardware photos.

## 1. Goals and constraints

- **Widest practical frequency coverage** for both RX and TX.
- **"All modes"**: CW, SSB, AM, FM, digital modes — a software property.
  A single real-valued ADC/DAC stream still carries full phase
  information for everything in its Nyquist band; SSB/CW demod and
  generation is done with a digital Hilbert transform + NCO (a "phasing"
  or "third method" SSB implementation), not by needing an analog I/Q
  front end. This is standard practice in real-sampling SDRs.
- **Small hardware budget available** — used below to fill the specific
  gaps the on-hand parts can't cover on their own (mainly: a
  low-VHF/HF gap-filler LO, a reference oscillator, filters/switches,
  and RF buffering/amplification).
- Use every listed part for a role it's actually good at.

### Why real sampling instead of I/Q, given 2× ADC / 2× DAC

The reference projects use a single ADC in real (not quadrature) mode
and get a full 0–32 MHz receiver out of it. Two ADCs and two DACs are
still very useful — just not as a mandatory I/Q pair:

- **ADC #1 / DAC #1**: the HF direct-sampling chain (0–32 MHz and
  beyond via bandpass undersampling, §3) — a direct extension of the
  proven prior art, now including TX.
- **ADC #2 / DAC #2**: an independent superheterodyne chain (§4) for
  VHF/UHF/microwave, sharing the ADF4351/AD9850/mixer hardware.

That means **two simultaneous, independent RX (and, time-shared, TX)
chains** instead of one I/Q chain — arguably more useful for "widest
coverage" than image rejection would have been, and it matches what's
already been proven on this exact board.

## 2. Why one LO/mixer chain isn't enough on its own

- **ADF4351**: tunes 34.4 MHz – 4.4 GHz. Cannot synthesize below ~34 MHz.
- **AD9850**: clean to roughly 40 MHz, but far below ADF4351 output
  level/purity at VHF+.
- **Direct sampling (no mixer)**: works great from 0 MHz up to wherever
  filtering and the ADC's analog input bandwidth allow bandpass
  undersampling (§3) — but doesn't scale indefinitely, and provides no
  band-selectivity beyond whatever filter is in front of it.

So the design keeps **two front-end chains sharing one digital
backend**:

```
                     ┌───────────────────────────────────┐
 HF/low-VHF antenna ─┤  Chain A: direct (band-)sampling    ├─ ADC #1 (RX)
                     │  no LO for 0–32 MHz; bandpass       │  DAC #1 (TX)
                     │  undersampling above that            │
                     └───────────────────────────────────┘

                     ┌───────────────────────────────────┐
 VHF/UHF/µW antenna ─┤  Chain B: superheterodyne            ├─ ADC #2 (RX)
                     │  LO = ADF4351 (34 MHz–4.4 GHz),      │  DAC #2 (TX)
                     │  AD9850 fills the 32–34(–45) MHz gap  │
                     │  + RF mixer(s) to a fixed IF          │
                     └───────────────────────────────────┘
```

Both chains terminate on the same Zynq PL/PS; a host (or the PS itself,
later) can run both simultaneously — e.g. watch the HF bands while also
monitoring a VHF/UHF channel.

## 3. Chain A — direct (band-pass) sampling, 0 MHz up

### RX (proven baseline + extension)

```
0–32 MHz:   LPF (anti-alias, ~32 MHz cutoff) → LNA/attenuator →
            AD9226 #1 @ 64 MSPS, Nyquist zone 1 → PL capture
            (exactly the wallufo/guido57 approach)

Higher segments (optional, same ADC, no extra parts):
            BPF for target segment → AD9226 #1 clocked at the same
            64 MSPS → bandpass-sample in Nyquist zone N (e.g. zone 2 ≈
            32–64 MHz, zone 3 ≈ 64–96 MHz, ...) → PL capture
```

- **Bandpass (undersampling) extension**: this is the standard, no-extra-
  silicon way to stretch a direct-sampling receiver past its baseband
  Nyquist zone — sample a higher band in a higher Nyquist zone, as long
  as (a) a bandpass filter ahead of the ADC rejects everything outside
  the target zone, so aliases don't overlap, and (b) the ADC's analog
  input bandwidth and aperture jitter are good enough at that frequency.
  The AD9226 datasheet's analog bandwidth typically supports useful
  undersampling up to roughly 100–150 MHz with real signal-to-noise
  degradation as you go up — treat each extra zone as a "bonus band,"
  not a guaranteed clean receiver, and validate each one on the bench.
  This needs a **switched filter bank** (see §5 budget) — one BPF per
  target segment, selected by an RF switch/relay under PL GPIO control,
  exactly like Chain B's filter bank, so the two chains can share the
  same filter-bank design/parts if convenient.
- **Demod**: digital Hilbert-transform-based SSB/CW (or simple
  envelope/FM detection) in the PL or on the host from the real ADC
  stream — no analog I/Q needed. This is what makes "all modes" work
  from a single real-valued channel.

### TX (new — the reference projects were RX-only)

```
0–32 MHz direct: PL NCO/DUC → DAC902E #1 @ ~160-165 MSPS → reconstruction
                 LPF (~32 MHz) → driver amp → PA → antenna

Higher segments: same DAC, PL synthesizes the target frequency directly
                 if within DAC902E's clean Nyquist band (roughly to
                 50-60 MHz for good SFDR on a ~165 MSPS part) → BPF →
                 PA → antenna
```

DAC902E's higher speed (~165 MSPS vs. the ADC's 64 MSPS — confirmed
silkscreened "DAC 165MHz" on the user's actual module, see
`docs/WIRING.md` §6) means direct TX synthesis can comfortably cover all
of HF and reach further into low VHF than originally assumed, without
any mixer — likely the best bang-for-buck TX path to bring up first.

## 4. Chain B — superheterodyne (approx. 30 MHz – multiple GHz)

```
RX:  BPF (band-select, switched) → LNA → RF mixer → fixed IF
     (e.g. 10.7, 21.4, or 45 MHz — pick based on filters you can get/have)
     → IF BPF (image reject) → IF amp → AD9226 #2 (direct- or
     bandpass-sampled, same technique as §3) → PL capture

TX:  PL NCO/DUC → DAC902E #2 (IF, within its clean Nyquist band) →
     reconstruction filter → RF mixer (up-convert with LO) → BPF
     (harmonic/image reject) → PA → antenna
```

- **LO selection by band**:
  - **~32–45 MHz RF target** (the gap neither direct sampling nor
    ADF4351 covers cleanly): use **AD9850** as the mixer LO.
  - **~34 MHz–4.4 GHz RF target**: use **ADF4351** as the mixer LO.
  - A simple RF/LO switch (relay or PIN-diode switch) under PL GPIO
    control selects which synthesizer feeds the mixer, so Chain B
    covers the full 32 MHz–4.4 GHz span with one mixer and one IF
    strip.
- **Image rejection**: needs a switched RF band-select filter bank ahead
  of the mixer (see §5 budget) — the limiting factor for how much of the
  ADF4351's range is actually *usable* rather than just theoretically
  reachable.
- **IF frequency choice**: pick something you can get an off-the-shelf
  (or easily home-built) crystal/ceramic filter for — this matters more
  for real receiver performance than almost anything else in Chain B.
- **TX up-conversion**: same LO/mixer, shared with RX (half-duplex by
  default — see risks, §7).

## 5. Suggested use of the hardware budget

Given a small additional budget, in priority order:

1. **TCXO/OCXO reference** for the ADF4351 (and ideally a shared
   reference distributed to the AD9850/clocking too). This sets the
   whole superheterodyne chain's frequency accuracy and reciprocal-mixing
   noise floor — the single highest-leverage purchase.
2. **RF switches/relays** (2–4×, e.g. small SPDT RF relays or a PIN-diode
   switch board) for band-select filter switching on both chains.
3. **Band-pass filter set** — a handful of catalog BPFs (VHF low band,
   VHF high band, UHF, whatever segments match your antennas/interests)
   plus one HF/low-pass filter if not already on hand. Cheap SAW or
   discrete LC filter modules are widely available.
4. **IF filter** for Chain B (crystal or ceramic filter at whatever IF
   you settle on) — narrow enough for SSB/CW selectivity.
5. **RF buffer/driver amps** for the ADC input and DAC output (impedance
   matching, gain to overcome mixer conversion loss) if the "other amps"
   already on hand don't cover these specific spots.
5a. **Clock buffer/driver for the DAC902E's CLK input** — that module
    takes its sample clock via SMA/coax, not a header pin (confirmed
    from the user's module, `docs/WIRING.md` §6), so the PL's DUC clock
    needs a proper 50 Ω-capable driver between the FPGA and each DAC's
    CLK jack, not a bare GPIO wire. A small clock-distribution buffer IC
    or RF buffer amp covers this for both DAC902E modules.
6. **Attenuator pads / step attenuator** for RX front-end gain control —
   12-bit ADCs have limited dynamic range (§7.4), so protecting against
   overload matters more here than in a 14/16-bit design.
7. *(Stretch)* a second ADF4351/synthesizer if full-duplex operation
   becomes a goal later.
8. **Dedicated Raspberry Pi** (4 or 5) as the demod/UI host once the PC-
   based development workflow (§6a) is working — turns the project into
   a standalone box. Not urgent; a PC covers this role during bring-up.

## 6. Digital backend (Zynq-7010 on EBAZ4205)

### PL (FPGA fabric)
- ADC capture for both AD9226s (parallel CMOS into the PL, as in
  wallufo's design, duplicated for the second channel).
- DDC per RX channel: NCO (tunable within the ADC's Nyquist zone) + CIC
  + FIR decimation, producing either a real IF stream (host does
  Hilbert/demod) or a complex baseband stream (Hilbert done in the PL) —
  start with the simpler real-stream path to match the proven prior art,
  add in-PL Hilbert/complex DDC later if host CPU time becomes a
  bottleneck.
- DUC per TX channel: NCO + interpolation feeding each DAC902E.
- Control: SPI master for ADF4351 and AD9850, GPIO for RF-switch/filter-
  bank selection and TX/RX (PTT) sequencing.
- Clock generation: MMCM-derived ADC/DAC sample clocks (64 MSPS class
  for the ADCs, matching the proven design; up to ~165 MSPS for the
  DACs). Note the DAC902E modules take their sample clock via a
  dedicated SMA jack, not a header pin — see `docs/WIRING.md` §6 for
  what that means for driving it from the PL.

### PS (Cortex-A9, Linux)
- Reuse/extend wallufo's approach: PetaLinux + a streaming server
  (TCP or similar) moving raw or lightly-decimated I/Q-or-real samples
  to a host, and accepting control commands back (frequency, mode,
  band-select, PTT) over the same or a second link. The PS's job stays
  deliberately thin: PL register/DMA access and framing samples for the
  network — no demod, no UI, so it stays light regardless of which host
  is on the other end (§6a).

### Demod/UI host — PC now, dedicated Pi later

The Zynq's dual A9 cores are the wrong place to run GNU Radio flowgraphs,
waterfall rendering, or FT8-class decoding — that work belongs on a
separate, more capable host, kept fully decoupled from the Zynq side by
the streaming protocol above:

- **Now (development)**: a PC on the same network (or USB/Ethernet
  direct) runs GNU Radio / the custom Qt5 app (à la guido57) / Python
  tooling against the Zynq's sample stream. This is the fastest path to
  iterate on DDC parameters, demod algorithms, and UI while the RF/PL
  side is still being brought up.
- **Later (deployment)**: swap the PC for a dedicated Raspberry Pi
  (4 or 5) running the identical software stack, turning the whole
  transceiver into a standalone box — no PC required. Because the PS
  only ever speaks a network protocol to "the host," this swap should be
  a non-event: same server on the Zynq, same client software on the new
  host, just a different machine at the other end of the Ethernet cable.
- **Design implication**: keep the Zynq↔host interface protocol-defined
  and host-agnostic from day one (documented sample format, command set,
  transport) rather than anything PC-specific (e.g. avoid X11 forwarding,
  filesystem shares, or other conveniences that only work because it's a
  PC on the bench) — that discipline now is what makes the later Pi swap
  free instead of a rewrite.
- Once on a Pi, self-contained operation (demod/modulate entirely on the
  Pi with the Zynq as a "radio peripheral," audio in/out on the Pi, no
  separate PC ever needed) is the natural end state.

## 7. Key risks / open design items

1. **Bandpass-undersampling limits** — each higher Nyquist zone on the
   AD9226 costs SNR and demands a correspondingly clean filter; treat
   Chain A's "beyond 32 MHz" extension as experimental per-band, not a
   given.
2. **LO phase noise (Chain B)** — reciprocal mixing across the whole
   superheterodyne path depends on the ADF4351's reference; this is why
   the TCXO/OCXO is priority #1 in the budget (§5).
3. **Front-end filter bank** — both chains' real-world selectivity and
   image rejection are bounded by whatever switched filters actually get
   built; this is the most "elbow grease" part of the project.
4. **ADC/DAC dynamic range** — 12 bits is modest; front-end
   attenuation/AGC and careful gain distribution matter more than in a
   higher-resolution design, especially on crowded HF.
5. **Half-duplex on Chain B** — one LO/mixer shared between RX and TX
   means half-duplex by default; full duplex needs a second synthesizer
   (§5, stretch item) or careful LO/filter duplication.
6. **DAC902E part identification** — the user's actual module is
   silkscreened "DAC 165MHz", not the AD9762-class (125 MSPS) part
   originally assumed here; it's more likely AD9767-class (14-bit,
   ~160-165 MSPS), which is better for this design (more headroom, wider
   clean Nyquist band) but the exact chip marking is still unconfirmed —
   see `docs/WIRING.md` §6.
7. **Two ADCs / two DACs running independently** means double the PL
   resource usage (capture, DDC/DUC, clocking) versus a single-channel
   design — worth checking early that the XC7Z010's fabric/BRAM budget
   comfortably fits two of each chain plus whatever's needed for FT8/
   display-style host work.

## 8. Phased build & test roadmap

1. **Reproduce the proven baseline** — bring up wallufo's (or guido57's)
   design as-is: one AD9226, 64 MSPS, 0–32 MHz, streaming to a host.
   This validates the board, toolchain, and PS↔PL↔host data path before
   any new work starts.
2. **Add TX on the same chain** — bring up DAC902E #1 doing direct HF
   synthesis (0–32 MHz), starting with a simple tone, then a PL-generated
   modulated signal. Validate with a receiver/spectrum analyzer.
3. **Second ADC/DAC pair** — duplicate the capture/DDC (and DUC) path
   for ADC #2 / DAC #2, still with no RF front end attached yet — pure
   digital validation that both channels run independently.
4. **Synthesizer control** — SPI-control the ADF4351 and AD9850
   independently; verify frequency/level on a spectrum analyzer or
   frequency counter.
5. **Chain B bring-up** — start with the AD9850-fed gap-filler segment
   (lower frequency, more forgiving), then extend to the ADF4351-fed
   range once the mixer/IF/filter chain is validated at one frequency.
6. **Filter bank and switching** — build/add the band-select filters and
   RF switches from the budget list (§5), wire them under PL GPIO
   control.
7. **Bandpass-undersampling extension on Chain A** *(optional/stretch)*
   — attempt one higher Nyquist zone once the baseline chains work, to
   see how far "widest coverage" can practically go with this ADC.
8. **Mode/software layer** — SSB/CW (Hilbert-based) demod and
   modulation, AM/FM, digital-mode decode (extending guido57's FT8 work)
   — a GNU Radio/host-software exercise once both chains stream
   reliably.
9. **Integration** — PTT sequencing, band-select automation, full
   antenna-to-antenna test on each chain, then together.

Each step should be validated independently; Chain A (direct sampling)
is intentionally brought up first since it's already proven by the
reference projects, giving a working narrowband HF transceiver well
before Chain B's harder superheterodyne RF chain is complete.
