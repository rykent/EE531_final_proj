module miner_tb_nouart_4lanes;

    logic clk;
    logic reset_n;

    localparam NUM_LANES = 4;

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
        int lane_result_count[NUM_LANES] = '{default:0};
        int total_results = 0;
        wait (reset_n); // Wait for reset to complete
        forever begin
            @(posedge clk);
            for (int i = 0; i < NUM_LANES; i++) begin
                if (valid_out[i]) begin
                    int test_idx = i + lane_result_count[i]*NUM_LANES;
                    if (test_idx < NUM_TESTS) begin
                        if (final_hash_le[i] != final_hash_le_test[test_idx]) begin
                            fail_count++;
                            $display("FAIL [lane %0d, test %0d] got %h expected %h", 
                                     i, test_idx, final_hash_le[i], final_hash_le_test[test_idx]);
                        end
                    end else begin
                        $display("WARNING: Lane %0d produced more results than available tests!", i);
                    end
                    lane_result_count[i]++;
                    total_results++;
                    if (total_results == NUM_TESTS) begin
                        $display("Done: %0d checked, %0d failed, %0d passed", total_results, fail_count, total_results - fail_count);
                        $finish;
                    end
                end
            end
        end
    end

    always #5 clk = ~clk;

endmodule