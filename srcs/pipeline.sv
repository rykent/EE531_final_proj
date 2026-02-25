module pipelinedhash (
    input clk,
    input reset_n,
    input [511:0] message_block_in,     //512 bits of message block
    input [255:0] midstate_hash,        //256 bits of initial hash input
    input flush,                        //Flush the pipeline when bitcoin header changes
    input valid_in,                     //Valid input when message block is valid
    output [255:0] hash_out,            //256 bits of hash output
    output valid_out                    //Valid output when hash is computed
);

    //Helper functions for sha256 ops
    //Big sigma and small sigma functions
    function automatic [31:0] bigsigma0(input [31:0] x);
        return {x[1:0], x[31:2]} ^ {x[12:0], x[31:13]} ^ {x[21:0], x[31:22]};
    endfunction

    function automatic [31:0] bigsigma1(input [31:0] x);
        return {x[5:0], x[31:6]} ^ {x[10:0], x[31:11]} ^ {x[24:0], x[31:25]};
    endfunction

    function automatic [31:0] smallsigma0(input [31:0] x);
        return {x[6:0], x[31:7]} ^ {x[17:0], x[31:18]} ^ {3'b0,x[31:3]};
    endfunction

    function automatic [31:0] smallsigma1(input [31:0] x);
        return {x[16:0], x[31:17]} ^ {x[18:0], x[31:19]} ^ {10'b0, x[31:10]};
    endfunction

    //Maj and Ch functions
    function automatic [31:0] maj(input [31:0] x, input [31:0] y, input [31:0] z);
        return (x & y) ^ (x & z) ^ (y & z);
    endfunction

    function automatic [31:0] ch(input [31:0] x, input [31:0] y, input [31:0] z);
        return (x & y) ^ (~x & z);
    endfunction

    //SHA256 initial hash values    
    localparam SHA256_H0_0 = 32'h6a09e667;
    localparam SHA256_H0_1 = 32'hbb67ae85;
    localparam SHA256_H0_2 = 32'h3c6ef372;
    localparam SHA256_H0_3 = 32'ha54ff53a;
    localparam SHA256_H0_4 = 32'h510e527f;
    localparam SHA256_H0_5 = 32'h9b05688c;
    localparam SHA256_H0_6 = 32'h1f83d9ab;
    localparam SHA256_H0_7 = 32'h5be0cd19;

    // SHA-256 round constants K[0..63]
    localparam logic [31:0] K [0:63] = '{
        32'h428a2f98, 32'h71374491, 32'hb5c0fbcf, 32'he9b5dba5, 32'h3956c25b,
        32'h59f111f1, 32'h923f82a4, 32'hab1c5ed5, 32'hd807aa98, 32'h12835b01,
        32'h243185be, 32'h550c7dc3, 32'h72be5d74, 32'h80deb1fe, 32'h9bdc06a7,
        32'hc19bf174, 32'he49b69c1, 32'hefbe4786, 32'h0fc19dc6, 32'h240ca1cc,
        32'h2de92c6f, 32'h4a7484aa, 32'h5cb0a9dc, 32'h76f988da, 32'h983e5152,
        32'ha831c66d, 32'hb00327c8, 32'hbf597fc7, 32'hc6e00bf3, 32'hd5a79147,
        32'h06ca6351, 32'h14292967, 32'h27b70a85, 32'h2e1b2138, 32'h4d2c6dfc,
        32'h53380d13, 32'h650a7354, 32'h766a0abb, 32'h81c2c92e, 32'h92722c85,
        32'ha2bfe8a1, 32'ha81a664b, 32'hc24b8b70, 32'hc76c51a3, 32'hd192e819,
        32'hd6990624, 32'hf40e3585, 32'h106aa070, 32'h19a4c116, 32'h1e376c08,
        32'h2748774c, 32'h34b0bcb5, 32'h391c0cb3, 32'h4ed8aa4a, 32'h5b9cca4f,
        32'h682e6ff3, 32'h748f82ee, 32'h78a5636f, 32'h84c87814, 32'h8cc70208,
        32'h90befffa, 32'ha4506ceb, 32'hbef9a3f7, 32'hc67178f2
    };

    //**************************************************
    //Pipeline Registers
    //**************************************************

    typedef struct packed {
        logic [31:0] w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15;
        logic [31:0] a, b, c, d, e, f, g, h;
        logic valid;
    } pipeline_reg_t;

    pipeline_reg_t stage_in[64];  //wires to connect stages
    pipeline_reg_t stage_out[64]; //registers between stages


    //Pipeline input logic
    assign stage_in[0].w0 = message_block_in[511:480];
    assign stage_in[0].w1 = message_block_in[479:448];
    assign stage_in[0].w2 = message_block_in[447:416];
    assign stage_in[0].w3 = message_block_in[415:384];
    assign stage_in[0].w4 = message_block_in[383:352];
    assign stage_in[0].w5 = message_block_in[351:320];
    assign stage_in[0].w6 = message_block_in[319:288];
    assign stage_in[0].w7 = message_block_in[287:256];
    assign stage_in[0].w8 = message_block_in[255:224];
    assign stage_in[0].w9 = message_block_in[223:192];
    assign stage_in[0].w10 = message_block_in[191:160];
    assign stage_in[0].w11 = message_block_in[159:128];
    assign stage_in[0].w12 = message_block_in[127:96];
    assign stage_in[0].w13 = message_block_in[95:64];
    assign stage_in[0].w14 = message_block_in[63:32];
    assign stage_in[0].w15 = message_block_in[31:0];
    assign stage_in[0].a = midstate_hash[255:224];
    assign stage_in[0].b = midstate_hash[223:192];
    assign stage_in[0].c = midstate_hash[191:160];
    assign stage_in[0].d = midstate_hash[159:128];
    assign stage_in[0].e = midstate_hash[127:96];
    assign stage_in[0].f = midstate_hash[95:64];
    assign stage_in[0].g = midstate_hash[63:32];
    assign stage_in[0].h = midstate_hash[31:0];
    assign stage_in[0].valid = valid_in;


    //Pipeline stages
    generate
        for (genvar i = 0; i < 64; i++) begin : PIPELINE_STAGE
            localparam logic [31:0] Ki = K[i];

            always_ff @(posedge clk or negedge reset_n) begin
                if (!reset_n | flush) begin
                    stage_out[i].w0 <= 32'b0;
                    stage_out[i].w1 <= 32'b0;
                    stage_out[i].w2 <= 32'b0;
                    stage_out[i].w3 <= 32'b0;
                    stage_out[i].w4 <= 32'b0;
                    stage_out[i].w5 <= 32'b0;
                    stage_out[i].w6 <= 32'b0;
                    stage_out[i].w7 <= 32'b0;
                    stage_out[i].w8 <= 32'b0;
                    stage_out[i].w9 <= 32'b0;
                    stage_out[i].w10 <= 32'b0;
                    stage_out[i].w11 <= 32'b0;
                    stage_out[i].w12 <= 32'b0;
                    stage_out[i].w13 <= 32'b0;
                    stage_out[i].w14 <= 32'b0;
                    stage_out[i].w15 <= 32'b0;
                    stage_out[i].a <= 32'b0;
                    stage_out[i].b <= 32'b0;
                    stage_out[i].c <= 32'b0;
                    stage_out[i].d <= 32'b0;
                    stage_out[i].e <= 32'b0;
                    stage_out[i].f <= 32'b0;
                    stage_out[i].g <= 32'b0;
                    stage_out[i].h <= 32'b0;
                    stage_out[i].valid <= 0;
                end
                else begin
                    //Message schedule logic
                    //16 wide sliding windows 
                    stage_out[i].w0 <= stage_in[i].w1;
                    stage_out[i].w1 <= stage_in[i].w2;
                    stage_out[i].w2 <= stage_in[i].w3;
                    stage_out[i].w3 <= stage_in[i].w4;
                    stage_out[i].w4 <= stage_in[i].w5;
                    stage_out[i].w5 <= stage_in[i].w6;
                    stage_out[i].w6 <= stage_in[i].w7;
                    stage_out[i].w7 <= stage_in[i].w8;
                    stage_out[i].w8 <= stage_in[i].w9;
                    stage_out[i].w9 <= stage_in[i].w10;
                    stage_out[i].w10 <= stage_in[i].w11;
                    stage_out[i].w11 <= stage_in[i].w12;
                    stage_out[i].w12 <= stage_in[i].w13;
                    stage_out[i].w13 <= stage_in[i].w14;
                    stage_out[i].w14 <= stage_in[i].w15;
                    stage_out[i].w15 <= smallsigma1(stage_in[i].w14) + stage_in[i].w9 + smallsigma0(stage_in[i].w1) + stage_in[i].w0;

                    //Working variables logic a-h
                    //TODO a reg is probably critical path
                    stage_out[i].a <= stage_in[i].h + bigsigma1(stage_in[i].e) + ch(stage_in[i].e, stage_in[i].f, stage_in[i].g) + Ki + stage_in[i].w0 + bigsigma0(stage_in[i].a) + maj(stage_in[i].a, stage_in[i].b, stage_in[i].c);
                    stage_out[i].b <= stage_in[i].a;
                    stage_out[i].c <= stage_in[i].b;
                    stage_out[i].d <= stage_in[i].c;
                    stage_out[i].e <= stage_in[i].d + stage_in[i].h + bigsigma1(stage_in[i].e) + ch(stage_in[i].e, stage_in[i].f, stage_in[i].g) + Ki + stage_in[i].w0;
                    stage_out[i].f <= stage_in[i].e;
                    stage_out[i].g <= stage_in[i].f;
                    stage_out[i].h <= stage_in[i].g;

                    //Valid
                    stage_out[i].valid <= stage_in[i].valid;

                end
            end


            //Special case for last stage
            if (i < 63) begin
                assign stage_in[i+1] = stage_out[i];
            end
        end
    endgenerate


    //Final hash output logic

    logic [31:0] h0, h1, h2, h3, h4, h5, h6, h7;
    assign h0 = stage_out[63].a + midstate_hash[255:224];
    assign h1 = stage_out[63].b + midstate_hash[223:192];
    assign h2 = stage_out[63].c + midstate_hash[191:160];
    assign h3 = stage_out[63].d + midstate_hash[159:128];
    assign h4 = stage_out[63].e + midstate_hash[127:96];
    assign h5 = stage_out[63].f + midstate_hash[95:64];
    assign h6 = stage_out[63].g + midstate_hash[63:32];
    assign h7 = stage_out[63].h + midstate_hash[31:0];
    assign hash_out = {h0, h1, h2, h3, h4, h5, h6, h7};
    assign valid_out = stage_out[63].valid;


endmodule   
    