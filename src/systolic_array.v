// instatiates N^2 PEs and wires them together for the systolic array
// the input skew of A is delayed by i cycles for row i
// the input skew of B is delayed by j cycles for col j
// this ensures that A[i][k] and B[k][j] both meet at the same time at PE[i][j]
// PE accumulators are also wired up vertically so they all drain down (drain_in connects to drain_out of next row)
// after N drains, N rows have shifted out of the bottom and into drain_flat

module systolic_array #(
    parameter N = 4
) (
    input  wire clk,
    input  wire rst,
    input  wire clear,                         // clear the accumulator
    input  wire compute,                       // compute mode enable
    input  wire drain,                         // drain mode enable
    input  wire [N*16-1:0]    a_in_flat,       // A is packed as a flat vector instead of a 2D array
    input  wire [N*16-1:0]    b_in_flat,       // B is packed as a flat vector instead of a 2D array
    output wire [N*N*32-1:0]  acc_flat,        // direct accumulator readout (debug only)
    output wire [N*32-1:0]    drain_flat       // systolic drain
);

    // WIRES BETWEEN PEs
    // Horizontal wires (A moves left to right): h_wire[i][j] is in_a of PE[i][j]
    wire signed [15:0] h_wire [0:N-1][0:N];

    // Vertical wires (B moves top to bottom): v_wire[i][j] is in_b of PE[i][j]
    wire signed [15:0] v_wire [0:N][0:N-1];

    // Drain wires (accumulator flows down): d_wire[i][j] is drain_in of PE[i][j]
    wire signed [31:0] d_wire [0:N][0:N-1];
    // d_wire[0][j] = 0 (top row has nothing above it)
    // d_wire[N][j] = drain_out of PE[N-1][j] (bottom row will eventually go to drain_flat)

    // PE accumulators
    wire signed [31:0] pe_acc [0:N-1][0:N-1];

    // set all top row drain inputs to 0
    genvar t;
    generate
        for (t = 0; t < N; t = t + 1) begin : drain_top
            assign d_wire[0][t] = 32'sd0;
        end
    endgenerate

    // A input skew: row i is delayed by i cycles
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : a_skew_row
            if (i == 0) begin : no_skew
                assign h_wire[0][0] = $signed(a_in_flat[0*16 +: 16]);
            end else begin : has_skew
                reg signed [15:0] a_pipe [0:i-1];
                integer k;
                always @(posedge clk) begin
                    if (rst) begin
                        for (k = 0; k < i; k = k + 1)
                            a_pipe[k] <= 16'sd0;
                    end else if (clear) begin
                        for (k = 0; k < i; k = k + 1)
                            a_pipe[k] <= 16'sd0;
                    end else if (compute) begin
                        a_pipe[0] <= $signed(a_in_flat[i*16 +: 16]);
                        for (k = 1; k < i; k = k + 1)
                            a_pipe[k] <= a_pipe[k-1];
                    end
                end
                assign h_wire[i][0] = a_pipe[i-1];
            end
        end
    endgenerate

    // B input skew: col j is delayed by j cycles
    genvar j;
    generate
        for (j = 0; j < N; j = j + 1) begin : b_skew_col
            if (j == 0) begin : no_skew
                assign v_wire[0][0] = $signed(b_in_flat[0*16 +: 16]);
            end else begin : has_skew
                reg signed [15:0] b_pipe [0:j-1];
                integer k;
                always @(posedge clk) begin
                    if (rst) begin
                        for (k = 0; k < j; k = k + 1)
                            b_pipe[k] <= 16'sd0;
                    end else if (clear) begin
                        for (k = 0; k < j; k = k + 1)
                            b_pipe[k] <= 16'sd0;
                    end else if (compute) begin
                        b_pipe[0] <= $signed(b_in_flat[j*16 +: 16]);
                        for (k = 1; k < j; k = k + 1)
                            b_pipe[k] <= b_pipe[k-1];
                    end
                end
                assign v_wire[0][j] = b_pipe[j-1];
            end
        end
    endgenerate
    
    // PE grid with interconnects between each other and accumulators draining down
    generate
        for (i = 0; i < N; i = i + 1) begin : row
            for (j = 0; j < N; j = j + 1) begin : col
                wire signed [31:0] pe_drain_out;

                systolic_pe pe (
                    .clk       (clk),
                    .rst       (rst),
                    .clear     (clear),
                    .compute   (compute),
                    .drain     (drain),
                    .in_a      (h_wire[i][j]),
                    .in_b      (v_wire[i][j]),
                    .out_a     (h_wire[i][j+1]),
                    .out_b     (v_wire[i+1][j]),
                    .drain_in  (d_wire[i][j]),  // from PE above
                    .drain_out (pe_drain_out),  // to PE below
                    .acc       (pe_acc[i][j])
                );

                assign d_wire[i+1][j] = pe_drain_out;
                assign acc_flat[(i*N+j)*32 +: 32] = pe_acc[i][j];
            end
        end
    endgenerate

    // set all bottom row drain outputs to drain_flat
    generate
        for (j = 0; j < N; j = j + 1) begin : drain_out_col
            assign drain_flat[j*32 +: 32] = d_wire[N][j];
        end
    endgenerate

endmodule
