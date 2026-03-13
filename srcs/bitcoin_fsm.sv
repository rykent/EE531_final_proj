module bitcoin_fsm (
    input clk,
    input reset_n,
    input lane0_valid_out,
    input header_valid,
    input golden_nonce_found,
    output logic midstate_hash_we,
    output logic lane0_valid_in,
    output logic first_block,
    output logic all_lanes_valid,
    output logic flush,
    output logic nonce_cntr_reset
);

    typedef enum logic [2:0] {
        RESET,
        HEADER_RECEIVE,
        BLOCK_0_HASH_COMPUTE,
        BLOCK_0_WAIT,
        PIPELINED_STAGE,
        GOLDEN_NONCE
    } bitcoin_fsm_state_t;

    bitcoin_fsm_state_t ps, ns;

    // Catch header_valid pulses that arrive during single-cycle states
    logic new_header_pending;

    //PS logic
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            ps <= RESET;
        else
            ps <= ns;
    end

    // new_header_pending flag
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            new_header_pending <= 0;
        else if (header_valid && ps != HEADER_RECEIVE
                              && ps != PIPELINED_STAGE
                              && ps != BLOCK_0_WAIT)
            new_header_pending <= 1;
        else if (ns == BLOCK_0_HASH_COMPUTE)
            new_header_pending <= 0;
    end

    //NS logic
    always_comb begin
        // Defaults
        midstate_hash_we = 0;
        lane0_valid_in   = 0;
        first_block      = 0;
        all_lanes_valid  = 0;
        flush            = 0;
        nonce_cntr_reset = 0;
        ns               = ps;

        case (ps)
            RESET: begin
                flush = 1;
                ns = HEADER_RECEIVE;
            end

            HEADER_RECEIVE: begin
                if (header_valid || new_header_pending)
                    ns = BLOCK_0_HASH_COMPUTE;
            end

            BLOCK_0_HASH_COMPUTE: begin
                first_block    = 1;
                lane0_valid_in = 1;
                ns = BLOCK_0_WAIT;
            end

            BLOCK_0_WAIT: begin
                if (header_valid) begin
                    flush = 1;
                    ns = BLOCK_0_HASH_COMPUTE;
                end
                else if (lane0_valid_out) begin
                    midstate_hash_we = 1;
                    nonce_cntr_reset = 1;
                    ns = PIPELINED_STAGE;
                end
            end

            PIPELINED_STAGE: begin
                lane0_valid_in  = 1;
                all_lanes_valid = 1;
                if (header_valid) begin
                    flush           = 1;
                    lane0_valid_in  = 0;
                    all_lanes_valid = 0;
                    ns = BLOCK_0_HASH_COMPUTE;
                end
                else if (golden_nonce_found) begin
                    lane0_valid_in  = 0;
                    all_lanes_valid = 0;
                    ns = GOLDEN_NONCE;
                end
            end

            GOLDEN_NONCE: begin
                flush = 1;
                if (header_valid || new_header_pending)
                    ns = BLOCK_0_HASH_COMPUTE;
                else
                    ns = HEADER_RECEIVE;
            end

            default: begin
                flush = 1;
                ns = RESET;
            end
        endcase
    end

endmodule
