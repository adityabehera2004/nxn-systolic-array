// used to store the instruction sequence of MMMs as [rows, d1, d2, ... , 0] (mem_i)
// testbench writes to it once before ap_start and then the controller reads from it
// controller reads the next dimension in the sequence for each MMM

module instr_mem #(
    parameter DEPTH      = 256,  // default number of 32 bit words for the instruction sequence
    parameter ADDR_WIDTH = 8     // default address width = log_2(depth)
) (
    input  wire                clk,
    input  wire                we,  // write enable
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [31:0]         din,
    output wire [31:0]         dout
);
    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'd0;
    end

    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;
        end
    end

    assign dout = mem[addr];

endmodule
