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
inside Vivado rather than have it work first try.

## Prerequisites

- Vivado 2021.2 (matching the reference projects; a newer version will
  likely work but may prompt IP upgrades)
- The EBAZ4205 board, USB-JTAG adapter, USB-UART adapter (see
  `guido57/EBAZ4205`'s Hackaday link for the board-prep hardware mods)
- For Phase 2: one AD9226 module wired per `docs/WIRING.md` §2, with its
  own external power supply

## Phase 1 — heartbeat LED (no ADC needed)

Goal: prove the board boots a bitstream and the PS7→PL clock path works,
before wiring anything else up.

1. `cd vivado && vivado -mode batch -source create_project.tcl`
   (or open Vivado and run `source create_project.tcl` in the Tcl
   console) — creates the project and block design.
2. Open the project in the Vivado GUI.
3. Double-click the `system.bd` block design, open the `processing_system7_0`
   IP, and check the **Clock Configuration** page — confirm what FCLK0
   actually comes out at given this board's real oscillator, and adjust
   `PCW_FCLK0_PERIPHERAL_DIVISOR0/1` if it's not landing near 50 MHz
   (the script's guessed divisors are a starting point, not verified).
4. Regenerate the block design output products if prompted.
5. Run Synthesis → Implementation → Generate Bitstream from the Flow
   Navigator.
6. Program the device (Hardware Manager, or export the bitstream for a
   PetaLinux boot flow later).
7. **Check**: both LEDs should blink at roughly 1 Hz. If they don't
   light at all, suspect JTAG/power/board-prep issues before suspecting
   the RTL. If they light but at the wrong rate, the actual FCLK0/64 MHz
   clocking-wizard output isn't what was assumed — go back to step 3.

## Phase 2 — AD9226 #1 capture

Goal: get real ADC samples into the PL and visible somehow (ILA/logic
analyzer probe is the simplest first check — no PS/host software needed
yet).

1. Wire AD9226 #1 to the DATA3 header per `docs/WIRING.md` §2, including
   its own external power supply and (recommended) the RF input-
   conditioning modification in §4.
2. Confirm the AD9226 module's output format strap (two's complement vs.
   offset binary, `docs/WIRING.md` §4) — `adc_sampler.v` just passes the
   bus through, so whatever format the ADC outputs is what you'll see;
   there's no format conversion to hide a mismatch.
3. In Vivado, add an **Integrated Logic Analyzer (ILA)** debug core
   probing `adc1_data_sync`, `adc1_otr_sync`, and `adc1_valid_sync` from
   `top.v` (Set Up Debug in the Flow Navigator, or a `mark_debug`
   attribute on those nets before synthesis).
4. Rebuild, program, and feed a known test tone (a few MHz, well under
   the 32 MHz Nyquist limit) into the AD9226's RF input.
5. **Check**: in the Hardware Manager's ILA waveform, `adc1_data_sync`
   should show a moving 12-bit value tracking the input tone, `sys_valid`
   should pulse steadily, and `adc1_otr_sync` should stay low unless
   you're intentionally overdriving the input.

**If `adc1_data_sync` is stuck (flat, all-0s, or all-1s) despite correct
wiring and a good input signal**: check the module's `OEB` pin is tied
low (`docs/WIRING.md` §4) before suspecting the FPGA/HDL side — AD9226
tri-states its outputs whenever `OEB` isn't held low, which looks
identical to a wiring or clocking fault from the digital side.

## What comes after this

Once Phase 2's ILA capture looks right, the next roadmap steps
(`docs/ARCHITECTURE.md` §8) are: stream those samples off to the PS
(replacing the ILA-only check with an actual AXI-Stream/BRAM capture
path or a simple AXI GPIO memory-mapped register, following
wallufo/guido57's TCP-streaming pattern), then bring up DAC902E #1 for
TX, then the second ADC/DAC pair.
