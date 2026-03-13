`timescale 1ns / 1ps

module uart_tb;

    logic clk;
    logic reset;
    logic [639:0] hash;
    logic tx;
    logic rx;

    // Local signals to drive uart_top inputs
    logic miner_valid;

    parameter CLK_PERIOD = 10;
    always #(CLK_PERIOD/2) clk = ~clk;
    assign rx = tx;

    // Instantiate top module
    UART #(.CLKS_PER_BIT(10)) UART(
        .clk(clk),
        .reset(reset),
        .miner_hash(hash),
        .miner_valid(miner_valid),   // connect to local TB signal
        .rx(rx),
        .tx(tx)
    );

    initial begin
        clk = 0;
        reset = 1;
        miner_valid = 0;   // initialize

        #50
        reset = 0;

        #50
        hash = {
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF,
            64'h0123456789ABCDEF
        };
        
        // pulse miner_valid for 1 clock
        @(posedge clk) miner_valid = 1;
        @(posedge clk) miner_valid = 0;
        
        #90000
        hash = {
            64'hDEADBEEF01010101,
            64'hDEADBEEF02020202,
            64'hDEADBEEF03030303,
            64'hDEADBEEF04040404,
            64'hDEADBEEF05050505,
            64'hDEADBEEF06060606,
            64'hDEADBEEF07070707,
            64'hDEADBEEF08080808,
            64'hDEADBEEF09090909,
            64'h0123456789ABCDEF
        };
        @(posedge clk) miner_valid = 1;
        @(posedge clk) miner_valid = 0;
        #2000;
        $finish;
    end
endmodule