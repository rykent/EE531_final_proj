module sha256_prepare_r1 (
    input [95:0] header,
    input [31:0] nonce_le,
    output [511:0] message_block_out
);
    //Append 0x280 to the end of the header for length
    assign message_block_out = {header, nonce_le, 8'h80, 312'b0, 64'h280};

endmodule


//Lane 0 is only lane that needs to compute the first block hash for round 1
module sha256_prepare_r1_lane0 (
    input [639:0] header,
    input [31:0] nonce_le,
    input first_block,
    output logic [511:0] message_block_out
);

    always_comb begin
        if(first_block) begin
            message_block_out = header[639:128];
        end
        else begin
            //Append 0x280 to the end of the header for length
            message_block_out = {header[127:32], nonce_le, 8'h80, 312'b0, 64'h280};
        end
    end
endmodule

module sha256_prepare_r2 (
    input [255:0] first_round_hash,
    output [511:0] message_block_out
);
    assign message_block_out = {first_round_hash, 8'h80, 184'b0, 64'h100};

endmodule