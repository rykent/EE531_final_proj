//////////////////////////////////////////////////////////////////////////////////
// Company: Cal Poly
// Engineer: Ryken Thompson
// 
// Create Date: 03/09/2026 12:38:23 PM
// Design Name: UART Header Deserializer
// Module Name: uart_header_deserializer
// Description: Used to deserialize the header from the UART
//              and store it in a register.
// Additional Comments: To be used for interfacing
//                      with the UART display
//////////////////////////////////////////////////////////////////////////////////

module uart_header_deserializer(
    input  logic         clk,
    input  logic         reset_n,
    input  logic [7:0]   byte_in,
    input  logic         byte_valid,
    output logic [639:0] header_out,
    output logic         header_valid
);

    logic [639:0] header_reg;
    logic [6:0]   byte_index;
    logic         receiving;


    assign header_out = header_reg;
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            header_reg <= 0;
            header_valid <= 0;
            receiving <= 0;
            byte_index <= 0;
        end 
        else begin
            if (byte_valid && !receiving) begin
                //Look for magic byte 0xBB and start deserializing the header
                header_valid <= 0;
                if (byte_in == 8'hBB) begin
                    receiving <= 1;
                    byte_index <= 0;
                    header_reg <= 0;
                end
                else begin
                    receiving <= 0;
                end
            end
            else if (byte_valid && receiving) begin
                header_reg <= {header_reg[631:0], byte_in}; // Shift in the new byte
                if (byte_index == 79) begin
                    header_valid <= 1;
                    receiving <= 0;
                    byte_index <= 0;
                end
                else begin
                    byte_index <= byte_index + 1;
                    header_valid <= 0;
                end
            end
            else begin
                header_valid <= 0;
            end
        end
    end
endmodule