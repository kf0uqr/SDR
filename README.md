# SDR Transceiver Project

A wideband, all-mode software-defined radio transceiver built around a
Xilinx Zynq-7010 (EBAZ4205 board) and a set of commonly-available data
converter / synthesizer modules.

## Target hardware

| Qty | Part | Role |
|---|---|---|
| 1 | EBAZ4205 (Zynq-7010, XC7Z010) | Digital backend: DDC/DUC, control, PS/PL processing |
| 2 | AD9226 (12-bit, 65 MSPS ADC) | I/Q receive digitizer pair |
| 2 | DAC902E module (AD9762-class, 12-bit, 125 MSPS DAC) | I/Q transmit synthesizer pair |
| 1 | ADF4351/ADF435x wideband synthesizer (34.4 MHz – 4.4 GHz) | Main tunable LO (VHF/UHF/microwave path) |
| 1 | AD9850 DDS (0 – ~40 MHz) | HF-band LO / exciter, sample clock trim, calibration |
| 1+ | RF double-balanced mixer(s) | Up/down conversion for the ADF4351 signal path |
| — | Assorted amps, filters | Gain stages, anti-alias / image-reject / harmonic filtering |

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full system
design: frequency plan, signal chain, clocking, digital backend
partitioning, and the phased build/test roadmap.

## Status

Design phase. No gateware/firmware has been written yet — this repository
currently holds the architecture document that the HDL, drivers, and
host-side DSP will be built against.
