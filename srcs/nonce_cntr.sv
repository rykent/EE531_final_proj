module nonce_cntr #(parameter STRIDE = 1, parameter START = 0)(
    input clk,
    input reset_n,
    input reset_s,
    output [31:0] nonce_out //Little endian nonce
);

    //Nonce counter
    logic [31:0] nonce_reg;
    //Convert to little endian
    assign nonce_out = {nonce_reg[7:0], nonce_reg[15:8], nonce_reg[23:16], nonce_reg[31:24]};

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            nonce_reg <= START;
        else if (reset_s)
            nonce_reg <= START;
        else
            nonce_reg <= nonce_reg + STRIDE;
    end
    
endmodule