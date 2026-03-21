// each Processing Element (PE) performs a signed 16 bit x 16 bit MAC (multiply and accumulate)
// 16 bit x 16 bit = 32 bit product (accumulator has to be 32 bit to store the result)
// Q8.8 x Q8.8 = Q16.16 product (accumulator has to be Q16.16 to store the result)
// data will propagate through each PE in the array systolically (A flows left to right, B flows top to bottom)
// each PE will multiply A and B before letting the result drain down
// the bottom PE's accumulator will add all the results in the column together

module systolic_pe (
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,      // clear the accumulator
    input  wire        compute,    // compute mode enable
    input  wire        drain,      // drain mode enable
    input  wire signed [15:0] in_a,   // data from left
    input  wire signed [15:0] in_b,   // data from above
    output reg  signed [15:0] out_a,  // pass through to right PE
    output reg  signed [15:0] out_b,  // pass through to below PE
    input  wire signed [31:0] drain_in,  // value from the above PE accumulator
    output wire signed [31:0] drain_out, // value this PE accumulator will send down
    output reg  signed [31:0] acc        // accumulator
);

    assign drain_out = acc;  // drain_out always has the same value as the accumulator

    always @(posedge clk) begin
        if (rst) begin
            out_a <= 16'sd0;
            out_b <= 16'sd0;
            acc   <= 32'sd0;
        end else if (clear) begin
            out_a <= 16'sd0;
            out_b <= 16'sd0;
            acc   <= 32'sd0;
        end else if (compute) begin
            // compute mode: multiply A and B and put it in the accumulator
            out_a <= in_a;
            out_b <= in_b;
            acc   <= acc + (in_a * in_b);
        end else if (drain) begin
            // drain mode: drain the accumulator and load from the PE above
            acc <= drain_in;
        end
    end

endmodule
