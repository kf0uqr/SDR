# Bring-up: building and running the Phase 1/2 project

This covers the first two steps of the roadmap in `docs/ARCHITECTURE.md`
§8: reproduce the proven baseline, then add AD9226 #1 capture. It uses
the RTL in `hdl/rtl/`, the constraints in `hdl/constraints/ebaz4205.xdc`
(see `docs/WIRING.md` for where those pin numbers come from), and the
project script in `vivado/create_project.tcl`.

**Honesty check**: none of this has been built or simulated yet — there's
no Vivado toolchain available in the environment that wrote it. The RTL
and constraints are low-risk (plain Verilog, pin numbers copied from a
verified working project). The Tcl script's block-design portion
(PS7 clock config, Clocking Wizard, reset) is a reasonable, standard-
pattern starting point but genuinely untested — expect to iterate on it
inside Vivado rather than have it work first try. Where a step is
uncertain, it says so and gives a fallback rather than pretending it's
solved.

Work through this top to bottom. Each unchecked box is one concrete
action or one pass/fail check — don't skip ahead if one fails, since
later steps assume earlier ones actually passed.

## 0. Prerequisites

- [x] Vivado installed — 2026.1, not the reference projects' 2021.2;
      that's fine, the EBAZ4205's Zynq-7010 stays supported across
      Vivado releases, but expect an IP-upgrade prompt on first open of
      `vivado/create_project.tcl`'s generated project (Clocking Wizard,
      PS7, proc_sys_reset are all versioned IP — accept the upgrade).
- [ ] EBAZ4205 board in hand, with pins soldered to its JTAG and UART
      header pads
- [ ] Both FTDI adapter boards in hand with pins soldered (JTAG board
      likely FT4232H, UART board confirmed Adafruit FT232H, per
      photos) — see §1 for wiring
- [ ] One AD9226 module + its own external 5V supply (needed from §3
      onward, not for §2's LED-only check)
- [ ] This repo cloned/available locally where Vivado can reach it

## 1. JTAG and UART adapter setup

The board you're planning to use for JTAG has `ADBUS`/`BDBUS`/`CDBUS`/
`DDBUS` headers and 8 TX/RX activity LEDs — a plain FT2232H only has
two channels (A/B), so this layout is much more likely an **FT4232H
Mini Module** (4 independent channels). The smaller board is a confirmed
**Adafruit FT232H breakout** (silkscreened `FT232H`, "3V logic, 5V
safe, Multi-protocol USB I2C/SPI/GPIO Chip" — a single-channel part,
different from both of the above). Neither is a genuine Xilinx/Digilent
cable, but all of these chips are the same family Digilent's own
HS2/HS3 cables use, so this is a well-trodden path either way — the
chip differences change a few specific details below, not the overall
plan.

- [ ] Use the larger (FT4232H-likely) board for **JTAG**, the Adafruit
      FT232H board for **UART** — as planned.
- [ ] **If it's an FT4232H**: only channels A and B support the MPSSE
      engine that JTAG needs; C and D are UART-only on that chip. Use
      **channel A** (the `ADBUS` header) for JTAG below — don't wire
      JTAG to `CDBUS`/`DDBUS`, it won't work.
- [ ] **Set the board's `VIO` pin** (in the `GND`/`PWR`/`VIO` header
      column next to `ADBUS`) **to 3.3V**, matching the Zynq JTAG bank
      voltage. Mini-module boards like this one set their I/O drive
      voltage from this pin — leaving it floating or at the wrong
      voltage means unreliable JTAG communication at best. Confirm
      what the Zynq's JTAG-adjacent bank actually runs at (3.3V is the
      normal case for this board's PS I/O, per the PS7 MIO config in
      `vivado/create_project.tcl`, but verify rather than assume for
      the specific JTAG pins).
- [x] Locate the JTAG header/pads on the EBAZ4205 — done, pins already
      soldered to the board's JTAG and UART jumpers. (A community
      write-up at theokelo.co.ke/getting-starting-with-ebaz4205-zynq-7000/
      reportedly covers this and general bring-up — worth a read, though
      it couldn't be fetched from here to fold its specifics into this
      doc; flag anything from it worth capturing here.)
- [x] Wire the JTAG board's channel A (`ADBUS`) pins to the EBAZ4205's
      JTAG header (`J8`) using the FTDI chip's **fixed** MPSSE mapping —
      **confirmed by an annotated photo of the user's actual board**,
      matching the predicted mapping exactly:

      | FTDI pin | JTAG signal | EBAZ4205 `J8` pin |
      |---|---|---|
      | ADBUS0 | TCK | `TCK` |
      | ADBUS1 | TDI | `TDI` |
      | ADBUS2 | TDO | `TDO` |
      | ADBUS3 | TMS | `TMS` |
      | `GND` (ADBUS-side power column) | — | `GND`/board ground |

      `J8`'s own silkscreen (confirmed separately) lists its 5 pins as
      `TDI`/`TDO`/`TCK`/`TMS`/`VCC` — wire `VCC` to the FT board's `VCC`
      sense pin if it has one (many JTAG probes use this to sense the
      target's logic level rather than to supply power — don't treat it
      as a power source either direction). Xilinx 7-series JTAG
      programming doesn't need `TRST`.
- [ ] Choose a programming path for the JTAG adapter (pick one):
  - [ ] **Path A (simplest, no Vivado dependency)**: install
        `openFPGALoader`. No EEPROM reprogramming needed — it supports
        generic FT2232H/FT4232H boards for Xilinx 7-series JTAG
        directly.
  - [ ] **Path B (recommended if staying in the Vivado GUI)**: recent
        Vivado versions (2026.1 included) ship an **official
        `program_ftdi` utility** built for exactly this — it reflashes
        FT232H/FT2232H/FT4232H EEPROMs to be Digilent-JTAG-compatible,
        properly (unlike generic `FT_Prog`, which a widely-repeated
        warning says can corrupt a chip's EEPROM if misused — that
        warning is specifically about **genuine Digilent cables**, not
        relevant to these generic boards, but `program_ftdi` is the
        safer, purpose-built tool either way). Run it from Vivado's Tcl
        console or command line per its own `-help`; no separate
        Digilent Adept install needed since it's part of the same
        toolchain already being installed.
        - **Caveat**: some cheap FT2232H/FT4232H boards from AliExpress-
          class sellers ship a smaller EEPROM (128-byte 93C46) than these
          tools expect (256-byte 93C66) — if `program_ftdi` or
          `openFPGALoader` reports an EEPROM size/write error, this is
          the first thing to suspect.
  - [ ] **If the JTAG board is really an FT4232H** (§1's identification):
        its channel A can do JTAG while channel B does UART
        *simultaneously* from the same chip — so `program_ftdi`-style
        configs commonly set up exactly that split (Port A = JTAG,
        Port B = UART). This means the FT4232H board alone could
        potentially replace the separate Adafruit FT232H for UART too,
        per §1's "optional simplification" note — worth knowing before
        deciding whether to bother wiring up the second board at all.
        (An FT232H specifically, being single-channel, cannot do both
        at once — irrelevant here since that's the board already
        assigned to UART only.)
- [ ] Wire the Adafruit FT232H board to the EBAZ4205's `J7` header
      (silkscreened `VCC RXD TXD GND`, confirmed from your board photo)
      using its labeled `D0`/`D1`/`Gnd` pins (bottom row) — FTDI's
      standard convention on this chip in UART/VCP mode is `D0`=TXD,
      `D1`=RXD: adapter `D0`→`J7 RXD`, adapter `D1`→`J7 TXD`, adapter
      `Gnd`→`J7 GND` (crossed, as usual). Leave the board's own `5V`/`3V`
      pins disconnected — it's USB-powered and, per its own silkscreen
      ("3V logic, 5V safe"), only needs the three data/ground lines to
      talk to the EBAZ4205's 3.3V UART.
- [ ] *(Optional simplification — now fully specified, not just
      theoretical)*: the same annotated photo confirms this FT4232H
      board's **channel C** (`CDBUS`) is wired for UART on this exact
      board layout: `CDBUS0`=`TXD`, `CDBUS1`=`RXD`, plus a nearby `GND`.
      That means this single board can provide **both** JTAG (channel
      A) and UART (channel C) at once via a second USB connection —
      genuinely replacing the separate Adafruit FT232H board, not just a
      hypothetical. Wire `CDBUS0`→`J7 RXD`, `CDBUS1`→`J7 TXD` (crossed,
      as usual), `GND`→`J7 GND`. Not required if the two-board plan
      below is already working or simpler to keep separate — but this is
      now a concrete option, not a maybe.
- [ ] Install a serial terminal (minicom, PuTTY, or `screen`) — don't
      need to connect yet, just confirm it opens a port at 115200 8N1.

**Report back**: what actually worked (or the exact error) for
programming-path A or B — this doc will get corrected once one is
confirmed against your actual hardware.

## 2. Phase 1 — heartbeat LED (no ADC needed)

Goal: prove the board boots a bitstream and the PS7→PL clock path works,
before wiring anything else up.

- [ ] `cd vivado && vivado -mode batch -source create_project.tcl`
      (or open Vivado, then run `source create_project.tcl` in the Tcl
      console) — creates the project and block design.
- [ ] Open the project in the Vivado GUI.
- [ ] Double-click the `system.bd` block design, open the
      `processing_system7_0` IP, and check the **Clock Configuration**
      page — confirm what FCLK0 actually comes out at given this
      board's real oscillator.
  - [ ] If it's not landing near 50 MHz, adjust
        `PCW_FCLK0_PERIPHERAL_DIVISOR0/1` (the script's values are a
        starting guess, not verified).
- [ ] Regenerate the block design output products if Vivado prompts for
      it.
- [ ] Run Synthesis (Flow Navigator).
- [ ] Run Implementation.
- [ ] Generate Bitstream.
- [ ] Connect the JTAG adapter (per §1) and open the Hardware Manager.
- [ ] Program the device.
- [ ] **Check: do both LEDs blink at roughly 1 Hz?**
  - [ ] Yes → Phase 1 done, go to §3.
  - [ ] No light at all → suspect JTAG connection, board power, or the
        board-prep mods (SD boot resistor, etc.) before suspecting the
        RTL. Re-check §1's JTAG wiring and programming path first.
  - [ ] Lights blink, but clearly not ~1 Hz → the real FCLK0/64 MHz
        clocking-wizard output isn't what was assumed. Go back to the
        Clock Configuration check above and re-derive the actual
        frequency, then rebuild.

## 3. Phase 2 — AD9226 #1 capture

Goal: get real ADC samples into the PL and visible somehow (an ILA/logic
analyzer probe is the simplest first check — no PS/host software needed
yet).

- [ ] Wire AD9226 #1 to the DATA3 header per `docs/WIRING.md` §2.
- [ ] Power the AD9226 module from its own external 5V supply (not the
      EBAZ4205 header — see `docs/WIRING.md` §4).
- [ ] (Recommended, not blocking) Apply the RF input-conditioning
      modification from `docs/WIRING.md` §4 before connecting an
      antenna.
- [ ] Confirm the AD9226 module's `OEB` pin is tied low (`docs/WIRING.md`
      §4) — required for the ADC to drive its outputs at all.
- [ ] Note which output format the module uses (two's complement vs.
      offset binary, `docs/WIRING.md` §4's R32–R35 strap) if you've been
      able to confirm it — `adc_sampler.v` passes the bus through as-is,
      with no format conversion to hide a mismatch.
- [ ] In Vivado, add an **Integrated Logic Analyzer (ILA)** debug core
      probing `adc1_data_sync`, `adc1_otr_sync`, and `adc1_valid_sync`
      from `top.v` (Flow Navigator → Set Up Debug, or a `mark_debug`
      attribute on those nets before synthesis).
- [ ] Rebuild (synthesis → implementation → bitstream) and program the
      device.
- [ ] Feed a known test tone (a few MHz, well under the 32 MHz Nyquist
      limit) into the AD9226's RF input.
- [ ] Open the ILA waveform in the Hardware Manager and trigger a
      capture.
- [ ] **Check: does `adc1_data_sync` show a moving 12-bit value tracking
      the input tone?**
  - [ ] Yes, and `sys_valid` pulses steadily, and `adc1_otr_sync` stays
        low → Phase 2 done.
  - [ ] `adc1_data_sync` is stuck (flat, all-0s, or all-1s) → check
        `OEB` is actually tied low before suspecting the FPGA/HDL side;
        a floating/high `OEB` tri-states the ADC's outputs, which looks
        identical to a wiring or clocking fault from the digital side.
  - [ ] Data moves but looks like noise / doesn't track the tone →
        re-check the DATA3 pin wiring against `docs/WIRING.md` §2
        (easy to swap two data-bit wires on a hand-wired ribbon) and the
        64 MHz sample clock is actually reaching the ADC.
  - [ ] `adc1_otr_sync` is stuck high → you're overdriving the ADC input;
        reduce the test tone level.

## What comes after this

Once Phase 2's ILA capture looks right, the next roadmap steps
(`docs/ARCHITECTURE.md` §8) are: stream those samples off to the PS
(replacing the ILA-only check with an actual AXI-Stream/BRAM capture
path or a simple AXI GPIO memory-mapped register, following
wallufo/guido57's TCP-streaming pattern), then bring up DAC902E #1 for
TX, then the second ADC/DAC pair.
