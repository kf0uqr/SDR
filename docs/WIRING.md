# Wiring reference: EBAZ4205 ↔ AD9226 / AD9850-class DDS

This is real, verified pin data pulled from the actual (uncommented) Vivado
constraint files and hardware photos in the reference projects — not a
guess from datasheets alone. Sources are cited per section so you can
cross-check against your own boards.

**Before wiring anything from this doc**: your AD9226/AD9850 breakout
modules may be a different revision than the ones photographed in these
reference projects (common on cheap, multi-seller Chinese modules).
Verify silkscreen labels on your actual boards against the pinouts below
before connecting power.

## 1. EBAZ4205 expansion headers

The board exposes (at least) three 20-pin expansion headers, labeled on
silkscreen as **DATA1**, **DATA2**, **DATA3**. Reference projects use:

| Header | Used for | Project |
|---|---|---|
| DATA1 | HDMI/TMDS, I2S audio, PS/2 (unrelated to this project) | guido57/EBAZ4205_SDR_spectrum |
| DATA2 | AD9851 DDS control lines | guido57/EBAZ4205_SDR_spectrum (`AD9851_test`) |
| DATA3 | AD9226 ADC data bus + clock | wallufo/EBAZ4205_SDR |

**Confirmed from a photo of the user's actual board** (2026-09,
silkscreen text `EBAZ4205`, Zynq `XC7Z010CLG400ABX1733`): all three
headers are present in that order along the right edge of the board,
and each has `GND` / `12V IN` silkscreened immediately next to it —
i.e. there's a 12 V rail routed near each header, not just signal pins
inside the 20-pin block. This means the AD9226 modules may be powerable
from that rail instead of a fully separate bench supply, **if** the
module's onboard regulator accepts 12 V input — check the module's own
input rating before relying on this (see §8's checklist).

Also visible and confirmed on this board: a microSD slot (supports the
SD-boot path assumed in `docs/BRINGUP.md`), a Winbond NAND flash chip
(the board's other/default boot option, per the base PS7 MIO
configuration in `vivado/create_project.tcl` — irrelevant if you stick
with SD boot), `J7` silkscreened `VCC RXD TXD GND` (the UART console
connector, in that pin order), and `J5` silkscreened `GND VCC SPEED PWM`
(a fan connector, unrelated to the RF wiring).

Only pins 5–9, 11, 13–20 of each 20-pin header appear in any constraint
file seen so far — **pins 1–4, 10, and 12 are presumably power/ground
rails** (common on this style of header) but that is inferred, not
confirmed from a schematic. The `GND`/`12V IN` silkscreen text confirms
*some* pins nearby carry power, but not yet which specific numbered
pins — see §8 for how to pin that down with a multimeter.

## 2. DATA3 header → AD9226 (Chain A, ADC #1)

Source: `wallufo/EBAZ4205_SDR`, `Zynq/capture-test/capture-test.srcs/constrs_1/imports/new/ebaz4205.xdc`
(the same table also appears, commented out for reference, in
`guido57/EBAZ4205_SDR_spectrum`'s `AD9851_test` project).

| FPGA package pin | I/O standard | Signal | DATA3 header pin | AD9226 side |
|---|---|---|---|---|
| M19 | LVCMOS33 | `ADC_in[0]` | DATA3_5 | D0 |
| N20 | LVCMOS33 | `ADC_clk_64M` | DATA3_6 | ADC sample clock (driven BY the FPGA, not from the ADC) |
| P18 | LVCMOS33 | `ADC_in[2]` | DATA3_7 | D2 |
| M17 | LVCMOS33 | `ADC_in[1]` | DATA3_8 | D1 |
| N17 | LVCMOS33 | `ADC_in[4]` | DATA3_9 | D4 |
| P20 | LVCMOS33 | `ADC_in[3]` | DATA3_11 | D3 |
| R18 | LVCMOS33 | `ADC_in[6]` | DATA3_13 | D6 |
| R19 | LVCMOS33 | `ADC_in[5]` | DATA3_14 | D5 |
| P19 | LVCMOS33 | `ADC_in[8]` | DATA3_15 | D8 |
| T20 | LVCMOS33 | `ADC_in[7]` | DATA3_16 | D7 |
| U20 | LVCMOS33 | `ADC_in[10]` | DATA3_17 | D10 |
| T19 | LVCMOS33 | `ADC_in[9]` | DATA3_18 | D9 |
| V20 | LVCMOS33 | `OTR` | DATA3_19 | OTR (over-range flag) |
| U19 | LVCMOS33 | `ADC_in[11]` | DATA3_20 | D11 (MSB) |

That's the full 12-bit data bus (D0–D11) + sample clock + OTR = 14
signal wires — matching the "16 wires ADC ↔ FPGA (PL)" ribbon cable
shown in that project's hardware photo (the extra 2 conductors are most
likely a ground reference and possibly one spare/unused).

**Key point**: the FPGA *drives* the 64 MHz sample clock to the AD9226
— the ADC does not free-run — so the PL must generate this clock (an
MMCM output, per `docs/ARCHITECTURE.md` §6) before the ADC will produce
valid data.

For **ADC #2** (Chain B's IF sampler in our design, not present in the
single-ADC reference projects), duplicate this same bus structure on a
second header/set of GPIO pins — DATA1 is otherwise unused by the SDR
projects and is the natural candidate if its pins aren't needed for
display/audio in your build, but confirm it's wired as generic GPIO on
your specific board before committing to it.

## 3. DATA2 header → AD9851/AD9850-class DDS

Source: `guido57/EBAZ4205_SDR_spectrum`, `AD9851_test/AD9851_test.srcs/constrs_1/new/ebaz4205.xdc`.

| FPGA package pin | I/O standard | Signal | DATA2 header pin | DDS side |
|---|---|---|---|---|
| G19 | LVCMOS33 | `AD9851_sd_out` | DATA2_7 | Serial data (W-CLK/serial load bit, DDS "D7"/serial-mode data pin) |
| H20 | LVCMOS33 | `AD9851_clock_out` | DATA2_8 | W_CLK (word load clock) |
| J19 | LVCMOS33 | `AD9851_fq_ud_out` | DATA2_9 | FQ_UD (frequency update strobe) |
| K18 | LVCMOS33 | `AD9851_pwm_out` | DATA2_11 | Reset or a PWM-derived control line (confirm against your module's silkscreen — name suggests PWM-based control, not a standard AD9850/9851 pin, possibly driving an RC-filtered analog control voltage on that specific breakout) |

This is the AD9851 (a close sibling of your AD9850 — same serial-load
protocol, AD9851 just adds a ×6 reference multiplier and goes higher in
frequency). **Your AD9850 module's serial interface is pin-compatible**:
W_CLK, FQ_UD, D7 (serial data), and RESET are the standard four control
lines. Map:

| AD9850 standard pin | Use this DATA2 mapping |
|---|---|
| D7 (serial data) | `AD9851_sd_out` → DATA2_7 |
| W_CLK | `AD9851_clock_out` → DATA2_8 |
| FQ_UD | `AD9851_fq_ud_out` → DATA2_9 |
| RESET | `AD9851_pwm_out` → DATA2_11 *(verify — see caveat above)* |

Confirm the 4th line against your specific AD9850 module's silkscreen
before wiring — if it's labeled `RESET` you're fine with the mapping
above; if the guido57 project is instead driving something PWM-specific
to their module, you may need only 3 of these 4 lines for a standard
AD9850 (RESET can often be tied to a GPIO you control directly instead).

## 4. AD9226 module: power and input conditioning

**Confirmed from a photo of the user's actual module**: it's essentially
the same board as the one in `wallufo/EBAZ4205_SDR`'s reference photos —
identical silkscreen (`AD9226 12-BIT 65MSPS`) and matching component
references (R1–R35, C1–C43, U1/OEB/3V3 test point layout), so the
modification table below should apply close to component-for-component
rather than needing re-derivation.

- **Power**: this specific module is silkscreened `GND+5V` at both its
  green screw terminal (P1) and on two pins of its own signal header
  (P2) — it wants a regulated **5V** supply, not the EBAZ4205 DATA
  header's 12V rail noted in §1. Feed it 5V into the P1 terminal block;
  don't wire the header's `GND+5V` pins to the board's `12V IN` — that's
  a voltage mismatch, not just an alternate supply point.
- **Header pinout confirmed**: the module's own P2 header is silkscreened
  `GND, OTR, D0–D11, CLK, GND+5V` — matching the DATA3 pin table in §2's
  signal set, one row carrying the even data bits + OTR and the other
  the odd bits + CLK, consistent with how `wallufo`'s ribbon cable maps
  to `DATA3_5`–`DATA3_20`.
- **RF input**: already a proper SMA connector on the module — no extra
  connector work needed before this feeds from a filter/antenna.
- **OEB must be tied low**: AD9226's `OEB` (output-enable, active low)
  pin needs to be grounded (or pulled low) for the ADC to actually drive
  its output bus — if bring-up wiring looks correct but
  `adc1_valid_sync`/`adc1_data_sync` never show sensible values in the
  ILA (`docs/BRINGUP.md` Phase 2), check continuity from the module's
  `OEB` pad to ground before suspecting the FPGA side.
- **Output format strap**: AD9226 modules typically have a two's-
  complement vs. offset-binary output select (often a resistor/jumper
  near the ADC's `OEB`/format pin) — on this module that's the
  **R32–R35 cluster** bottom-left near U1, the same location the
  reference project's own docs flagged
  (`AD9226 two's complement settings.jpg`). Populated/unpopulated status
  isn't readable at normal photo resolution — a tight macro shot of just
  that resistor cluster would let this be confirmed exactly; until then,
  check which format your HDL sampler expects and treat a wrong guess as
  low-risk (bit-inverted/offset values that still "work" but read wrong,
  not a hardware fault).
- **Recommended input-conditioning modification** (from
  `AD9226 board original schematic.png` vs.
  `AD9226 board modified schematic.png` in that repo): the stock
  AD8138-based differential driver on these modules is configured for
  a lab ADC-eval use case, not a 50 Ω antenna/RF input. The reference
  project's modification, which we'd recommend replicating:

  | Component | Stock value | Modified (RF-input) value |
  |---|---|---|
  | R2, R14 (AD8138 feedback) | 200 Ω | 2200 Ω |
  | R8, R13 (AD8138 gain-set) | 200 Ω | 390 Ω |
  | R6 | 75 Ω | 56 Ω |
  | R7 | 3000 Ω | *(removed)* |
  | R3 | 62 Ω | *(removed, replaced by R1 = 51 Ω)* |
  | R16 | 51 Ω | 56 Ω |
  | — | — | + C1 = 0.1 µF DC-blocking cap in series with the RF input |
  | — | — | + D1, D2 = 1N4148 diodes to ground for input overvoltage clamping |
  | — | — | + C2 = 0.1 µF added at the D- bias node |

  This changes the front-end gain and adds DC blocking + simple diode
  protection appropriate for a 50 Ω antenna feed instead of a bench
  signal generator — worth doing on both of your AD9226 modules before
  connecting an antenna, to protect the ADC input from static/overload
  and to get the right full-scale input level. Treat the exact resistor
  values as a starting point to verify against your module's actual
  schematic (silkscreen part references may differ) rather than blindly
  matching by position.

## 5. DAC902E module (Chain A/B TX)

**Correction from closer photos**: the DAC chip itself (`U2`) is now
legible — marked **`DAC902E 9AARHEK`** directly on the package. So
"DAC902E" is the actual chip part number, not just a board/module name
as assumed earlier. The connector pinout (below) confirms it's a
**12-bit** data bus (`B1`–`B12`), not the 14-bit AD9767-class part
guessed in the previous revision of this doc — that guess is now
superseded. The board's "DAC 165MHz" silkscreen still stands, so: 12-bit
resolution, ~165 MSPS clock — narrower than a 14-bit part would have
been, but still meaningfully faster/wider-Nyquist than the originally-
assumed 125 MSPS AD9762-class part.

Board layout, all silkscreened directly on the module:

- **`J1` (`CLK`)**: a dedicated SMA jack for the DAC's sample clock.
  **This is different from the AD9226 modules**, which take their
  sample clock over the header — the DAC902E instead expects the clock
  delivered as a proper RF/coax signal. This means the PL's DUC sample
  clock needs to leave the FPGA through a clock buffer/driver capable of
  driving 50 Ω coax (not a bare GPIO pin wired straight to a header, the
  way `ADC_clk_64M` works for the AD9226) — budget for a small clock
  distribution buffer IC (or at minimum an RF buffer amp) between the
  FPGA's MMCM output and this SMA input. This wasn't accounted for in
  the original hardware-budget list (`docs/ARCHITECTURE.md` §5) — add
  it.
- **`P3` (`V+` / `GND`)**: a 2-pin screw terminal for module power.
  Unlike the AD9226 module, the voltage isn't printed here (just `V+`,
  no number) — check the module's regulator/LDO markings or measure its
  input range before connecting a supply; don't assume 5V by analogy
  with the AD9226 module.
- **`J2` (`OUT`)**: SMA RF output, after an on-board reconstruction
  filter/transformer network (visible inductors/caps around `L1`-`L5`,
  `U1`) — ready to feed a mixer, filter, or PA input directly via coax,
  no extra output conditioning needed to get started.
- **Data bus connector — confirmed pinout**: a 14-pin (2×7) black IDC-
  style box header, silkscreened directly on the board's back side:

  | Row A | Row B |
  |---|---|
  | `CLK` | `B12` |
  | `PW` | `B11` |
  | `B1` | `B10` |
  | `B2` | `B9` |
  | `B3` | `B8` |
  | `B4` | `B7` |
  | `B5` | `B6` |

  I.e. the 12-bit data bus is `B1`–`B12` across both rows, plus `CLK`
  and `PW` on the header (in addition to the dedicated `CLK` SMA jack
  and the `V+`/`GND` screw terminal already covered above).

  - **Bit order (`B1`=LSB vs. MSB) is an assumption, not labeled as
    such** — `B1`/`B12` follow the same low-to-high naming convention as
    the AD9226's `D0`/`D11`, but confirm by testing once the DUC is
    driving it: if the output frequency looks like a scrambled/aliased
    version of what you commanded, try reversing the bit order before
    suspecting anything else.
  - **`PW`**: likely a power-down/sleep control input common on this
    DAC family (not a power *supply* pin — that's the separate `V+`/
    `GND` terminal), rather than a data or power line. Tie it to the
    level that means "normal operation, not powered down" (commonly
    logic low, but confirm against the DAC902E's own datasheet if you
    can find one, or by testing) — don't leave it floating.
  - **`CLK` on the header vs. the `J1` SMA jack**: both exist on this
    board. They're most likely the same clock net, with the header pin
    there for probing with a scope/logic analyzer while the SMA jack is
    the intended signal-injection point (it has a proper 50 Ω
    connector; the header pin doesn't). Use the SMA path as the primary
    clock input per §5's original guidance above; treat the header
    `CLK` pin as a monitor point, not a second required connection,
    unless testing shows otherwise.

## 6. ADF435x eval board (Chain B LO)

From a photo of the user's actual board: silkscreened **"ADF435X EVAL
BD"** (a generic Chinese eval board, maker mark "NWDZ"), chip `U1`
marked `ADF...` (exact suffix — 4350 vs. 4351 — not fully legible; the
architecture doc's 34.4 MHz–4.4 GHz range assumes ADF4351, confirm
against the full chip marking if it matters later).

- **Control interface — confirmed 3.3V logic**: a header silkscreened
  (two rows) `LD / CLK / LE / CE / GND` and `PDR / MUX / DAT / GND /
  3V3`:

  | Pin | Function |
  |---|---|
  | `LE` | Latch Enable (SPI-style chip select for the register-load interface) |
  | `CLK` | Serial clock |
  | `DAT` | Serial data in (MOSI) |
  | `LD` | Lock Detect (output — high once the PLL is locked) |
  | `CE` | Chip Enable (power control — must be held high for normal operation) |
  | `MUX` | Muxout (status/readback output, function set by register config) |
  | `PDR` | Unclear — possibly a power-down control distinct from `CE`; not a standard ADF435x pin name, flag for the seller's own documentation or continued testing rather than guessing |
  | `3V3` | Digital I/O reference — **confirms the control interface runs at 3.3V logic**, directly compatible with the Zynq's 3.3V PS/PL I/O banks with no level-shifting needed |
  | `GND` | Ground (appears on both rows) |

  This is good news: the SPI-style control (`LE`/`CLK`/`DAT`) can be
  driven straight from PL GPIO/SPI-like bit-banging at 3.3V, same as
  planned for the AD9850 in §3.

- **Reference clock — two paths, and this is where the TCXO/OCXO
  upgrade from `docs/ARCHITECTURE.md` §5 (budget item #1) actually
  connects**: the board has its own onboard 25.000 MHz crystal (`X1`)
  feeding the ADF435x's `REFIN`, **and** a separate SMA `MCLK` input
  jack. If that `MCLK` input lets an external reference override
  the onboard crystal (typical for eval boards like this), that's the
  injection point for a better external TCXO/OCXO reference later —
  confirm by checking whether a signal on `MCLK` actually overrides
  `X1`, or whether both feed in some combined way, before assuming
  either behavior.

- **LO output — connectors confirmed SMA**: a clearer photo confirms
  `+LO`, `-LO`, and `MCLK` are all proper threaded SMA jacks, same as
  the AD9226/DAC902E modules — ordinary coax cables work directly, no
  connector-type concern (an earlier revision of this doc misjudged
  these as test-point pins from a worse angle; disregard that).
  - The one real remaining item: `+LO`/`-LO` are still a **differential**
    pair (consistent with the ADF4351's RFOUT structure). **Confirmed
    from the user's actual mixer module (§7): its `RF_LO` port is
    single-ended**, so a balun/transformer to combine `+LO`/`-LO` into
    single-ended 50 Ω is genuinely needed here, not just a "check your
    mixer" hedge — there's no differential-LO escape hatch with this
    specific mixer. Using only `+LO` alone and leaving `-LO`
    unterminated will work after a fashion but wastes half the output
    power and degrades harmonic performance; not recommended as a
    permanent solution. Add a balun to the hardware-budget list
    (`docs/ARCHITECTURE.md` §5) if one isn't already on hand.
- **Power**: a separate `DC5V` barrel jack — same external-supply
  pattern as the AD9226 and DAC902E modules, not header-powered.

## 7. RF mixer module (Chain B)

From a photo of the user's actual mixer: a small shielded module (metal
can over the mixer die/PCB) with three single-ended SMA ports,
silkscreened directly on the board:

| Port | Function |
|---|---|
| `RF_IN` | RF input (bottom) |
| `RF_LO` | LO input (right) |
| `RF_IF` | IF output (left) |

All three are **single-ended SMA** — this is what confirms the balun
requirement noted in §6 for feeding the ADF435x's differential `+LO`/
`-LO` output into this mixer's `RF_LO` port.

- **Passive vs. active — not determined from the photo**: the shielded
  can hides whether this is a passive double-balanced mixer (which
  works in either direction, so the same module could plausibly serve
  both Chain B's RX downconversion and TX upconversion per
  `docs/ARCHITECTURE.md` §4) or an active mixer IC (typically one
  direction only, RX). Don't assume bidirectional operation without
  confirming — check for any part markings on the shield itself (a can
  removed briefly, or a macro shot of any visible marking, would
  resolve this), or test it in one direction first and treat the
  reverse direction as unverified until tried.
- If a second mixer is needed for a separate TX path (i.e., this one
  turns out to be RX-only), that becomes a hardware-budget item not
  currently listed in `docs/ARCHITECTURE.md` §5 — worth flagging once
  the passive/active question is resolved.

## 8. What's still unverified — continuity-check procedure

Do these with a multimeter in continuity/diode-test mode, board
**unpowered**, before wiring anything permanently. Report back what you
find and I'll fold it into this doc and the XDC.

1. **Find pin 1 on each header.** Look for a square pad (vs. round pads
   for the rest), a silkscreen dot/arrow, or a "1" printed near one end
   of the DATA1/2/3 headers. This tells us which physical end
   `DATA3_5` etc. actually starts from — the tables in §2/§3 give pin
   *numbers*, not a physical left/right position, and Vivado only cares
   about the FPGA package pin (already correct), but *you* need this to
   avoid plugging a cable in backwards.
2. **Identify the power pins.** With one probe on a known ground point
   (e.g. the Ethernet jack's metal shield, or the DC barrel jack's
   outer sleeve) and the other probing each of DATA3 pins 1–4, 10, 12
   in turn: note which read as continuous with ground (0 Ω-ish) — those
   are GND pins. Then, with the board powered and a multimeter in DC
   voltage mode (careful — board now live), check the remaining
   candidates (1–4, 10, 12 minus whichever tested as GND) for ~12 V,
   ~5V, or ~3.3V relative to ground. Repeat for DATA1 and DATA2 if you
   plan to use them too.
3. **Check the AD9226 module's supply input rating** (its own
   silkscreen near the power terminal, or its regulator IC's datasheet)
   against whatever voltage you found in step 2 — only wire it to the
   header's power pin if the module accepts that voltage directly;
   otherwise keep using a separate bench supply as §4 originally assumed.
4. **Confirm the AD9226 output format strap** (§4) — look for a
   populated 0 Ω resistor or jumper near the ADC labeled something like
   a format/OEB select, and compare its position to
   `AD9226 two's complement settings.jpg` from the reference repo if you
   can get eyes on that file.
5. **Confirm your AD9850 module's 4th control line** (§3) — check its
   silkscreen for a pin labeled `RESET` near the D7/W_CLK/FQ_UD trio.

Also still open, lower priority:

- Whether your specific AD9226 and AD9850 module revisions match the
  pinout/component layout shown in the reference photos — cheap modules
  from different sellers sometimes differ.
- Physical connector gender/pitch on the DATA headers (photos show a
  ribbon/jumper cable but not the header's pitch or keying) — bring a
  spare header/cable when you go to wire this up, or measure pin pitch
  with calipers.

## Sources

- https://github.com/wallufo/EBAZ4205_SDR (AD9226 capture, real XDC + schematics)
- https://github.com/guido57/EBAZ4205_SDR_spectrum (AD9851 control XDC, block diagram)
- https://github.com/guido57/EBAZ4205 (board bring-up notes)
- https://github.com/KeitetsuWorks/EBAZ4205 (base board XDC/PetaLinux reference)
