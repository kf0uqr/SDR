// top.v
//
// Top-level for Phase 1/2 bring-up (see docs/BRINGUP.md):
//   - Phase 1: heartbeat LED only, proves the bitstream loads and PS7
//     is supplying a PL clock. No ADC needed.
//   - Phase 2: adds AD9226 #1 capture (Chain A) via adc_sampler.
//
// This instantiates the Vivado block design (PS7 + clocking wizard +
// reset synchronizer, created by vivado/create_project.tcl) and wires
// it to the plain-RTL modules in this directory. The block design's
// generated wrapper name is fixed by that script as "system_wrapper".
module top (
    // Board LEDs
    output wire [1:0] led,

    // AD9226 #1 (Chain A RX) — DATA3 header, see hdl/constraints/ebaz4205.xdc
    output wire        adc1_sample_clk,
    input  wire [11:0] adc1_data,
    input  wire        adc1_otr,

    // Zynq PS-side fixed I/O and DDR — passed straight through to the
    // block design; Vivado's make_wrapper output normally generates
    // these automatically, they're listed here for clarity.
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);

    wire sys_clk_64m;
    wire sys_rst_n;
    wire [11:0] adc1_data_sync;
    wire        adc1_otr_sync;
    wire        adc1_valid_sync; // currently unused at top level; will feed
                                  // the AXI-Stream capture path in a later phase

    // --- Block design: PS7 + clk_wiz (64 MHz out) + proc_sys_reset ---
    system_wrapper system_i (
        .DDR_addr        (DDR_addr),
        .DDR_ba          (DDR_ba),
        .DDR_cas_n       (DDR_cas_n),
        .DDR_ck_n        (DDR_ck_n),
        .DDR_ck_p        (DDR_ck_p),
        .DDR_cke         (DDR_cke),
        .DDR_cs_n        (DDR_cs_n),
        .DDR_dm          (DDR_dm),
        .DDR_dq          (DDR_dq),
        .DDR_dqs_n       (DDR_dqs_n),
        .DDR_dqs_p       (DDR_dqs_p),
        .DDR_odt         (DDR_odt),
        .DDR_ras_n       (DDR_ras_n),
        .DDR_reset_n     (DDR_reset_n),
        .DDR_we_n        (DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio    (FIXED_IO_mio),
        .FIXED_IO_ps_clk (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .clk_64m         (sys_clk_64m),
        .peripheral_aresetn(sys_rst_n)
    );

    // --- Phase 1: heartbeat LED, clocked from the 64 MHz PL clock ---
    heartbeat_led #(
        .CLK_HZ(64_000_000)
    ) u_heartbeat (
        .clk   (sys_clk_64m),
        .rst_n (sys_rst_n),
        .led   (led)
    );

    // --- Phase 2: AD9226 #1 capture ---
    assign adc1_sample_clk = sys_clk_64m;

    adc_sampler #(
        .DATA_WIDTH(12)
    ) u_adc1_sampler (
        .sample_clk   (sys_clk_64m),
        .sample_rst_n (sys_rst_n),
        .adc_data     (adc1_data),
        .adc_otr      (adc1_otr),

        .sys_clk      (sys_clk_64m),
        .sys_rst_n    (sys_rst_n),
        .sys_data     (adc1_data_sync),
        .sys_otr      (adc1_otr_sync),
        .sys_valid    (adc1_valid_sync)
    );
    // NOTE: sample_clk and sys_clk are the same 64 MHz domain here, so
    // adc_sampler's synchronizer is a no-op in this phase (harmless).
    // It's already wired for a future phase where sys_clk becomes a
    // separate AXI fabric clock and the ADC keeps its own dedicated
    // sample clock.

endmodule
