module miner_tb_nouart;

    logic clk;
    logic reset_n;

    localparam NUM_LANES = 1;

    //Test using Genesis Block
    logic [639:0] bitcoin_header;
    logic header_ready;
    logic header_changed;
    logic [255:0] final_hash_le [NUM_LANES-1:0];
    logic [31:0] valid_out [NUM_LANES-1:0];

    miner #(.NUM_LANES(NUM_LANES)) miner_inst (
        .clk(clk),
        .reset_n(reset_n),
        .bitcoin_header(bitcoin_header),
        .header_ready(header_ready),
        .header_changed(header_changed),
        .final_hash_le(final_hash_le),
        .valid_out(valid_out)
    );


    localparam NUM_TESTS = 500;
    logic [639:0] bitcoin_header_test [0:NUM_TESTS-1];
    logic [255:0] final_hash_le_test [0:NUM_TESTS-1];

    initial begin
        $readmemh("bitcoin_header.hex", bitcoin_header_test);
        $readmemh("bitcoin_hash.hex", final_hash_le_test);
    end

    initial begin
        clk = 0;
        reset_n = 0;
        bitcoin_header = 0;
        header_ready = 0;
        header_changed = 0;
        #10 reset_n = 1;

        @(posedge clk);
        @(posedge clk);
        header_ready = 1;
        bitcoin_header = bitcoin_header_test[0];
        @(posedge clk);
        header_ready = 0;
     end

    // Parallel block: sample pipeline output and verify against expected hashes
    initial begin
        int result_count = 0;
        int fail_count = 0;
        wait (reset_n); // Wait for reset to complete
        forever begin
            @(posedge clk);
            if (valid_out[0]) begin
                if (final_hash_le[0] != final_hash_le_test[result_count]) begin
                    fail_count++;
                    $display("FAIL [%0d] got %h expected %h", result_count, final_hash_le[0], final_hash_le_test[result_count]);
                end
                result_count++;
                if (result_count == NUM_TESTS) begin
                    $display("Done: %0d checked, %0d failed, %0d passed", result_count, fail_count, result_count - fail_count);
                    $finish;
                end
            end
        end
    end

    always #5 clk = ~clk;

endmodule