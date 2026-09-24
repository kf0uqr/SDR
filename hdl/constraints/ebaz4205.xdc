## ebaz4205.xdc
##
## Constraints for this project's Chain A bring-up (heartbeat LED +
## AD9226 #1 capture). Pin assignments for the LEDs and the DATA3/AD9226
## bus are copied verbatim from verified, working reference projects —
## see docs/WIRING.md for the full sourcing and caveats. Do not edit the
## AD9226 pin numbers without re-checking docs/WIRING.md; they must match
## the DATA3 header wiring on the physical board.
##
## Sources:
##   - LEDs:        KeitetsuWorks/EBAZ4205 (base board bring-up)
##   - AD9226/DATA3: wallufo/EBAZ4205_SDR (Zynq/capture-test project)

# Green LED
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]

# Red LED
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]

# --- AD9226 #1 (Chain A, RX) on the DATA3 header ---
# ADC_clk_64M is driven BY the FPGA to the ADC (not an input from it).
set_property -dict { PACKAGE_PIN N20 IOSTANDARD LVCMOS33 } [get_ports { adc1_sample_clk   }]; # DATA3_6
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[0]      }]; # DATA3_5
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[1]      }]; # DATA3_8
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[2]      }]; # DATA3_7
set_property -dict { PACKAGE_PIN P20 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[3]      }]; # DATA3_11
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[4]      }]; # DATA3_9
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[5]      }]; # DATA3_14
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[6]      }]; # DATA3_13
set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[7]      }]; # DATA3_16
set_property -dict { PACKAGE_PIN P19 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[8]      }]; # DATA3_15
set_property -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[9]      }]; # DATA3_18
set_property -dict { PACKAGE_PIN U20 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[10]     }]; # DATA3_17
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { adc1_data[11]     }]; # DATA3_20
set_property -dict { PACKAGE_PIN V20 IOSTANDARD LVCMOS33 } [get_ports { adc1_otr          }]; # DATA3_19

# --- AD9226 #2 (Chain B IF sampler) ---
# NOT YET WIRED. docs/WIRING.md flags DATA1's pin function as unverified
# (it's used for HDMI/audio/PS2 in the reference projects, not ADC data).
# Do not uncomment/build against this until the physical header is
# confirmed to be free, generic GPIO on your board.
#set_property -dict { PACKAGE_PIN ??  IOSTANDARD LVCMOS33 } [get_ports { adc2_sample_clk  }]; # DATA1_? (TBD)
#set_property -dict { PACKAGE_PIN ??  IOSTANDARD LVCMOS33 } [get_ports { adc2_data[0]     }]; # DATA1_? (TBD)
# ... (remaining adc2_data[1..11] and adc2_otr similarly TBD)
