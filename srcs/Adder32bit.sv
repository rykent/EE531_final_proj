module CSA32 #(parameter W=32)
(
    input logic [W-1:0] a, b, c,
    output logic [W-1:0] sum, carry
);
    assign sum = a ^ b ^ c;
    assign carry = (a & b) | (b & c) | (a & c);
endmodule
