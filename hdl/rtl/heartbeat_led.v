// heartbeat_led.v
//
// Blinks the two board LEDs at ~1 Hz from a free-running counter. This is
// the traditional "does the bitstream even load and run" bring-up test —
// no ADC, no PS, no clocking wizard dependency — so it's the very first
// thing to build and program before touching anything else in this repo.
//
// Adapted from counter26.v in wallufo/EBAZ4205_SDR (MIT licensed),
// simplified to a plain LED counter without the RST/count outputs that
// module exposed for its own project's use.
module heartbeat_led #(
    parameter CLK_HZ = 50_000_000
) (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [1:0] led
);

    localparam integer HALF_PERIOD = CLK_HZ / 2; // ~1 Hz full blink period on led[0]

    reg [31:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 32'd0;
            led     <= 2'b00;
        end else if (counter >= HALF_PERIOD - 1) begin
            counter <= 32'd0;
            led     <= led + 2'b01;
        end else begin
            counter <= counter + 32'd1;
        end
    end

endmodule
