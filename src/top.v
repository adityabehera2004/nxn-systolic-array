// all this does is instantiate and wire together the:
// - 4 memories
//      - mem_a and mem_b using data_mem.v
//      - mem_i using instr_mem.v
//      - mem_o using output_mem.v
// - the systolic array (we don't directly create any PEs)
// - the controller

module top #(
    parameter N              = 4,
    parameter A_ADDR_WIDTH   = 12,
    parameter O_ADDR_WIDTH   = 12,
    parameter I_ADDR_WIDTH   = 8,
    parameter AMEM_DEP       = 4096,
    parameter OMEM_DEP       = 4096,
    parameter IMEM_DEP       = 256
) (
    // Top IO signals as specified in the pdf
    input  wire clk,
    input  wire rst,

    input  wire [A_ADDR_WIDTH-1:0]  addrA,
    input  wire                     enA,
    input  wire signed [15:0]       dataA,

    input  wire [A_ADDR_WIDTH-1:0]  addrB,
    input  wire                     enB,
    input  wire signed [15:0]       dataB,

    input  wire [I_ADDR_WIDTH-1:0]  addrI,
    input  wire                     enI,
    input  wire [31:0]              dataI,

    input  wire [O_ADDR_WIDTH-1:0]  addrO,
    output wire signed [31:0]       dataO,

    input  wire                     ap_start,
    output wire                     ap_done
);

    // State machine signals
    wire [I_ADDR_WIDTH-1:0] sm_iaddr;
    wire [31:0]             sm_idata;

    wire [A_ADDR_WIDTH-1:0] sm_a_raddr;
    wire signed [15:0]      sm_a_rdata;
    wire [A_ADDR_WIDTH-1:0] sm_a_waddr;
    wire signed [15:0]      sm_a_wdata;
    wire                    sm_a_we;

    wire [A_ADDR_WIDTH-1:0] sm_b_raddr;
    wire signed [15:0]      sm_b_rdata;

    wire [O_ADDR_WIDTH-1:0] sm_o_waddr;
    wire signed [31:0]      sm_o_wdata;
    wire                    sm_o_we;
    wire [O_ADDR_WIDTH-1:0] sm_o_raddr;
    wire                    sm_o_re;
    wire signed [31:0]      sm_o_rdata;

    // Systolic array signals
    wire                sa_clear, sa_compute, sa_drain;
    wire [N*16-1:0]     sa_a_in_flat;
    wire [N*16-1:0]     sa_b_in_flat;
    wire [N*N*32-1:0]   sa_acc_flat;
    wire [N*32-1:0]     sa_drain_flat;

    // Instruction memory
    instr_mem #(.DEPTH(IMEM_DEP), .ADDR_WIDTH(I_ADDR_WIDTH)) mem_i (
        .clk  (clk),
        .we   (enI),
        .addr (enI ? addrI : sm_iaddr),
        .din  (dataI),
        .dout (sm_idata)
    );

    // A memory signals
    // B doesn't need signals because we just keep reading the next matrix from memory and feeding it into the top of the array
    // A does need signals though because mem_a will be written with the most recent MMM output from mem_o so that computation can continue
    wire                 a_mem_we   = enA | sm_a_we;
    wire [A_ADDR_WIDTH-1:0] a_mem_addr = enA ? addrA : sm_a_we ? sm_a_waddr : sm_a_raddr;
    wire signed [15:0]   a_mem_din  = enA ? dataA : sm_a_wdata;

    // A memory
    data_mem #(.DEPTH(AMEM_DEP), .ADDR_WIDTH(A_ADDR_WIDTH)) mem_a (
        .clk  (clk),
        .we   (a_mem_we),
        .addr (a_mem_addr),
        .din  (a_mem_din),
        .dout (sm_a_rdata)
    );

    // B memory
    data_mem #(.DEPTH(AMEM_DEP), .ADDR_WIDTH(A_ADDR_WIDTH)) mem_b (
        .clk  (clk),
        .we   (enB),
        .addr (enB ? addrB : sm_b_raddr),
        .din  (dataB),
        .dout (sm_b_rdata)
    );

    // Output memory signal
    // during computation, the controller needs to read its own output to feed back as input into A
    // this is related to the A memory signals since mem_o is read and writted to mem_a
    // after computation, we want the testbench to read the output so that we can check if against ref_out
    wire [O_ADDR_WIDTH-1:0] o_rd_addr = sm_o_re ? sm_o_raddr : addrO;

    // Output memory
    output_mem #(.DEPTH(OMEM_DEP), .ADDR_WIDTH(O_ADDR_WIDTH)) mem_o (
        .clk   (clk),
        .we    (sm_o_we),
        .waddr (sm_o_waddr),
        .wdata (sm_o_wdata),
        .raddr (o_rd_addr),
        .rdata (sm_o_rdata)
    );

    assign dataO = sm_o_rdata;

    // Systolic Array
    systolic_array #(.N(N)) sys_arr (
        .clk        (clk),
        .rst        (rst),
        .clear      (sa_clear),
        .compute    (sa_compute),
        .drain      (sa_drain),
        .a_in_flat  (sa_a_in_flat),
        .b_in_flat  (sa_b_in_flat),
        .acc_flat   (sa_acc_flat),
        .drain_flat (sa_drain_flat)
    );

    // State Machine
    state_machine #(
        .N       (N),
        .A_ADDR_WIDTH (A_ADDR_WIDTH),
        .O_ADDR_WIDTH (O_ADDR_WIDTH),
        .I_ADDR_WIDTH (I_ADDR_WIDTH)
    ) sm (
        .clk       (clk),
        .rst       (rst),
        .ap_start  (ap_start),
        .ap_done   (ap_done),
        .iaddr     (sm_iaddr),
        .idata     (sm_idata),
        .a_raddr   (sm_a_raddr),
        .a_rdata   (sm_a_rdata),
        .a_waddr   (sm_a_waddr),
        .a_wdata   (sm_a_wdata),
        .a_we      (sm_a_we),
        .b_raddr   (sm_b_raddr),
        .b_rdata   (sm_b_rdata),
        .o_waddr   (sm_o_waddr),
        .o_wdata   (sm_o_wdata),
        .o_we      (sm_o_we),
        .o_raddr   (sm_o_raddr),
        .o_re      (sm_o_re),
        .o_rdata   (sm_o_rdata),
        .sa_clear   (sa_clear),
        .sa_compute (sa_compute),
        .sa_drain   (sa_drain),
        .a_in_flat  (sa_a_in_flat),
        .b_in_flat  (sa_b_in_flat),
        .acc_flat   (sa_acc_flat),
        .drain_flat (sa_drain_flat)
    );

endmodule
