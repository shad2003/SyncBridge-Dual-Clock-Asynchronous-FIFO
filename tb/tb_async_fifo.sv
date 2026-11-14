//-----------------------------------------------------------------------------
// Module: tb_async_fifo
// Description: Comprehensive layered self-checking testbench for Parameterized
//              Dual-Clock Asynchronous FIFO.
// Features:
//   - True asynchronous clock generation:
//       * wclk: 100 MHz (Period = 10,000 ps)
//       * rclk: 73 MHz  (Period = 13,698 ps)
//   - Golden Reference Scoreboard with dynamic queue and instant mismatch reporting.
//   - Corner-case & protocol invariant checkers:
//       * Overflow prevention checker (no overwrite when wfull).
//       * Underflow prevention checker (no pointer movement when rempty).
//       * CDC Gray-code single-bit transition property checkers for wptr and rptr.
//   - Directed & randomized test scenarios:
//       * TEST_FULL_EMPTY
//       * TEST_FAST_WRITE
//       * TEST_FAST_READ
//       * TEST_RANDOM_RESET
//       * TEST_RANDOM (supports +SEED=<int>)
//   - Waveform dumping to sim/waves.vcd.
//-----------------------------------------------------------------------------
`timescale 1ps / 1ps

module tb_async_fifo;

    // Parameters
    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 4;
    localparam int DEPTH      = 1 << ADDR_WIDTH;

    // Clock Periods (timescale 1ps / 1ps):
    // wclk: 100 MHz -> Period = 10,000 ps (Half = 5,000 ps)
    // rclk: 73 MHz  -> Period = 13,698 ps (Half = 6,849 ps)
    localparam time WCLK_HALF_PERIOD = 5000ps;
    localparam time RCLK_HALF_PERIOD = 6849ps;

    // DUT Signals - Write Domain
    logic                  wclk;
    logic                  wrst_n;
    logic                  winc;
    logic [DATA_WIDTH-1:0] wdata;
    logic                  wfull;

    // DUT Signals - Read Domain
    logic                  rclk;
    logic                  rrst_n;
    logic                  rinc;
    logic [DATA_WIDTH-1:0] rdata;
    logic                  rempty;

    // Verification Statistics & Counters
    integer write_count      = 0;
    integer read_count       = 0;
    integer checks_count     = 0;
    integer assertions_count = 0;
    integer error_count      = 0;

    // Reference Model / Golden Scoreboard Queue
    logic [DATA_WIDTH-1:0] ref_queue [$];

    // Test Configuration Plusargs
    reg [8*32-1:0] test_name = "TEST_FULL_EMPTY";
    integer        random_seed = 1;
    integer        enable_dump = 1;

    // Monitor State Variables
    logic [ADDR_WIDTH:0] prev_wptr;
    logic                wptr_initialized = 1'b0;
    integer              dist_w;

    logic [ADDR_WIDTH:0] prev_rptr;
    logic                rptr_initialized = 1'b0;
    integer              dist_r;
    logic [DATA_WIDTH-1:0] exp_read_data;

    // DUT Instantiation
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wclk   (wclk),
        .wrst_n (wrst_n),
        .winc   (winc),
        .wdata  (wdata),
        .wfull  (wfull),
        .rclk   (rclk),
        .rrst_n (rrst_n),
        .rinc   (rinc),
        .rdata  (rdata),
        .rempty (rempty)
    );

    //-------------------------------------------------------------------------
    // Asynchronous Clock Generators
    //-------------------------------------------------------------------------
    initial begin
        wclk = 1'b0;
        forever #WCLK_HALF_PERIOD wclk = ~wclk;
    end

    initial begin
        rclk = 1'b0;
        forever #RCLK_HALF_PERIOD rclk = ~rclk;
    end

    //-------------------------------------------------------------------------
    // VCD Waveform Dump
    //-------------------------------------------------------------------------
    initial begin
        if ($value$plusargs("DUMP=%d", enable_dump)) begin
            // Plusarg override
        end
        if (enable_dump) begin
            $dumpfile("sim/waves.vcd");
            $dumpvars(0, tb_async_fifo);
        end
    end

    //-------------------------------------------------------------------------
    // Gray Code Distance Calculation Function
    // Computes Hamming distance between two vectors
    //-------------------------------------------------------------------------
    function [31:0] hamming_dist;
        input [ADDR_WIDTH:0] a;
        input [ADDR_WIDTH:0] b;
        integer k;
        logic [ADDR_WIDTH:0] diff;
        begin
            diff = a ^ b;
            hamming_dist = 0;
            for (k = 0; k <= ADDR_WIDTH; k = k + 1) begin
                if (diff[k]) hamming_dist = hamming_dist + 1;
            end
        end
    endfunction

    //-------------------------------------------------------------------------
    // Invariant Checkers & Monitors: Write Clock Domain
    //-------------------------------------------------------------------------
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            prev_wptr        <= '0;
            wptr_initialized <= 1'b0;
        end else begin
            if (wptr_initialized) begin
                dist_w = hamming_dist(dut.wptr, prev_wptr);
                // Invariant: Gray-code pointer can only transition by at most 1 bit
                if (dist_w > 1) begin
                    $display("[ASSERTION FAILED] wptr multi-bit Gray transition! Prev=0b%b, Curr=0b%b, Dist=%0d",
                             prev_wptr, dut.wptr, dist_w);
                    $fatal(1);
                end
                assertions_count = assertions_count + 1;
            end
            prev_wptr        <= dut.wptr;
            wptr_initialized <= 1'b1;

            // Invariant: Memory overwrite protection on full
            if (wfull && winc) begin
                #1; // Sample post-clock edge
                if (dut.u_wptr_full.wbinnext != dut.u_wptr_full.wbin) begin
                    $display("[ASSERTION FAILED] Memory overflow! wbin advanced while wfull was asserted!");
                    $fatal(1);
                end
                assertions_count = assertions_count + 1;
            end

            // Scoreboard push on valid write
            if (winc && !wfull) begin
                ref_queue.push_back(wdata);
                write_count  = write_count + 1;
                checks_count = checks_count + 1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Invariant Checkers & Monitors: Read Clock Domain
    //-------------------------------------------------------------------------
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            prev_rptr        <= '0;
            rptr_initialized <= 1'b0;
        end else begin
            if (rptr_initialized) begin
                dist_r = hamming_dist(dut.rptr, prev_rptr);
                // Invariant: Gray-code pointer can only transition by at most 1 bit
                if (dist_r > 1) begin
                    $display("[ASSERTION FAILED] rptr multi-bit Gray transition! Prev=0b%b, Curr=0b%b, Dist=%0d",
                             prev_rptr, dut.rptr, dist_r);
                    $fatal(1);
                end
                assertions_count = assertions_count + 1;
            end
            prev_rptr        <= dut.rptr;
            rptr_initialized <= 1'b1;

            // Invariant: Underflow protection on empty
            if (rempty && rinc) begin
                #1; // Sample post-clock edge
                if (dut.u_rptr_empty.rbinnext != dut.u_rptr_empty.rbin) begin
                    $display("[ASSERTION FAILED] Memory underflow! rbin advanced while rempty was asserted!");
                    $fatal(1);
                end
                assertions_count = assertions_count + 1;
            end

            // Scoreboard pop and data integrity check on valid read
            if (rinc && !rempty) begin
                if (ref_queue.size() == 0) begin
                    $display("[SCOREBOARD FATAL] Empty reference queue on valid read! Time=%0t", $time);
                    $fatal(1);
                end
                exp_read_data = ref_queue.pop_front();
                if (rdata !== exp_read_data) begin
                    $display("[SCOREBOARD ERROR] Data mismatch at time %0t!", $time);
                    $display("    Expected: 0x%08h", exp_read_data);
                    $display("    Actual:   0x%08h", rdata);
                    $display("    Read Index: %0d", read_count);
                    error_count = error_count + 1;
                    $fatal(1, "[SCOREBOARD FATAL] FIFO payload corrupted across CDC boundary!");
                end
                read_count   = read_count + 1;
                checks_count = checks_count + 1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Verification Driver Tasks
    //-------------------------------------------------------------------------

    // Apply asynchronous reset to both domains
    task reset_all;
        input integer hold_wclk_cycles;
        begin
            winc   = 1'b0;
            wdata  = '0;
            rinc   = 1'b0;
            wrst_n = 1'b0;
            rrst_n = 1'b0;
            ref_queue.delete();

            repeat (hold_wclk_cycles) @(posedge wclk);
            @(negedge wclk);
            wrst_n = 1'b1;
            @(negedge rclk);
            rrst_n = 1'b1;

            // Allow reset release to settle across 2-FF synchronizers
            repeat (3) @(posedge wclk);
            repeat (3) @(posedge rclk);
        end
    endtask

    // Single write attempt
    task try_write;
        input  [DATA_WIDTH-1:0] data;
        output                  success;
        reg                     success;
        reg                     was_full;
        begin
            @(negedge wclk);
            was_full = wfull;
            wdata = data;
            winc  = 1'b1;
            @(posedge wclk);
            #1;
            success = !was_full;
            @(negedge wclk);
            winc  = 1'b0;
        end
    endtask

    // Single read attempt
    task try_read;
        output [DATA_WIDTH-1:0] data;
        output                  success;
        reg    [DATA_WIDTH-1:0] data;
        reg                     success;
        reg                     was_empty;
        begin
            @(negedge rclk);
            was_empty = rempty;
            rinc = 1'b1;
            @(posedge rclk);
            #1;
            success = !was_empty;
            data    = rdata;
            @(negedge rclk);
            rinc = 1'b0;
        end
    endtask

    //-------------------------------------------------------------------------
    // Directed Test 1: TEST_FULL_EMPTY
    // Completely fills FIFO, tests overflow protection, drains, tests underflow.
    //-------------------------------------------------------------------------
    task run_test_full_empty;
        reg ok;
        logic [DATA_WIDTH-1:0] dummy_data;
        integer i;
        begin
            $display("[TEST] >>> Starting TEST_FULL_EMPTY <<<");

            reset_all(5);

            // 1. Initial status check
            if (!rempty) begin
                $display("[FAIL] rempty should be 1 after reset!");
                $fatal(1);
            end
            if (wfull) begin
                $display("[FAIL] wfull should be 0 after reset!");
                $fatal(1);
            end
            assertions_count = assertions_count + 2;

            // 2. Fill FIFO up to DEPTH (16 entries)
            $display("[TEST] Filling FIFO with %0d entries...", DEPTH);
            for (i = 0; i < DEPTH; i = i + 1) begin
                try_write(32'hA000_0000 + i, ok);
                if (!ok) begin
                    $display("[FAIL] Early wfull assertion on entry %0d!", i);
                    $fatal(1);
                end
            end

            // Wait 1 write clock for wfull registered output
            @(posedge wclk);
            #1;
            if (!wfull) begin
                $display("[FAIL] wfull not asserted after %0d writes!", DEPTH);
                $fatal(1);
            end
            $display("[TEST] wfull successfully asserted at capacity %0d.", DEPTH);
            assertions_count = assertions_count + 1;

            // 3. Overflow test: attempt 5 additional writes when full
            $display("[TEST] Attempting overflow writes (should be safely blocked)...");
            for (i = 0; i < 5; i = i + 1) begin
                try_write(32'hBAD0_0000 + i, ok);
                if (ok) begin
                    $display("[FAIL] Overflow write succeeded while wfull was asserted!");
                    $fatal(1);
                end
            end
            $display("[TEST] Overflow writes blocked successfully.");

            // 4. Drain FIFO completely (16 reads)
            $display("[TEST] Draining %0d entries...", DEPTH);
            for (i = 0; i < DEPTH; i = i + 1) begin
                try_read(dummy_data, ok);
                if (!ok) begin
                    $display("[FAIL] Early rempty assertion on read entry %0d!", i);
                    $fatal(1);
                end
            end

            // Wait 1 read clock for rempty registered output
            @(posedge rclk);
            #1;
            if (!rempty) begin
                $display("[FAIL] rempty not asserted after full drain!");
                $fatal(1);
            end
            $display("[TEST] rempty successfully asserted after draining.");
            assertions_count = assertions_count + 1;

            // 5. Underflow test: attempt 5 additional reads when empty
            $display("[TEST] Attempting underflow reads (should be safely blocked)...");
            for (i = 0; i < 5; i = i + 1) begin
                try_read(dummy_data, ok);
                if (ok) begin
                    $display("[FAIL] Underflow read succeeded while rempty was asserted!");
                    $fatal(1);
                end
            end
            $display("[TEST] Underflow reads blocked successfully.");
            $display("[TEST] >>> TEST_FULL_EMPTY PASSED <<<");
        end
    endtask

    //-------------------------------------------------------------------------
    // Directed Test 2: TEST_FAST_WRITE
    // Fast burst writes at 100 MHz with slow intermittent reads at 73 MHz.
    // Exercises sustained backpressure and safe wfull throttling.
    //-------------------------------------------------------------------------
    task run_test_fast_write;
        integer fw_total_tx;
        integer fw_writes_done;
        integer fw_reads_done;
        begin
            fw_total_tx     = 80;
            fw_writes_done  = 0;
            fw_reads_done   = 0;
            $display("[TEST] >>> Starting TEST_FAST_WRITE (Burst Writes with Slow Reads) <<<");

            reset_all(5);

            fork
                // Writer Process: Aggressive continuous writes
                begin : blk_fw_writer
                    while (fw_writes_done < fw_total_tx) begin
                        @(negedge wclk);
                        if (!wfull) begin
                            wdata = 32'hF000_0000 + fw_writes_done;
                            winc  = 1'b1;
                            fw_writes_done = fw_writes_done + 1;
                        end else begin
                            winc  = 1'b0; // Honor backpressure
                        end
                    end
                    @(negedge wclk);
                    winc = 1'b0;
                end

                // Reader Process: Throttled slow reads (read 1 out of every 3 cycles)
                begin : blk_fw_reader
                    integer cycle_cnt;
                    cycle_cnt = 0;
                    while (fw_reads_done < fw_total_tx) begin
                        @(negedge rclk);
                        cycle_cnt = cycle_cnt + 1;
                        if (!rempty && (cycle_cnt % 3 == 0)) begin
                            rinc = 1'b1;
                            fw_reads_done = fw_reads_done + 1;
                        end else begin
                            rinc = 1'b0;
                        end
                    end
                    @(negedge rclk);
                    rinc = 1'b0;
                end
            join

            // Drain any remaining entries
            repeat (10) @(posedge rclk);
            if (ref_queue.size() > 0) begin
                $display("[TEST] Draining leftover items in ref_queue...");
                while (!rempty) begin
                    @(negedge rclk);
                    rinc = 1'b1;
                    @(posedge rclk);
                end
                @(negedge rclk);
                rinc = 1'b0;
            end

            if (ref_queue.size() != 0) begin
                $display("[FAIL] Reference queue not empty at test conclusion!");
                $fatal(1);
            end
            $display("[TEST] >>> TEST_FAST_WRITE PASSED (%0d transactions verified) <<<", fw_total_tx);
        end
    endtask

    //-------------------------------------------------------------------------
    // Directed Test 3: TEST_FAST_READ
    // Slow burst writes with continuous reads.
    // Exercises rempty deassertion/assertion and underflow prevention.
    //-------------------------------------------------------------------------
    task run_test_fast_read;
        integer fr_total_tx;
        integer fr_writes_done;
        integer fr_reads_done;
        begin
            fr_total_tx     = 80;
            fr_writes_done  = 0;
            fr_reads_done   = 0;
            $display("[TEST] >>> Starting TEST_FAST_READ (Continuous Reads with Sporadic Writes) <<<");

            reset_all(5);

            fork
                // Writer Process: Writes 1 entry every 4 cycles
                begin : blk_fr_writer
                    integer cycle_cnt;
                    cycle_cnt = 0;
                    while (fr_writes_done < fr_total_tx) begin
                        @(negedge wclk);
                        cycle_cnt = cycle_cnt + 1;
                        if (!wfull && (cycle_cnt % 4 == 0)) begin
                            wdata = 32'hE000_0000 + fr_writes_done;
                            winc  = 1'b1;
                            fr_writes_done = fr_writes_done + 1;
                        end else begin
                            winc  = 1'b0;
                        end
                    end
                    @(negedge wclk);
                    winc = 1'b0;
                end

                // Reader Process: Reads aggressively whenever !rempty
                begin : blk_fr_reader
                    while (fr_reads_done < fr_total_tx) begin
                        @(negedge rclk);
                        if (!rempty) begin
                            rinc = 1'b1;
                            fr_reads_done = fr_reads_done + 1;
                        end else begin
                            rinc = 1'b0;
                        end
                    end
                    @(negedge rclk);
                    rinc = 1'b0;
                end
            join

            repeat (10) @(posedge rclk);
            if (ref_queue.size() != 0) begin
                $display("[FAIL] Reference queue not empty at test conclusion!");
                $fatal(1);
            end
            $display("[TEST] >>> TEST_FAST_READ PASSED (%0d transactions verified) <<<", fr_total_tx);
        end
    endtask

    //-------------------------------------------------------------------------
    // Directed Test 4: TEST_RANDOM_RESET
    // Injects mid-operation asynchronous reset during active traffic,
    // verifies clean pointer zeroing, rempty=1, wfull=0, and clean recovery.
    //-------------------------------------------------------------------------
    task run_test_random_reset;
        integer initial_writes;
        integer recovery_writes;
        reg ok;
        logic [DATA_WIDTH-1:0] dummy_data;
        integer k;
        begin
            initial_writes  = 10;
            recovery_writes = 30;
            $display("[TEST] >>> Starting TEST_RANDOM_RESET (Mid-Stream Asynchronous Reset) <<<");

            reset_all(5);

            // 1. Send initial traffic
            for (k = 0; k < initial_writes; k = k + 1) begin
                try_write(32'h1000_0000 + k, ok);
            end

            // 2. Mid-operation async reset assertion
            $display("[TEST] Triggering mid-stream asynchronous reset assertion...");
            #2500ps; // Asynchronous to both clock domains
            wrst_n = 1'b0;
            rrst_n = 1'b0;
            winc   = 1'b0;
            rinc   = 1'b0;

            // Flush scoreboard reference queue
            ref_queue.delete();

            #15000ps; // Hold reset active across multiple clock cycles

            // Verify asynchronous reset state immediately
            if (dut.wfull !== 1'b0) begin
                $display("[FAIL] wfull must be 0 under active reset!");
                $fatal(1);
            end
            if (dut.rempty !== 1'b1) begin
                $display("[FAIL] rempty must be 1 under active reset!");
                $fatal(1);
            end
            assertions_count = assertions_count + 2;
            $display("[TEST] Asynchronous reset state verified: wfull=0, rempty=1.");

            // 3. Deassert resets cleanly
            @(negedge wclk);
            wrst_n = 1'b1;
            @(negedge rclk);
            rrst_n = 1'b1;

            repeat (5) @(posedge wclk);
            repeat (5) @(posedge rclk);

            // 4. Recovery traffic
            $display("[TEST] Injecting post-reset recovery traffic (%0d entries)...", recovery_writes);
            for (k = 0; k < recovery_writes; k = k + 1) begin
                try_write(32'h2000_0000 + k, ok);
                if (k >= 2) begin
                    try_read(dummy_data, ok);
                end
            end

            // Drain remaining
            while (!rempty) begin
                try_read(dummy_data, ok);
            end

            repeat (5) @(posedge rclk);
            if (ref_queue.size() != 0) begin
                $display("[FAIL] Post-reset recovery queue mismatch!");
                $fatal(1);
            end
            $display("[TEST] >>> TEST_RANDOM_RESET PASSED <<<");
        end
    endtask

    //-------------------------------------------------------------------------
    // Randomized Test Scenario: TEST_RANDOM
    // Runs randomized concurrent read/write transactions with configurable seed.
    //-------------------------------------------------------------------------
    task run_test_random;
        input integer seed_val;
        integer init_seed;
        integer rnd_total_tx;
        integer rnd_writes_done;
        integer rnd_reads_done;
        integer dummy;
        begin
            init_seed       = seed_val;
            rnd_total_tx    = 150;
            rnd_writes_done = 0;
            rnd_reads_done  = 0;
            $display("[TEST] >>> Starting TEST_RANDOM with SEED=%0d (%0d transactions) <<<", init_seed, rnd_total_tx);

            dummy = $urandom(seed_val); // Seed PRNG
            reset_all(5);

            fork
                // Writer Process
                begin : blk_rnd_writer
                    while (rnd_writes_done < rnd_total_tx) begin
                        @(negedge wclk);
                        // 70% probability of trying to write
                        if (($urandom % 100 < 70) && !wfull) begin
                            wdata = $urandom();
                            winc  = 1'b1;
                            rnd_writes_done = rnd_writes_done + 1;
                        end else begin
                            winc  = 1'b0;
                        end
                    end
                    @(negedge wclk);
                    winc = 1'b0;
                end

                // Reader Process
                begin : blk_rnd_reader
                    while (rnd_reads_done < rnd_total_tx) begin
                        @(negedge rclk);
                        // 65% probability of trying to read
                        if (($urandom % 100 < 65) && !rempty) begin
                            rinc = 1'b1;
                            rnd_reads_done = rnd_reads_done + 1;
                        end else begin
                            rinc = 1'b0;
                        end
                    end
                    @(negedge rclk);
                    rinc = 1'b0;
                end
            join

            // Drain remaining
            repeat (10) @(posedge rclk);
            while (!rempty) begin
                @(negedge rclk);
                rinc = 1'b1;
                @(posedge rclk);
            end
            @(negedge rclk);
            rinc = 1'b0;

            repeat (5) @(posedge rclk);
            if (ref_queue.size() != 0) begin
                $display("[FAIL] Random test ended with pending unread items in queue!");
                $fatal(1);
            end
            $display("[TEST] >>> TEST_RANDOM SEED=%0d PASSED (%0d writes, %0d reads verified) <<<",
                     init_seed, rnd_writes_done, rnd_reads_done);
        end
    endtask

    //-------------------------------------------------------------------------
    // Main Test Execution Flow
    //-------------------------------------------------------------------------
    initial begin
        // Parse runtime plusargs
        if ($value$plusargs("TESTNAME=%s", test_name)) begin
            $display("[TB] Running test requested via plusarg: %0s", test_name);
        end else begin
            $display("[TB] No TESTNAME specified, defaulting to: %0s", test_name);
        end

        if ($value$plusargs("SEED=%d", random_seed)) begin
            $display("[TB] Random seed provided: %0d", random_seed);
        end

        // Execute scenario
        if (test_name == "TEST_FULL_EMPTY") begin
            run_test_full_empty();
        end else if (test_name == "TEST_FAST_WRITE") begin
            run_test_fast_write();
        end else if (test_name == "TEST_FAST_READ") begin
            run_test_fast_read();
        end else if (test_name == "TEST_RANDOM_RESET") begin
            run_test_random_reset();
        end else begin
            run_test_random(random_seed);
        end

        // Final verification summary banner
        #10000ps;
        $display("\n=======================================================");
        $display("   SIMULATION COMPLETED SUCCESSFULLY: %0s", test_name);
        $display("=======================================================");
        $display("   Total Successful Writes Verified : %0d", write_count);
        $display("   Total Successful Reads Verified  : %0d", read_count);
        $display("   Data Integrity Checks Passed     : %0d", checks_count);
        $display("   Safety Assertions Verified       : %0d", assertions_count);
        $display("   Total Scoreboard Errors          : %0d", error_count);
        $display("   Status                           : [PASS]");
        $display("=======================================================\n");

        $finish;
    end

endmodule
