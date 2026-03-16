// testbench performs two tests
// sanity check: NxN identity (checks MxI=M)
// this no longer happens under the new flow but I have kept it in just in case
// actual test: calculate MMMs with identity/random matrices based on the instruction sequence (checks sim_out against ref_out)
// gen_inputs.py takes care of parsing the arguments to make the MMM chain for testbench now (testbench just executes)

`timescale 1ns/1ps

`ifndef N
  `define N 4  // default N
`endif

module testbench;

    localparam NN            = `N;
    localparam A_ADDR_WIDTH  = 12;
    localparam O_ADDR_WIDTH  = 12;
    localparam I_ADDR_WIDTH  = 8;
    localparam CLK_HALF      = 5; // 10 ns = 100 MHz

    // signals for the systolic array device (IO signals are defined in top.v)
    reg  clk, rst, ap_start;
    reg  [A_ADDR_WIDTH-1:0]  addrA; reg enA; reg signed [15:0] dataA;
    reg  [A_ADDR_WIDTH-1:0]  addrB; reg enB; reg signed [15:0] dataB;
    reg  [I_ADDR_WIDTH-1:0]  addrI; reg enI; reg [31:0]        dataI;
    reg  [O_ADDR_WIDTH-1:0]  addrO;
    wire signed [31:0]       dataO;
    wire                     ap_done;

    // instantiate a top.v instance so we can control the device
    top #(
        .N              (NN),
        .A_ADDR_WIDTH   (A_ADDR_WIDTH),
        .O_ADDR_WIDTH   (O_ADDR_WIDTH),
        .I_ADDR_WIDTH   (I_ADDR_WIDTH)
    ) sys_arr_top (
        .clk      (clk),
        .rst      (rst),
        .addrA    (addrA), .enA (enA), .dataA (dataA),
        .addrB    (addrB), .enB (enB), .dataB (dataB),
        .addrI    (addrI), .enI (enI), .dataI (dataI),
        .addrO    (addrO), .dataO (dataO),
        .ap_start (ap_start),
        .ap_done  (ap_done)
    );

    // Clock
    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    // Helpers
    task do_reset;
        begin
            rst      = 1;
            ap_start = 0;
            enA = 0; enB = 0; enI = 0;
            @(posedge clk); @(posedge clk);
            rst = 0;
            @(posedge clk);
        end
    endtask

    task write_memA;
        input [A_ADDR_WIDTH-1:0] addr;
        input signed [15:0] data;
        begin
            @(negedge clk);
            addrA = addr; dataA = data; enA = 1;
            @(posedge clk); #1;
            enA = 0;
        end
    endtask

    task write_memB;
        input [A_ADDR_WIDTH-1:0] addr;
        input signed [15:0] data;
        begin
            @(negedge clk);
            addrB = addr; dataB = data; enB = 1;
            @(posedge clk); #1;
            enB = 0;
        end
    endtask

    task write_instr;
        input [I_ADDR_WIDTH-1:0] addr;
        input [31:0]             data;
        begin
            @(negedge clk);
            addrI = addr; dataI = data; enI = 1;
            @(posedge clk); #1;
            enI = 0;
        end
    endtask

    task pulse_start;
        begin
            @(negedge clk);
            ap_start = 1;
            @(posedge clk); #1;
            ap_start = 0;
        end
    endtask

    task wait_done;
        input integer timeout;
        integer t;
        begin
            t = 0;
            while (!ap_done && t < timeout) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t >= timeout) begin
                $display("ERROR: ap_done timeout after %0d cycles", timeout);
            end else begin
                $display("  %0d MMMs, %0d MACs", `TEST_MMM_TOTAL, `TEST_MAC_TOTAL);
                $display("  %0d cycles", t);
            end
        end
    endtask

    task read_output;
        input  [O_ADDR_WIDTH-1:0] addr;
        output signed [31:0]      val;
        begin
            addrO = addr;
            @(negedge clk);
            val = dataO;
        end
    endtask

    // FALLBACK TEST: NxN Identity Multiply (MxI=M)
    // it is identical to the case where you only call make sim N=?
    // this should not happen anymore since gen_inputs.py passes everything directly to run_test instead
    integer i, j;  // for loop incrementers
    reg signed [15:0] A_sanity [0:15][0:15]; // up to N=8
    reg signed [31:0] C_got;
    reg signed [31:0] C_exp;
    integer pass, fail;

    task fallback_test;
        integer a, b, c;
        begin
            $display("\nFallback: %0dx%0d Identity Multiply (MxI=M)", NN, NN);
            pass = 0; fail = 0;

            do_reset;

            // Fill A with arbitrary values (A[i][j] = i+j+1 in Q8.8)
            // Fill B with identity matrix (1.0 on diagonal = 256 in Q8.8)
            for (i = 0; i < NN; i = i + 1) begin
                for (j = 0; j < NN; j = j + 1) begin
                    A_sanity[i][j] = (i + j + 1) * 16;
                    write_memA(i * NN + j, A_sanity[i][j]); // arbitrary values
                    write_memB(i * NN + j, (i == j) ? 16'sd256 : 16'sd0); // identity matrix
                end
            end

            // Instruction sequence = [N, N, N, 0]
            write_instr(0, NN);
            write_instr(1, NN);
            write_instr(2, NN);
            write_instr(3, 0);

            pulse_start;
            wait_done(10000);

            // Check that C[i][j] equals A[i][j]
            for (i = 0; i < NN; i = i + 1) begin
                for (j = 0; j < NN; j = j + 1) begin
                    read_output(i * NN + j, C_got);
                    C_exp = A_sanity[i][j] * 32'sd256; // 1.0 in Q8.8 = 256
                    if (C_got === C_exp) begin
                        pass = pass + 1;
                    end else begin
                        $display("  FAIL C[%0d][%0d]: got %0d, exp %0d", i, j, $signed(C_got), $signed(C_exp));
                        fail = fail + 1;
                    end
                end
            end
            $display("  PASS: %0d / %0d", pass, pass+fail);
        end
    endtask

    // ACTUAL TEST: Calculate MMMs with identity/random matrices based on the given instruction sequence
    // this is the function that actually handles all basic identity multiplies and MMM chains
    reg signed [15:0] file_a   [0:`MEM_A_WORDS-1];
    reg signed [15:0] file_b   [0:`MEM_B_WORDS-1];
    reg        [31:0] file_i   [0:`MEM_I_WORDS-1];
    reg signed [31:0] file_ref [0:`MEM_REF_WORDS-1];
    integer n_a, n_b, n_i, n_ref;

    // exact word counts from gen_inputs.py passed in params.mk to avoid $readmemh "not enough words" warnings.
    `ifndef MEM_A_WORDS
      `define MEM_A_WORDS   4096
    `endif
    `ifndef MEM_B_WORDS
      `define MEM_B_WORDS   4096
    `endif
    `ifndef MEM_I_WORDS
      `define MEM_I_WORDS   256
    `endif
    `ifndef MEM_REF_WORDS
      `define MEM_REF_WORDS 4096
    `endif

    reg signed [31:0] sim_out [0:`MEM_REF_WORDS-1];

    task run_test;
        input [200*8-1:0] a_file, b_file, i_file, r_file;
        input integer      total_out;  // expected number of output words (if it is 0, we will detect from ref_out)
        integer idx;
        begin
            // print test string based on TEST_TYPE (0=identity, 1=chain)
            `ifdef TEST_TYPE
                if (`TEST_TYPE == 0) begin
                    // print the identity multiply string
                    `ifdef TEST_IDENTITY_M
                        `ifdef TEST_IDENTITY_I  // if both M and I are present
                            $display("\n%0dx%0d Identity Multiply: M(%0dx%0d) x I(%0dx%0d) = M(%0dx%0d)", `TEST_IDENTITY_M, `TEST_IDENTITY_I, `TEST_IDENTITY_M, `TEST_IDENTITY_I, `TEST_IDENTITY_I, `TEST_IDENTITY_I, `TEST_IDENTITY_M, `TEST_IDENTITY_I);
                        `else  // fallback to NxN Identity Multiply if one isn't present
                            $display("\n%0dx%0d Identity Multiply: M(%0dx%0d) x I(%0dx%0d) = M(%0dx%0d)", NN, NN, NN, NN, NN, NN, NN, NN);
                        `endif
                    `else  // fallback to NxN Identity Multiply if one isn't present
                        $display("\n%0dx%0d Identity Multiply: M(%0dx%0d) x I(%0dx%0d) = M(%0dx%0d)", NN, NN, NN, NN, NN, NN, NN, NN);
                    `endif
                end else begin
                    // print the MMM chain
                    `ifdef TEST_MMM_CHAIN
                        $display("\n%s", `TEST_MMM_CHAIN);
                    `else
                        $display("\nI=[%0s]", `WORKDIR_INSTR);  // fallback to just printing I array if something goes wrong (should never happen)
                    `endif
                end
            `else  // fallback to just printing I array if something goes wrong (should never happen)
                $display("\nI=[%0s]", `WORKDIR_INSTR);
            `endif
            pass = 0; fail = 0;

            $readmemh(a_file, file_a, 0, `MEM_A_WORDS   - 1);
            $readmemh(b_file, file_b, 0, `MEM_B_WORDS   - 1);
            $readmemh(i_file, file_i, 0, `MEM_I_WORDS   - 1);
            $readmemh(r_file, file_ref, 0, `MEM_REF_WORDS - 1);

            do_reset;

            // Load memory A
            idx = 0;
            while (idx < `MEM_A_WORDS && file_a[idx] !== 16'hxxxx) begin
                write_memA(idx, file_a[idx]);
                idx = idx + 1;
            end

            // Load memory B
            idx = 0;
            while (idx < `MEM_B_WORDS && file_b[idx] !== 16'hxxxx) begin
                write_memB(idx, file_b[idx]);
                idx = idx + 1;
            end

            // Load instruction memory
            idx = 0;
            while (idx < `MEM_I_WORDS && file_i[idx] !== 32'hxxxxxxxx) begin
                write_instr(idx, file_i[idx]);
                idx = idx + 1;
            end

            pulse_start;
            wait_done(200000);

            // detect output size from ref_out when not provided
            if (total_out == 0) begin
                total_out = 0;
                while (total_out < `MEM_REF_WORDS && file_ref[total_out] !== 32'hxxxxxxxx)
                    total_out = total_out + 1;
            end

            // compare outputs
            for (idx = 0; idx < total_out; idx = idx + 1) begin
                read_output(idx, C_got);
                sim_out[idx] = C_got;
                C_exp = file_ref[idx];
                if (C_got === C_exp) begin
                    pass = pass + 1;
                end else begin
                    $display("  FAIL out[%0d]: got %08x, exp %08x", idx, C_got, C_exp);
                    fail = fail + 1;
                end
            end

            // dump output in sim_out.hex
            $writememh(`WORKDIR_OUT, sim_out, 0, total_out - 1);

            $display("  PASS: %0d / %0d", pass, pass+fail);
        end
    endtask

    // STATE TRANSITION LOG
    integer log_file;
    integer log_started;
    integer cycle_count;
    reg [4:0] prev_state;
    reg ap_start_twin;

    initial begin
        log_file    = $fopen(`WORKDIR_LOG, "w");
        log_started = 0;
        cycle_count = 0;
        // use this to store the previous log state so we only log once per state (initialized to invalid state 31)
        prev_state  = 5'd31;
        // use this to make sure we don't repeatedly start logging (only triggers on rising edge)
        ap_start_twin = 0;
    end

    always @(posedge clk) begin
        // only start logging when ap_start pulses
        if (ap_start && !ap_start_twin) begin
            // ap_start is 1 but ap_start_twin is still 0
            log_started = 1;
            cycle_count = 0;
        end
        ap_start_twin = ap_start;

        if (log_started) begin
            if (sys_arr_top.sm.state !== prev_state) begin
                case (sys_arr_top.sm.state)
                    5'd0:  $fdisplay(log_file, "IDLE        %0d", cycle_count);
                    5'd1:  $fdisplay(log_file, "FETCH_I     %0d", cycle_count);
                    5'd2:  $fdisplay(log_file, "FETCH_A     %0d", cycle_count);
                    5'd3:  $fdisplay(log_file, "FETCH_B     %0d", cycle_count);
                    5'd4:  $fdisplay(log_file, "SETUP       %0d", cycle_count);
                    5'd5:  $fdisplay(log_file, "SETUP_WAIT  %0d", cycle_count);
                    5'd6:  $fdisplay(log_file, "FEED_A1     %0d", cycle_count);
                    5'd7:  $fdisplay(log_file, "FEED_A2     %0d", cycle_count);
                    5'd8:  $fdisplay(log_file, "FEED_B1     %0d", cycle_count);
                    5'd9:  $fdisplay(log_file, "FEED_B2     %0d", cycle_count);
                    5'd10: $fdisplay(log_file, "PUSH        %0d", cycle_count);
                    5'd11: $fdisplay(log_file, "FLUSH       %0d", cycle_count);
                    5'd12: $fdisplay(log_file, "FLUSH_WAIT  %0d", cycle_count);
                    5'd13: $fdisplay(log_file, "DRAIN       %0d", cycle_count);
                    5'd14: $fdisplay(log_file, "DRAIN_WAIT  %0d", cycle_count);
                    5'd15: $fdisplay(log_file, "DRAIN_READ  %0d", cycle_count);
                    5'd16: $fdisplay(log_file, "NEXT        %0d", cycle_count);
                    5'd17: $fdisplay(log_file, "CHAIN_I     %0d", cycle_count);
                    5'd18: $fdisplay(log_file, "CHAIN_D     %0d", cycle_count);
                    5'd19: $fdisplay(log_file, "WB1         %0d", cycle_count);
                    5'd20: $fdisplay(log_file, "WB2         %0d", cycle_count);
                    5'd21: $fdisplay(log_file, "DONE        %0d", cycle_count);
                    default: $fdisplay(log_file, "UNKNOWN     %0d", cycle_count);
                endcase
                prev_state = sys_arr_top.sm.state;
            end
            cycle_count = cycle_count + 1;
        end
    end

    // MAIN TEST SEQUENCE
    initial begin
        $dumpfile(`WORKDIR_VCD);
        $dumpvars(0, testbench);

        $display("");
        $display("=== %0dx%0d Systolic Array Testbench ===", `N, `N);

        `ifdef TEST_TYPE
            // if 1, run test
            run_test(`WORKDIR_A, `WORKDIR_B, `WORKDIR_I, `WORKDIR_REF, 0);
        `else
            // fallback to running the hardcoded sanity check (shouldn't happen with new flow)
            fallback_test;
        `endif

        $display("\n=== %0dx%0d Systolic Array Complete ===", `N, `N);
        $fclose(log_file);
        $finish(0);
    end

endmodule
