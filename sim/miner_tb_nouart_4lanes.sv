`timescale 1ns / 1ps

module miner_tb_uart_4lanes;

    localparam NUM_LANES    = 4;
    localparam CLKS_PER_BIT = 10;       // fast baud for simulation
    localparam CLK_PERIOD   = 10;       // 10 ns → 100 MHz

    logic clk;
    logic reset_n;
    logic uart_rx_pin;
    logic uart_tx_pin;

    miner #(
        .NUM_LANES(NUM_LANES),
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) miner_inst (
        .clk(clk),
        .reset_n(reset_n),
        .uart_rx(uart_rx_pin),
        .uart_tx(uart_tx_pin)
    );

    // ----------------------------------------------------------------
    // Test vectors
    // ----------------------------------------------------------------
    localparam NUM_TESTS = 500;
    logic [639:0] bitcoin_header_test [0:NUM_TESTS-1];
    logic [255:0] final_hash_le_test  [0:NUM_TESTS-1];

    initial begin
        $readmemh("bitcoin_header.hex", bitcoin_header_test);
        $readmemh("bitcoin_hash.hex", final_hash_le_test);
    end

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    // ----------------------------------------------------------------
    // UART byte-level task (start + 8 data LSB-first + stop)
    // ----------------------------------------------------------------
    task automatic send_uart_byte(input [7:0] data);
        // Start bit
        uart_rx_pin = 1'b0;
        repeat (CLKS_PER_BIT) @(posedge clk);
        // 8 data bits, LSB first
        for (int i = 0; i < 8; i++) begin
            uart_rx_pin = data[i];
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
        // Stop bit
        uart_rx_pin = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
    endtask

    // ----------------------------------------------------------------
    // Send a 640-bit header: magic byte 0xBB then 80 bytes MSB-first
    // ----------------------------------------------------------------
    task automatic send_header_uart(input [639:0] header);
        send_uart_byte(8'hBB);
        for (int i = 79; i >= 0; i--)
            send_uart_byte(header[i*8 +: 8]);
    endtask

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        clk        = 0;
        reset_n    = 0;
        uart_rx_pin = 1'b1;            // UART idle high
        repeat (5) @(posedge clk);
        reset_n = 1;
        repeat (5) @(posedge clk);

        $display("[TB] Sending header over UART ...");
        send_header_uart(bitcoin_header_test[0]);
        $display("[TB] Header sent.  Waiting for pipeline results ...");

        // Safety timeout — let verification block call $finish
        #100_000_000;
        $display("[TB] TIMEOUT");
        $finish;
    end

    // ----------------------------------------------------------------
    // Verification — read internal signals via hierarchical references
    // ----------------------------------------------------------------
    initial begin
        int total_results;
        int fail_count;
        int lane_result_count [NUM_LANES];

        total_results = 0;
        fail_count    = 0;
        for (int i = 0; i < NUM_LANES; i++)
            lane_result_count[i] = 0;

        wait (reset_n);

        // Log when the miner latches the header
        @(posedge miner_inst.header_valid);
        $display("[TB] header_valid seen — miner latched header %h",
                 miner_inst.bitcoin_header);
        $display("[TB] FSM state = %0d", miner_inst.bitcoin_fsm_inst.ps);

        forever begin
            @(posedge clk);

            for (int i = 0; i < NUM_LANES; i++) begin
                if (miner_inst.valid_out[i]) begin
                    int test_idx;
                    test_idx = i + lane_result_count[i] * NUM_LANES;

                    if (test_idx < NUM_TESTS) begin
                        if (miner_inst.final_hash_le[i] !== final_hash_le_test[test_idx]) begin
                            fail_count++;
                            $display("FAIL [lane %0d, test %0d] got %h expected %h",
                                     i, test_idx,
                                     miner_inst.final_hash_le[i],
                                     final_hash_le_test[test_idx]);
                        end
                    end else begin
                        $display("WARNING: lane %0d exceeded test count", i);
                    end

                    lane_result_count[i]++;
                    total_results++;

                    if (total_results == NUM_TESTS) begin
                        $display("[TB] Done: %0d checked, %0d failed, %0d passed",
                                 total_results, fail_count, total_results - fail_count);
                        $finish;
                    end
                end
            end
        end
    end

endmodule
