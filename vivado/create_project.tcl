#*****************************************************************************
# create_project.tcl
#
# Recreates the Vivado project for this repo's Chain A bring-up (heartbeat
# LED + AD9226 #1 capture). Source this from the Vivado Tcl console:
#
#   cd vivado
#   vivado -mode batch -source create_project.tcl
#   (or: launch Vivado GUI, then `source create_project.tcl` in the Tcl console)
#
# UNTESTED: written without access to Vivado in the environment that
# produced it. The project-creation, PS7 configuration, and RTL/XDC import
# steps follow the same proven pattern used by the reference EBAZ4205
# projects (see attribution below) and should be low-risk, but the
# clocking-wizard and AXI-GPIO wiring have not been run through Vivado
# here. Treat this as a strong starting point to open and iterate on in
# Vivado, not a guaranteed one-shot build.
#
# The processing_system7 configuration block below (DDR timing, MIO pin
# assignments, ENET0/UART1/SD0 setup for the cost-reduced EBAZ4205
# variant) is copied near-verbatim from KeitetsuWorks/EBAZ4205
# (https://github.com/KeitetsuWorks/EBAZ4205, MIT licensed) — those
# values are hard-won board-specific settings, not something to
# regenerate from a generic Zynq-7010 template.
#*****************************************************************************

set _xil_proj_name_ "sdr_transceiver"
set part "xc7z010clg400-1"

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/.."]

create_project ${_xil_proj_name_} "$script_dir/${_xil_proj_name_}" -part $part -force

set_property target_language Verilog [current_project]

# --- Add our plain RTL + constraints ---
add_files -norecurse [list \
  "$repo_root/hdl/rtl/top.v" \
  "$repo_root/hdl/rtl/heartbeat_led.v" \
  "$repo_root/hdl/rtl/adc_sampler.v" \
]
add_files -fileset constrs_1 -norecurse "$repo_root/hdl/constraints/ebaz4205.xdc"

set_property top top [current_fileset]

# --- Block design: PS7 + Clocking Wizard (64 MHz) + Processor System Reset ---
proc cr_bd_system {} {
  set design_name system
  create_bd_design $design_name

  # Processing System 7 — configuration copied from KeitetsuWorks/EBAZ4205
  # (base board bring-up), which is verified working on this exact
  # cost-reduced board (no 25 MHz crystal; Ethernet clock supplied by the
  # Zynq itself; SD0 boot; UART1 console). Only the FCLK0 frequency is
  # changed here (50 MHz, feeding our clocking wizard) — everything else
  # is left as that proven configuration.
  set ps7 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0 ]
  set_property -dict [ list \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} \
    CONFIG.PCW_UIPARAM_DDR_DEVICE_CAPACITY {2048 MBits} \
    CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO {EMIO} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {EMIO} \
    CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {External} \
    CONFIG.PCW_ENET_RESET_ENABLE {1} \
    CONFIG.PCW_ENET_RESET_SELECT {Share reset pin} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 24 .. 25} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
    CONFIG.PCW_SD0_GRP_CD_IO {MIO 34} \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR1 {1} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {50} \
  ] $ps7
  # NOTE: the exact FCLK0 divisors to land on a clean 50 MHz depend on the
  # IOPLL frequency Vivado's PS7 GUI computes for this board's input
  # oscillator — confirm/re-derive in the PS7 IP's "Clock Configuration"
  # GUI page rather than trusting the divisor values above blindly; they
  # are a starting point, not verified against real IOPLL math here.

  # Clocking Wizard: 50 MHz PS FCLK0 -> 64.000 MHz for the AD9226 pair.
  set clk_wiz [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0 ]
  set_property -dict [ list \
    CONFIG.PRIM_IN_FREQ {50.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {64.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
  ] $clk_wiz

  # Processor System Reset, synchronized to the 64 MHz domain.
  set rst_gen [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]

  connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0]   [get_bd_pins clk_wiz_0/clk_in1]
  connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins clk_wiz_0/reset]
  connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins proc_sys_reset_0/ext_reset_in]
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
  connect_bd_net [get_bd_pins clk_wiz_0/locked]   [get_bd_pins proc_sys_reset_0/dcm_locked]

  # External ports our plain-RTL top.v consumes.
  make_bd_intf_pins_external  [get_bd_intf_pins processing_system7_0/DDR]
  make_bd_intf_pins_external  [get_bd_intf_pins processing_system7_0/FIXED_IO]

  set clk_64m [create_bd_port -dir O clk_64m]
  connect_bd_net $clk_64m [get_bd_pins clk_wiz_0/clk_out1]

  set aresetn [create_bd_port -dir O peripheral_aresetn]
  connect_bd_net $aresetn [get_bd_pins proc_sys_reset_0/peripheral_aresetn]

  validate_bd_design
  save_bd_design
}

cr_bd_system

set wrapper_path [make_wrapper -fileset sources_1 -files [get_files system.bd] -top]
add_files -norecurse -fileset sources_1 $wrapper_path
set_property top top [current_fileset]
update_compile_order -fileset sources_1

puts "Project created. Next: open in Vivado, re-check the PS7 clock"
puts "configuration page, generate the block design output products,"
puts "then run synthesis/implementation from the GUI (see docs/BRINGUP.md)."
