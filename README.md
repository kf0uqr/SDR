# SDR Transceiver Project

A wideband, all-mode software-defined radio transceiver built around a
Xilinx Zynq-7010 (EBAZ4205 board) and a set of commonly-available data
converter / synthesizer modules.

## Target hardware

| Qty | Part | Role |
|---|---|---|
| 1 | EBAZ4205 (Zynq-7010, XC7Z010) | Digital backend: DDC/DUC, control, PS/PL processing |
| 2 | AD9226 (12-bit, 65 MSPS ADC) | I/Q receive digitizer pair |
| 2 | DAC902E module (chip marked "DAC902E", 12-bit, board silkscreened "DAC 165MHz" — see `docs/WIRING.md` §6) | I/Q transmit synthesizer pair |
| 1 | ADF4351/ADF435x wideband synthesizer (34.4 MHz – 4.4 GHz) | Main tunable LO (VHF/UHF/microwave path) |
| 1 | AD9850 DDS (0 – ~40 MHz) | HF-band LO / exciter, sample clock trim, calibration |
| 1+ | RF double-balanced mixer(s) | Up/down conversion for the ADF4351 signal path |
| — | Assorted amps, filters | Gain stages, anti-alias / image-reject / harmonic filtering |

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full system
design: frequency plan, signal chain, clocking, digital backend
partitioning, and the phased build/test roadmap.

See [`docs/WIRING.md`](docs/WIRING.md) for verified pin-level wiring
between the EBAZ4205 and the AD9226/AD9850-class DDS modules, sourced
from the reference projects' actual constraint files and hardware
photos.

See [`docs/BRINGUP.md`](docs/BRINGUP.md) for how to build and test the
current HDL scaffold, phase by phase.

## Repository layout

- `hdl/rtl/` — plain Verilog sources (heartbeat LED bring-up test, the
  AD9226 sample-capture module, the top-level tying them to the PS7
  block design).
- `hdl/constraints/` — Vivado XDC pin constraints (see `docs/WIRING.md`
  for sourcing).
- `vivado/create_project.tcl` — recreates the Vivado project and its PS7
  + clocking-wizard block design from scratch; no binary project files
  are committed.
- `docs/` — architecture, wiring, and bring-up documentation.

## Prior art

This design builds directly on two existing EBAZ4205 receiver projects,
which prove out the core direct-sampling RX chain (single AD9226 at
64 MSPS, 0–32 MHz, no LO/mixer needed) that this project extends with a
second RX/TX chain, TX capability, and a superheterodyne path for
VHF/UHF/microwave:

- https://github.com/guido57/EBAZ4205_SDR_spectrum
- https://github.com/wallufo/EBAZ4205_SDR

## Status

Phase 1/2 HDL scaffold written (heartbeat LED bring-up + AD9226 #1
capture, see `docs/BRINGUP.md`) but **not yet built or tested** — no
Vivado toolchain was available in the environment that wrote it. Next
step is opening `vivado/create_project.tcl` in real Vivado and iterating
from there.
