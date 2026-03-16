// used to store mem_a (input matrix) and mem_b (weight/identity matrix) as Q8.8 matrices
// testbench writes to it once before ap_start and then the controller reads from it
// controller reads offsets of B for each MMM (it only reads A the first time)

module data_mem #(
    parameter DEPTH  = 4096,  // default number of 16 bit words (Q8.8) for this matrix
    parameter ADDR_WIDTH = 12  // default address width = log_2(depth)
) (
    input  wire               clk,
    input  wire               we,  // write enable
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire signed [15:0] din,
    output wire signed [15:0] dout
);
    reg signed [15:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;
        end
    end

    assign dout = mem[addr];

endmodule
