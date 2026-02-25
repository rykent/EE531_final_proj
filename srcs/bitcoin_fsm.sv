module bitcoin_fsm (
    input clk,
    input reset_n,
    input lane0_valid_out,
    input header_ready,
    input header_changed,
    output logic midstate_hash_we,
    output logic lane0_valid_in,
    output logic first_block,
    output logic all_lanes_valid,
    output logic flush,
    output logic nonce_cntr_reset
);

    //Bitcoin FSM
    //Initial version not including UART support
    typedef enum logic [2:0] {
        RESET,
        //HEADER_RECEIVE,
        BLOCK_0_HASH_COMPUTE,
        BLOCK_0_WAIT,
        PIPELINED_STAGE
        //GOLDEN_NONCE_STATE
    } bitcoin_fsm_state_t;

    bitcoin_fsm_state_t ps, ns;


    //PS logic
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ps <= RESET;
        end
        else begin
            ps <= ns;
        end
    end


    //NS logic
    always_comb begin

        nonce_cntr_reset = 0;
        case (ps)
            RESET: begin
                midstate_hash_we = 0;
                lane0_valid_in = 0;
                first_block = 0;
                all_lanes_valid = 0;
                flush = 1;
                if(header_ready) begin
                    ns = BLOCK_0_HASH_COMPUTE;
                end
                else begin
                    ns = RESET;
                end
            end
            BLOCK_0_HASH_COMPUTE: begin
                ns = BLOCK_0_WAIT;
                first_block = 1;
                lane0_valid_in = 1;
                all_lanes_valid = 0;
                flush = 0;
            end
            BLOCK_0_WAIT: begin
                lane0_valid_in = 0;
                first_block = 0;
                all_lanes_valid = 0;
                flush = 0;
                if (lane0_valid_out) begin
                    midstate_hash_we = 1;
                    nonce_cntr_reset = 1;
                    ns = PIPELINED_STAGE;
                end
                else begin
                    midstate_hash_we = 0;
                    ns = BLOCK_0_WAIT;
                end
            end
            PIPELINED_STAGE: begin
                if (header_changed) begin
                    ns = RESET;
                    flush = 1;
                    midstate_hash_we = 0;
                    first_block = 0;
                    lane0_valid_in = 0;
                    all_lanes_valid = 0;
                end
                else begin
                    ns = PIPELINED_STAGE;
                    flush = 0;
                    first_block = 0;
                    lane0_valid_in = 1;
                    all_lanes_valid = 1;
                    midstate_hash_we = 0;
                end

            end
            default: begin
                ns = RESET;
                midstate_hash_we = 0;
                lane0_valid_in = 0;
                first_block = 0;
                all_lanes_valid = 0;
                flush = 1;
            end
        endcase
    end
    
endmodule