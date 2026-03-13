//////////////////////////////////////////////////////////////////////////////////
// Company: Cal Poly
// Engineer: Glen Hayashibara
// 
// Create Date: 03/09/2026 12:38:23 PM
// Design Name: UART 640-bit Hash Serializer
// Module Name: uart_hash_serializer
// Description: Used to serialize the 640-bit hash
//              from the bitcoin mining output.
// Additional Comments: To be used for interfacing
//                      with the UART display
//////////////////////////////////////////////////////////////////////////////////

module uart_hash_serializer(
    input  logic         clk,
    input  logic         reset_n,
    input  logic [639:0] hash_in,
    input  logic         hash_valid,
    input  logic         tx_ready,       // handshake with Tx
    output logic [7:0]   byte_out,
    output logic         byte_valid
);

    logic [639:0] hash_reg;
    logic [6:0]   byte_index;
    logic         sending;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sending    <= 0;
            byte_index <= 0;
            byte_out   <= 0;
            byte_valid <= 0;
            hash_reg   <= 0;
        end
        else begin
            if (hash_valid && !sending) begin
                hash_reg   <= hash_in;
                sending    <= 1;
                byte_index <= 0;
                byte_valid <= 0;
            end
            else if (sending && tx_ready) begin
                byte_out   <= hash_reg[639:632];
                hash_reg   <= {hash_reg[631:0], 8'h00};
                byte_valid <= 1;
                if (byte_index == 79) begin
                    sending <= 0;
                end
                else begin
                    byte_index <= byte_index + 1;
                end
            end
        end
    end
endmodule