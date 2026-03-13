`timescale 1ns / 1ps

module genesis_block_tb_4lanes;

    localparam NUM_LANES    = 4;
    localparam CLKS_PER_BIT = 10;
    localparam CLK_PERIOD   = 10;       // 10 ns -> 100 MHz

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

    // Genesis header with nonce zeroed — miner substitutes its own counter.
    // Nonce field is at bits [31:0]; the rest is the real genesis block.
    localparam [639:0] GENESIS_HEADER =
        640'h01000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_3ba3edfd_7a7b12b2_7ac72c3e_67768f61_7fc81bc3_888a5132_3a9fb8aa_4b1e5e4a_29ab5f49_ffff001d_00000000;

    // Expected output: genesis header with winning nonce 0x1DAC2B7C (LE bytes)
    localparam [639:0] EXPECTED_GOLDEN =
        640'h01000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_3ba3edfd_7a7b12b2_7ac72c3e_67768f61_7fc81bc3_888a5132_3a9fb8aa_4b1e5e4a_29ab5f49_ffff001d_1dac2b7c;

    // Winning nonce_reg value (big-endian counter) = 0x7C2BAC1D = 2,083,236,893
    // Lane 1 (start=1, stride=4) reaches it after 520,809,223 increments
    // + 128-cycle pipeline latency => ~520,809,351 cycles in PIPELINED_STAGE
    // Total sim: ~521 M cycles (~5.21 s simulated @ 100 MHz)

    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- UART byte-level helpers ------------------------------------------

    task automatic send_uart_byte(input [7:0] data);
        uart_rx_pin = 1'b0;
        repeat (CLKS_PER_BIT) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            uart_rx_pin = data[i];
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
        uart_rx_pin = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
    endtask

    task automatic send_header_uart(input [639:0] header);
        send_uart_byte(8'hBB);
        for (int i = 79; i >= 0; i--)
            send_uart_byte(header[i*8 +: 8]);
    endtask

    task automatic recv_uart_byte(output [7:0] data);
        @(negedge uart_tx_pin);
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(posedge clk);
            data[i] = uart_tx_pin;
        end
        repeat (CLKS_PER_BIT) @(posedge clk);
    endtask

    // ---- Stimulus ---------------------------------------------------------

    initial begin
        clk         = 0;
        reset_n     = 0;
        uart_rx_pin = 1'b1;
        repeat (5) @(posedge clk);
        reset_n = 1;
        repeat (5) @(posedge clk);

        $display("[TB] Sending genesis header (nonce zeroed) over UART ...");
        send_header_uart(GENESIS_HEADER);
        $display("[TB] Header sent — mining from nonce 0");

        // Timeout: ~521M mining cycles * 10 ns + margin
        #6_000_000_000;
        $display("[TB] TIMEOUT — golden nonce not found");
        $finish;
    end

    // ---- FSM state monitor ------------------------------------------------

    initial begin
        wait (reset_n);
        @(posedge miner_inst.header_valid);
        $display("[TB] header_valid — header latched");
        $display("[TB]   target = %h", miner_inst.target_reg);
        wait (miner_inst.bitcoin_fsm_inst.ps == 4); // PIPELINED_STAGE
        $display("[TB] FSM -> PIPELINED_STAGE — all lanes mining");
    end

    // ---- Mining progress & golden-nonce detection -------------------------

    initial begin
        int mining_cycle;
        mining_cycle = 0;

        wait (miner_inst.bitcoin_fsm_inst.ps == 4);
        $display("[TB] Mining started at %0t", $time);

        forever begin
            @(posedge clk);
            mining_cycle++;

            if (mining_cycle % 50_000_000 == 0)
                $display("[TB] %0t | %0dM mining cycles | lane1 nonce_reg = 0x%08h",
                         $time, mining_cycle / 1_000_000,
                         miner_inst.LANE[1].nonce_cntr_inst.nonce_reg);

            if (miner_inst.golden_nonce_found) begin
                $display("[TB] *** GOLDEN NONCE FOUND at mining cycle %0d (%0t) ***",
                         mining_cycle, $time);
                $display("[TB]   winning_nonce (LE) = 0x%08h", miner_inst.winning_nonce);
                $display("[TB]   golden_header      = %h",     miner_inst.golden_header);
                break;
            end
        end
    end

    // ---- UART TX capture & verification -----------------------------------

    initial begin
        logic [7:0]   rx_bytes [0:79];
        logic [639:0] received;

        wait (reset_n);

        // Capture the 80-byte golden header transmitted by the miner
        for (int i = 0; i < 80; i++)
            recv_uart_byte(rx_bytes[i]);

        // Reconstruct 640-bit value (serializer sends MSB-first)
        received = '0;
        for (int i = 0; i < 80; i++)
            received = {received[631:0], rx_bytes[i]};

        $display("[TB] Received golden header over UART TX:");
        $display("[TB]   header = %h", received);
        $display("[TB]   nonce  = 0x%08h", received[31:0]);

        if (received === EXPECTED_GOLDEN)
            $display("[TB] *** PASS — received header matches expected genesis block ***");
        else begin
            $display("[TB] *** FAIL — header mismatch ***");
            $display("[TB]   expected: %h", EXPECTED_GOLDEN);
            $display("[TB]   got:      %h", received);
        end

        #1000;
        $finish;
    end

endmodule
