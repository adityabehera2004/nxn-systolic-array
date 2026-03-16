// used to store the final result as a Q16.16 matrix (mem_o isn't saved as a file)
// controller writes to this after each MMM computation (only last MMM is final, all others feed back into A)
// testbench reads after ap_done to compare with ref_out (testbench dumps to sim_out even tho mem_o isn't saved)

module output_mem #(
    parameter DEPTH      = 4096,  // default number of 32 bit words (Q16.6) for the final output matrix
    parameter ADDR_WIDTH = 12     // default address width = log_2(depth)
) (
    input  wire                clk,
    // write port
    input  wire                we,  // write enable
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire signed [31:0] wdata,
    // read port
    input  wire [ADDR_WIDTH-1:0] raddr,
    output wire signed [31:0] rdata
);
    reg signed [31:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
    end

    assign rdata = mem[raddr];

endmodule
