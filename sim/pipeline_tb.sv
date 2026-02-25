module pipeline_tb;

    logic clk;
    logic reset;
    logic [511:0] message_block_in;
    logic [255:0] midstate_hash;
    logic flush;
    logic valid_in;
    logic [255:0] hash_out;
    logic valid_out;


    //localparam [511:0] TEST_MESSAGE_ABC = {24'h616263, 8'h80, 416'h0, 64'h18};
    //localparam [255:0] TEST_MESSAGE_HASH = {256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad};


    //Load 441 short test messages from test_message.hex and test_hash.hex
    localparam int NUM_TESTS = 441;
    logic [511:0] test_messages [0:NUM_TESTS-1];
    logic [255:0] test_hashes [0:NUM_TESTS-1];

    initial begin
        $readmemh("test_message.hex", test_messages);
        $readmemh("test_hash.hex", test_hashes);
    end

    //SHA256 initial hash values    
    localparam SHA256_H0_0 = 32'h6a09e667;
    localparam SHA256_H0_1 = 32'hbb67ae85;
    localparam SHA256_H0_2 = 32'h3c6ef372;
    localparam SHA256_H0_3 = 32'ha54ff53a;
    localparam SHA256_H0_4 = 32'h510e527f;
    localparam SHA256_H0_5 = 32'h9b05688c;
    localparam SHA256_H0_6 = 32'h1f83d9ab;
    localparam SHA256_H0_7 = 32'h5be0cd19;
    localparam [255:0] DEFAULT_HASH = {SHA256_H0_0, SHA256_H0_1, SHA256_H0_2, SHA256_H0_3, SHA256_H0_4, SHA256_H0_5, SHA256_H0_6, SHA256_H0_7};



    pipelinedhash pipeline_inst(
        .clk(clk),
        .reset(reset),
        .message_block_in(message_block_in),
        .midstate_hash(midstate_hash),
        .flush(flush),
        .valid_in(valid_in),
        .hash_out(hash_out),
        .valid_out(valid_out)
    );

    initial begin
        clk = 0;
        reset = 0;
        valid_in = 0;
        message_block_in = 0;
        midstate_hash = 0;
        #10 reset = 1;
        midstate_hash = DEFAULT_HASH;

        for (int i = 0; i < NUM_TESTS; i++) begin
            @(posedge clk);
            message_block_in = test_messages[i];
            valid_in = 1;
        end
        @(posedge clk);
        valid_in = 0;
        // Let monitor block verify and call $finish
    end

    // Parallel block: sample pipeline output and verify against expected hashes
    initial begin
        int result_count = 0;
        int fail_count = 0;
        wait (reset); // Wait for reset to complete
        forever begin
            @(posedge clk);
            if (valid_out) begin
                if (hash_out != test_hashes[result_count]) begin
                    fail_count++;
                    $display("FAIL [%0d] got %h expected %h", result_count, hash_out, test_hashes[result_count]);
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