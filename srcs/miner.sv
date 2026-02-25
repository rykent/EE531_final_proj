module miner #(parameter NUM_LANES = 1)(
    input clk,
    input reset_n,
    input [639:0] bitcoin_header,
    input header_ready,
    input header_changed,
    output logic [255:0] final_hash_le [NUM_LANES-1:0],
    output logic [31:0] valid_out [NUM_LANES-1:0]
    //input uart_rx,
    //output uart_tx
);

    //Miner

    function automatic [255:0] bswap256(input [255:0] x);
    automatic logic [255:0] y;
    for (int i = 0; i < 32; i++) begin
        y[i*8 +: 8] = x[(31-i)*8 +: 8];
    end
    return y;
    endfunction


    //FSM
    //State machine
    // RESET STATE
    // HEADER RECIEVE STATE (UART RX)
    // block 0 hash computuation state (use only lane 0 to compute block 0 hash)
    // block 0 wait state (wait for block 0 hash to be computed)
    // PIPELINED STAGE ( run round 1 and 2 using intermediate hash of block 0 for round 1) (use all lanes)
    // GOLDEN NONCE STATE (valid nonce found in a lane, send to UART TX)
    logic lane0_valid_out;
    logic midstate_hash_we;
    logic lane0_valid_in;
    logic first_block;
    logic all_lanes_valid;
    logic flush;
    logic nonce_cntr_reset;
    
    bitcoin_fsm bitcoin_fsm_inst(
        .clk(clk),
        .reset_n(reset_n),
        .lane0_valid_out(lane0_valid_out),
        .header_ready(header_ready),
        .header_changed(header_changed),
        .midstate_hash_we(midstate_hash_we),
        .lane0_valid_in(lane0_valid_in),
        .first_block(first_block),
        .all_lanes_valid(all_lanes_valid),
        .flush(flush),
        .nonce_cntr_reset(nonce_cntr_reset)
    );


    //SHA256 Pipeline
    //Parameterized number of lanes

    logic [255:0] r1_hash [NUM_LANES-1:0];

    localparam DEFAULT_HASH = 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    //Midstate hash register
    logic [255:0] midstate_hash;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n | flush) begin
            midstate_hash <= DEFAULT_HASH;
        end
        else if (midstate_hash_we) begin
            midstate_hash <= r1_hash[0];
        end
    end

    //Each lane
    //1 pipeline for first round
    //1 pipeline for second round
    //1 nonce counter adding by stride(#of lanes)

    logic [255:0] final_hash[NUM_LANES-1:0];
    //logic [255:0] final_hash_le[NUM_LANES-1:0]; //Little endian hash
    

    
    logic valid_in[NUM_LANES-1:0];
    logic valid_out_intermediate[NUM_LANES-1:0];

    assign lane0_valid_out = valid_out_intermediate[0];

    generate
        for (genvar i = 0; i < NUM_LANES; i++) begin : LANE

            assign final_hash_le[i] = bswap256(final_hash[i]);

            if (i == 0) begin
                assign valid_in[i] = lane0_valid_in;
            end
            else begin
                assign valid_in[i] = all_lanes_valid;
            end


            logic [31:0] nonce_le;
            logic [511:0] message_block_r1;
            logic [511:0] message_block_r2;

            nonce_cntr #(.STRIDE(NUM_LANES), .START(i)) nonce_cntr_inst(
                .clk(clk),
                .reset_n(reset_n),
                .reset_s(nonce_cntr_reset),
                .nonce_out(nonce_le)
            );

            if (i == 0) begin
                sha256_prepare_r1_lane0 sha256_prepare_r1_lane0_inst(
                    .header(bitcoin_header), // TODO
                    .nonce_le(nonce_le),
                    .first_block(first_block),
                    .message_block_out(message_block_r1)
                ) ;
            end
            else begin
                sha256_prepare_r1 sha256_prepare_r1_inst(
                    .header(bitcoin_header[127:32]), //TODO: 
                    .nonce_le(nonce_le),
                    .message_block_out(message_block_r1)
                );
            end

            pipelinedhash pipeline_inst(
                .clk(clk),
                .reset_n(reset_n),
                .message_block_in(message_block_r1),
                .midstate_hash(midstate_hash),
                .flush(flush),
                .valid_in(valid_in[i]),
                .hash_out(r1_hash[i]),
                .valid_out(valid_out_intermediate[i])
            );

            sha256_prepare_r2 sha256_prepare_r2_inst(
                .first_round_hash(r1_hash[i]),
                .message_block_out(message_block_r2)
            );

            pipelinedhash pipeline_inst_r2(
                .clk(clk),
                .reset_n(reset_n),
                .message_block_in(message_block_r2),
                .midstate_hash(DEFAULT_HASH),
                .flush(flush),
                .valid_in(valid_out_intermediate[i] & all_lanes_valid),
                .hash_out(final_hash[i]),
                .valid_out(valid_out[i])
            );


        end
    endgenerate

    
endmodule