// this is just a state machine that controls the systolic array
// it loads in A and B and computes each MMM in the instruction sequence

module state_machine #(
    parameter N              = 4,
    parameter A_ADDR_WIDTH   = 12,
    parameter O_ADDR_WIDTH   = 12,
    parameter I_ADDR_WIDTH   = 8
) (
    input  wire clk,
    input  wire rst,
    input  wire ap_start,
    output reg  ap_done,

    // Instruction memory (read only)
    output reg  [I_ADDR_WIDTH-1:0] iaddr,
    input  wire [31:0]             idata,

    // A memory (read + write for copying output into A after each MMM)
    output reg  [A_ADDR_WIDTH-1:0]  a_raddr,
    input  wire signed [15:0]       a_rdata,
    output reg  [A_ADDR_WIDTH-1:0]  a_waddr,
    output reg  signed [15:0]       a_wdata,
    output reg                      a_we,

    // B memory (read only)
    output reg  [A_ADDR_WIDTH-1:0]  b_raddr,
    input  wire signed [15:0]       b_rdata,

    // Output memory (read for copying output into A after each MMM + write)
    output reg  [O_ADDR_WIDTH-1:0]  o_waddr,
    output reg  signed [31:0]       o_wdata,
    output reg                      o_we,
    output reg  [O_ADDR_WIDTH-1:0]  o_raddr,
    output reg                      o_re,
    input  wire signed [31:0]       o_rdata,

    // Systolic array control signals
    output reg                  sa_clear,       // clear the accumulator
    output reg                  sa_compute,     // compute mode enable
    output reg                  sa_drain,       // drain mode enable
    output reg  [N*16-1:0]      a_in_flat,      // A is packed as a flat vector instead of a 2D array
    output reg  [N*16-1:0]      b_in_flat,      // B is packed as a flat vector instead of a 2D array
    input  wire [N*N*32-1:0]    acc_flat,       // direct accumulator readout (debug only)
    input  wire [N*32-1:0]      drain_flat      // systolic drain
);

    // Dimensions for current MMM
    reg [15:0] dim_a;       // constant through MMM chain (rows of A)
    reg [15:0] dim_b;       // inner dimensions (cols of A / rows of B)
    reg [15:0] dim_c;       // output dimension (cols of B)
    reg [I_ADDR_WIDTH-1:0] ip;  // instruction pointer (which MMM in the sequence)

    // Tiling (we need to tile to process matrices larger than the NxN systolic array)
    reg [15:0] row_tile, col_tile;
    reg [15:0] num_row_tiles, num_col_tiles;
    reg [15:0] k;           // current k step (it takes dim_b steps to process a tile)
    reg [5:0]  sub_n;       // current n step (it takes N steps to fill the A and B buffers for the NxN systolic array)
    reg [5:0]  flush_cnt;   // flush counter (it takes 2 * N-1 steps to flush the array)

    // Buffers (filled for k step within a tile and then presented to the systolic array at once)
    reg signed [15:0] a_buf [0:N-1];
    reg signed [15:0] b_buf [0:N-1];

    // Drain counters
    reg [15:0] drain_row, drain_col;

    // Writeback counter (for copying the intermediate output to A during chaining)
    reg [A_ADDR_WIDTH-1:0] wb_idx;
    reg [A_ADDR_WIDTH-1:0] wb_total;

    // B memory offset (for the concatenated weight matrices in mem_b)
    reg [A_ADDR_WIDTH-1:0] b_base;

    // STATES
    localparam [4:0]
        IDLE          = 5'd0,
        FETCH_I       = 5'd1,
        FETCH_A       = 5'd2,
        FETCH_B       = 5'd3,
        SETUP         = 5'd4,
        SETUP_WAIT    = 5'd5,
        FEED_A1       = 5'd6,
        FEED_A2       = 5'd7,
        FEED_B1       = 5'd8,
        FEED_B2       = 5'd9,
        PUSH          = 5'd10,
        FLUSH         = 5'd11,
        FLUSH_WAIT    = 5'd12,
        DRAIN         = 5'd13,
        DRAIN_WAIT    = 5'd14,
        DRAIN_READ    = 5'd15,
        NEXT          = 5'd16,
        CHAIN_I       = 5'd17,
        CHAIN_D       = 5'd18,
        WB1           = 5'd19,
        WB2           = 5'd20,
        DONE          = 5'd21;
    reg [4:0] state;

    integer ii;  // for loop incrementer

    always @(posedge clk) begin
        if (rst) begin
            state          <= IDLE;
            ap_done        <= 1'b0;
            ip             <= 0;
            iaddr          <= 0;
            a_raddr        <= 0;
            a_waddr        <= 0;
            a_wdata        <= 16'sd0;
            a_we           <= 1'b0;
            b_raddr        <= 0;
            o_waddr        <= 0;
            o_wdata        <= 32'sd0;
            o_we           <= 1'b0;
            o_raddr        <= 0;
            o_re           <= 1'b0;
            sa_clear       <= 1'b0;
            sa_compute     <= 1'b0;
            sa_drain       <= 1'b0;
            a_in_flat      <= {N*16{1'b0}};
            b_in_flat      <= {N*16{1'b0}};
            dim_a          <= 16'd0;
            dim_b          <= 16'd0;
            dim_c          <= 16'd0;
            row_tile       <= 16'd0;
            col_tile       <= 16'd0;
            num_row_tiles  <= 16'd0;
            num_col_tiles  <= 16'd0;
            k              <= 16'd0;
            sub_n          <= 6'd0;
            flush_cnt      <= 6'd0;
            drain_row      <= 16'd0;
            drain_col      <= 16'd0;
            b_base         <= 0;
            wb_idx         <= 0;
            wb_total       <= 0;
            for (ii = 0; ii < N; ii = ii + 1) begin
                a_buf[ii] <= 16'sd0;
                b_buf[ii] <= 16'sd0;
            end
        end else begin
            // pulse signals to deassert systolic array controls and A/output enables each cycle
            sa_clear <= 1'b0;
            sa_compute <= 1'b0;
            sa_drain <= 1'b0;
            a_we     <= 1'b0;
            o_we     <= 1'b0;
            o_re     <= 1'b0;

            case (state)

                // =============================================================
                // IDLE
                // =============================================================
                IDLE: begin
                    ap_done <= 1'b0;
                    if (ap_start) begin
                        ip     <= 0;
                        b_base <= 0;
                        state  <= FETCH_I;
                    end
                end

                // =============================================================
                // FETCH
                // =============================================================
                // read dim_a/dim_b from the instruction sequence
                FETCH_I: begin  // fetch instruction pointer
                    iaddr <= ip;
                    state <= FETCH_A;
                end

                FETCH_A: begin
                    if (idata == 32'd0) begin
                        state <= DONE;
                    end else begin
                        dim_a <= idata[15:0];
                        iaddr <= ip + 1;
                        state <= FETCH_B;
                    end
                end

                FETCH_B: begin
                    dim_b <= idata[15:0];
                    iaddr <= ip + 2;
                    state <= SETUP;
                end

                // =============================================================
                // SETUP
                // =============================================================
                // capture dim_c, compute tile counts, and clear the systolic array
                SETUP: begin
                    dim_c         <= idata[15:0];
                    num_row_tiles <= (dim_a + N - 1) / N;
                    num_col_tiles <= (idata[15:0] + N - 1) / N;
                    row_tile      <= 0;
                    col_tile      <= 0;
                    k             <= 0;
                    sub_n         <= 0;
                    flush_cnt     <= 0;
                    drain_row     <= 0;
                    drain_col     <= 0;
                    sa_clear      <= 1'b1;
                    state         <= SETUP_WAIT;
                end

                // wait 1 cycle for the systolic array to be cleared (sa_clear needs time to take effect)
                SETUP_WAIT: begin
                    sub_n <= 0;
                    state <= FEED_A1;
                end

                // =============================================================
                // FEED
                // =============================================================
                // read N values for A and N values for B for the current k step and feed them to buffers
                FEED_A1: begin  // Issue A read
                    a_raddr <= (row_tile * N + sub_n) * dim_b + k;
                    state   <= FEED_A2;
                end

                FEED_A2: begin  // Capture A read
                    if (row_tile * N + sub_n < dim_a) begin
                        a_buf[sub_n] <= a_rdata;
                    end else begin
                        a_buf[sub_n] <= 16'sd0;
                    end

                    if (sub_n == N - 1) begin
                        sub_n   <= 0;
                        state   <= FEED_B1;
                    end else begin
                        sub_n   <= sub_n + 1;
                        state   <= FEED_A1;
                    end
                end

                FEED_B1: begin  // Issue B read
                    b_raddr <= b_base + k * dim_c + col_tile * N + sub_n;
                    state   <= FEED_B2;
                end

                FEED_B2: begin  // Capture B read
                    if (col_tile * N + sub_n < dim_c) begin
                        b_buf[sub_n] <= b_rdata;
                    end else begin
                        b_buf[sub_n] <= 16'sd0;
                    end

                    if (sub_n == N - 1) begin
                        sub_n   <= 0;
                        state   <= PUSH;
                    end else begin
                        sub_n   <= sub_n + 1;
                        state   <= FEED_B1;
                    end
                end

                // =============================================================
                // PUSH
                // =============================================================
                // push A and B from buffers to systolic array's edge inputs
                // each push of a value from A/B advances the skew registers by one step
                // this way all data arrives at the correct PE at the correct time
                PUSH: begin
                    for (ii = 0; ii < N; ii = ii + 1) begin
                        a_in_flat[ii*16 +: 16] <= a_buf[ii];
                        b_in_flat[ii*16 +: 16] <= b_buf[ii];
                    end
                    sa_compute <= 1'b1;

                    if (k == dim_b - 1) begin
                        k         <= 0;
                        flush_cnt <= 0;
                        if (N > 1) begin
                            state <= FLUSH;
                        end else begin
                            state <= FLUSH_WAIT;
                        end
                    end else begin
                        k       <= k + 1;
                        sub_n   <= 0;
                        state   <= FEED_A1;
                    end
                end

                // =============================================================
                // FLUSH
                // =============================================================
                // flush for 2*(N-1) cycles to clear the systolic array before reading the output (drain_flat)
                FLUSH: begin
                    a_in_flat <= {N*16{1'b0}};
                    b_in_flat <= {N*16{1'b0}};
                    sa_compute <= 1'b1;

                    if (flush_cnt == 2*(N-1) - 1) begin
                        state <= FLUSH_WAIT;
                    end else begin
                        flush_cnt <= flush_cnt + 1;
                    end
                end

                // wait 1 cycle for the accumulators to settle before reading the bottom row (drain_flat)
                FLUSH_WAIT: begin
                    drain_row <= 0;
                    drain_col <= 0;
                    state     <= DRAIN_READ;
                end

                // =============================================================
                // DRAIN
                // =============================================================
                // shift all accumulators down 1 row into the PE directly below them
                DRAIN: begin
                    sa_drain <= 1'b1;
                    state    <= DRAIN_WAIT;
                end

                // wait 1 cycle for the accumulators to settle before reading the bottom row (drain_flat)
                DRAIN_WAIT: begin
                    state <= DRAIN_READ;
                end

                DRAIN_READ: begin
                    begin : drain_write_block
                        integer actual_row;
                        actual_row = row_tile * N + (N - 1 - drain_row);

                        if (drain_col < N) begin
                            if (actual_row < dim_a &&
                                col_tile * N + drain_col < dim_c) begin
                                o_waddr <= actual_row * dim_c
                                           + col_tile * N + drain_col;
                                o_wdata <= $signed(drain_flat[drain_col*32 +: 32]);
                                o_we    <= 1'b1;
                            end

                            if (drain_col == N - 1) begin
                                drain_col <= 0;
                                if (drain_row == N - 1) begin
                                    // All N rows drained
                                    drain_row <= 0;
                                    state     <= NEXT;
                                end else begin
                                    // Need to shift accs down and read next row
                                    drain_row <= drain_row + 1;
                                    state     <= DRAIN;
                                end
                            end else begin
                                drain_col <= drain_col + 1;
                                // stay in DRAIN_READ to write next column
                            end
                        end
                    end
                end

                // =============================================================
                // NEXT
                // =============================================================
                // advance to next tile or finish this MMM
                NEXT: begin
                    if (col_tile + 1 < num_col_tiles) begin
                        col_tile  <= col_tile + 1;
                        k         <= 0;
                        sub_n     <= 0;
                        flush_cnt <= 0;
                        drain_row <= 0;
                        drain_col <= 0;
                        sa_clear  <= 1'b1;
                        state     <= SETUP_WAIT;
                    end else if (row_tile + 1 < num_row_tiles) begin
                        row_tile  <= row_tile + 1;
                        col_tile  <= 0;
                        k         <= 0;
                        sub_n     <= 0;
                        flush_cnt <= 0;
                        drain_row <= 0;
                        drain_col <= 0;
                        sa_clear  <= 1'b1;
                        state     <= SETUP_WAIT;
                    end else begin
                        state <= CHAIN_I;
                    end
                end

                // =============================================================
                // CHAIN
                // =============================================================
                // read the next dimension from the instruction sequence (if 0, we are done)
                CHAIN_I: begin  // fetch instruction pointer
                    iaddr <= ip + 3;
                    state <= CHAIN_D;
                end

                CHAIN_D: begin
                    if (idata == 32'd0) begin
                        state <= DONE;
                    end else begin
                        b_base   <= b_base + dim_b * dim_c;
                        wb_idx   <= 0;
                        wb_total <= dim_a * dim_c;
                        dim_b    <= dim_c;
                        dim_c    <= idata[15:0];
                        ip       <= ip + 1;
                        state    <= WB1;
                    end
                end

                // =============================================================
                // WRITEBACK
                // =============================================================
                // copy the output (Q16.6) into A (Q8.8)
                WB1: begin  // Issue output read
                    o_raddr <= wb_idx;
                    o_re    <= 1'b1;
                    state   <= WB2;
                end

                WB2: begin  // Capture output read and write to A
                    a_waddr <= wb_idx;
                    if ((o_rdata >>> 8) > 32'sd32767) begin
                        a_wdata <= 16'sd32767;
                    end else if ((o_rdata >>> 8) < -32'sd32768) begin
                        a_wdata <= -16'sd32768;
                    end else begin
                        a_wdata <= (o_rdata >>> 8);
                    end
                    a_we    <= 1'b1;

                    if (wb_idx + 1 >= wb_total) begin
                        num_row_tiles <= (dim_a + N - 1) / N;
                        num_col_tiles <= (dim_c + N - 1) / N;
                        row_tile      <= 0;
                        col_tile      <= 0;
                        k             <= 0;
                        sub_n         <= 0;
                        flush_cnt     <= 0;
                        drain_row <= 0;
                        drain_col <= 0;
                        sa_clear      <= 1'b1;
                        state         <= SETUP_WAIT;
                    end else begin
                        wb_idx <= wb_idx + 1;
                        state  <= WB1;
                    end
                end

                // =============================================================
                // DONE
                // =============================================================
                DONE: begin
                    ap_done <= 1'b1;
                    if (ap_start) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
