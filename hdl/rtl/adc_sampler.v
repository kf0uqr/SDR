// adc_sampler.v
//
// Captures a parallel-CMOS ADC bus (AD9226-class: N-bit data + OTR) on the
// ADC's own sample clock, then hands each sample to a second clock domain
// (e.g. the PS/AXI fabric clock) as a single-cycle valid pulse + data word.
//
// This is the "Sampler" block from the reference EBAZ4205 SDR projects
// (guido57/EBAZ4205_SDR_spectrum, wallufo/EBAZ4205_SDR), written from
// scratch here so it can be instantiated twice (one per AD9226) rather
// than being tied to a single fixed ADC instance.
//
// Clock-domain crossing note: this uses a 2-flop synchronizer on a toggle
// signal, which is safe for moving a "new sample is ready" pulse across
// domains but does NOT itself guarantee the data bus is glitch-free if
// sys_clk sampling happens to race a sample_clk edge on a single specific
// bit. For a first bring-up (visually checking captured values on a slow
// test tone) this is adequate; if bit-exact capture at full 64 MSPS rate
// matters later, replace the data path with a small dual-clock FIFO
// (e.g. Xilinx FIFO Generator in independent-clocks mode) instead of the
// bare synchronizer below.
module adc_sampler #(
    parameter DATA_WIDTH = 12
) (
    // ADC side
    input  wire                    sample_clk,     // driven TO the ADC by this design (e.g. 64 MHz)
    input  wire                    sample_rst_n,
    input  wire [DATA_WIDTH-1:0]   adc_data,       // AD9226 D0..D11 (or whichever width)
    input  wire                    adc_otr,        // AD9226 OTR (over-range) flag

    // System/AXI side
    input  wire                    sys_clk,
    input  wire                    sys_rst_n,
    output reg  [DATA_WIDTH-1:0]   sys_data,
    output reg                     sys_otr,
    output reg                     sys_valid       // one sys_clk-wide pulse per new sample
);

    // --- sample_clk domain: register the ADC bus, toggle a "new data" flag ---
    reg [DATA_WIDTH-1:0] captured_data;
    reg                  captured_otr;
    reg                  capture_toggle;

    always @(posedge sample_clk or negedge sample_rst_n) begin
        if (!sample_rst_n) begin
            captured_data  <= {DATA_WIDTH{1'b0}};
            captured_otr   <= 1'b0;
            capture_toggle <= 1'b0;
        end else begin
            captured_data  <= adc_data;
            captured_otr   <= adc_otr;
            capture_toggle <= ~capture_toggle;
        end
    end

    // --- sys_clk domain: synchronize the toggle, detect edges, latch data ---
    reg toggle_sync_0, toggle_sync_1, toggle_sync_2;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            toggle_sync_0 <= 1'b0;
            toggle_sync_1 <= 1'b0;
            toggle_sync_2 <= 1'b0;
            sys_data      <= {DATA_WIDTH{1'b0}};
            sys_otr       <= 1'b0;
            sys_valid     <= 1'b0;
        end else begin
            toggle_sync_0 <= capture_toggle;
            toggle_sync_1 <= toggle_sync_0;
            toggle_sync_2 <= toggle_sync_1;

            sys_valid <= (toggle_sync_1 != toggle_sync_2);
            if (toggle_sync_1 != toggle_sync_2) begin
                sys_data <= captured_data;
                sys_otr  <= captured_otr;
            end
        end
    end

endmodule
