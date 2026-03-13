module miner #(
    parameter NUM_LANES = 1,
    parameter CLKS_PER_BIT = 10417
)(
    input clk,
    input reset_n,
    input uart_rx,
    output logic uart_tx
);

    //Miner

    // UART RX path: receive header from PC
    logic [7:0]   rx_byte;
    logic         rx_valid;
    logic [639:0] header_from_uart;
    logic         header_valid;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) rx_mod(
        .clk(clk),
        .reset_n(reset_n),
        .rx_serial(uart_rx),
        .rx_data(rx_byte),
        .rx_valid(rx_valid)
    );

    uart_header_deserializer deserializer(
        .clk(clk),
        .reset_n(reset_n),
        .byte_in(rx_byte),
        .byte_valid(rx_valid),
        .header_out(header_from_uart),
        .header_valid(header_valid)
    );

    // Internal bitcoin header register: latched from UART RX
    logic [639:0] bitcoin_header;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            bitcoin_header <= '0;
        else if (header_valid)
            bitcoin_header <= header_from_uart;
    end

    //Target computer and comparison signals
    //Target register
    logic [255:0] target_reg;
    logic [255:0] target_in;

    // Inline expand_nbits_to_target_be: convert nBits field to 256-bit target
    logic [31:0]  nbits_le_wire;
    logic [31:0]  nbits_be;
    logic [7:0]   nbits_exponent;
    logic [23:0]  nbits_coefficient;
    assign nbits_le_wire     = header_from_uart[63:32];
    assign nbits_be          = {nbits_le_wire[7:0], nbits_le_wire[15:8],
                                nbits_le_wire[23:16], nbits_le_wire[31:24]};
    assign nbits_exponent    = nbits_be[31:24];
    assign nbits_coefficient = nbits_be[23:0];
    assign target_in = (nbits_exponent >= 8'd3)
        ? ({232'd0, nbits_coefficient} << (8 * (nbits_exponent - 8'd3)))
        : ({232'd0, nbits_coefficient} >> (8 * (8'd3 - nbits_exponent)));

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            target_reg <= 0;
        end
        else if (header_valid) begin
            target_reg <= target_in;
        end
    end

    //Golden nonce detection
    logic [NUM_LANES-1:0] golden_nonce;
    logic                 golden_nonce_found;
    logic [31:0]          lane_nonce_delayed [NUM_LANES-1:0];

    assign golden_nonce_found = |golden_nonce;

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
        .header_valid(header_valid),
        .golden_nonce_found(golden_nonce_found),
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
        if (!reset_n)
            midstate_hash <= DEFAULT_HASH;
        else if (flush)
            midstate_hash <= DEFAULT_HASH;
        else if (midstate_hash_we)
            midstate_hash <= r1_hash[0];
    end

    //Each lane
    //1 pipeline for first round
    //1 pipeline for second round
    //1 nonce counter adding by stride(#of lanes)

    logic [255:0] final_hash[NUM_LANES-1:0];
    logic [255:0] final_hash_le[NUM_LANES-1:0];
    logic valid_out[NUM_LANES-1:0];

    logic valid_in[NUM_LANES-1:0];
    logic valid_out_intermediate[NUM_LANES-1:0];

    assign lane0_valid_out = valid_out_intermediate[0];

    generate
        for (genvar i = 0; i < NUM_LANES; i++) begin : LANE

            // Byte-swap 256 bits (reverse byte order for LE comparison)
            logic [255:0] fh;
            assign fh = final_hash[i];
            assign final_hash_le[i] = {
                fh[7:0],    fh[15:8],   fh[23:16],  fh[31:24],
                fh[39:32],  fh[47:40],  fh[55:48],  fh[63:56],
                fh[71:64],  fh[79:72],  fh[87:80],  fh[95:88],
                fh[103:96], fh[111:104],fh[119:112],fh[127:120],
                fh[135:128],fh[143:136],fh[151:144],fh[159:152],
                fh[167:160],fh[175:168],fh[183:176],fh[191:184],
                fh[199:192],fh[207:200],fh[215:208],fh[223:216],
                fh[231:224],fh[239:232],fh[247:240],fh[255:248]
            };

            if (i == 0) begin : LANE0_VALID_IN
                assign valid_in[i] = lane0_valid_in;
            end
            else begin : OTHER_LANES_VALID_IN
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

            // Nonce delay shift register (128 deep = 64 R1 + 64 R2 pipeline stages)
            logic [31:0] nonce_delay [0:127];
            always_ff @(posedge clk)
                nonce_delay[0] <= nonce_le;
            for (genvar j = 1; j < 128; j++) begin : NONCE_SHIFT
                always_ff @(posedge clk)
                    nonce_delay[j] <= nonce_delay[j-1];
            end
            assign lane_nonce_delayed[i] = nonce_delay[127];

            // Per-lane golden nonce comparison
            assign golden_nonce[i] = valid_out[i] && (final_hash_le[i] < target_reg);

        end
    endgenerate

    // Priority encoder: select lowest-indexed lane with a golden nonce
    localparam LANE_IDX_W = (NUM_LANES > 1) ? $clog2(NUM_LANES) : 1;
    logic [LANE_IDX_W-1:0] winning_lane;
    always_comb begin
        winning_lane = '0;
        for (int i = NUM_LANES-1; i >= 0; i--) begin
            if (golden_nonce[i])
                winning_lane = i[LANE_IDX_W-1:0];
        end
    end

    // Build golden header: original header with winning nonce at [31:0]
    logic [31:0]  winning_nonce;
    logic [639:0] golden_header;
    assign winning_nonce = lane_nonce_delayed[winning_lane];
    assign golden_header = {bitcoin_header[639:32], winning_nonce};

    // UART TX: serialize and transmit golden header
    logic [7:0] tx_byte;
    logic       tx_start;
    logic       tx_busy;

    uart_hash_serializer golden_serializer(
        .clk(clk),
        .reset_n(reset_n),
        .hash_in(golden_header),
        .hash_valid(golden_nonce_found),
        .tx_ready(!tx_busy),
        .byte_out(tx_byte),
        .byte_valid(tx_start)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) golden_tx(
        .clk(clk),
        .reset_n(reset_n),
        .tx_data(tx_byte),
        .tx_start(tx_start),
        .tx_serial(uart_tx),
        .sending(tx_busy)
    );

endmodule