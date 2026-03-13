//////////////////////////////////////////////////////////////////////////////////
// Company: Cal Poly
// Engineer: Glen Hayashibara
// 
// Design Name: Transmitter to UART
// Module Name: uart_tx
// Description: Used to take the serialized bytes of data
//              and concatenate them with start and stop bits
//              to deal with single serial data port.
// Additional Comments: 1 start "0" bit, 8 data bits, 1 stop "0" bit                
//////////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter CLKS_PER_BIT = 10417
)(
    input  logic       clk,
    input  logic       reset_n,
    input  logic [7:0] tx_data,     //hash_serializer byte to turn into tx_serial
    input  logic       tx_start,    //Tell Tx to start serializing tx_data
    output logic       tx_serial,   //Serial data signal
    output logic       sending      //Tx busy indicator
);

    logic [9:0] shift_reg;   //start + 8 data + stop
    logic [3:0] bit_counter; //Incrementer for shift_reg
    logic [15:0] clk_counter;//Used with clocks per bit speed
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin   //Reset situation
            shift_reg <= 10'b1111111111;
            bit_counter <= 0;
            clk_counter <= 0;
            sending <= 0;
            tx_serial <= 1;
        end 
        else begin
            //Start serial signal sending if not already doing so
            if (tx_start && !sending) begin
                // load start + data + stop bits
                shift_reg <= {1'b1, tx_data, 1'b0};
                bit_counter <= 0;
                clk_counter <= 0;
                sending <= 1;
                tx_serial <= 0;             //Start bit
            end 
            //Begin sending signal if we have started
            else if (sending) begin
                if (clk_counter < CLKS_PER_BIT-1) begin
                    clk_counter <= clk_counter + 1;
                end 
                else begin
                    clk_counter <= 0;
                    bit_counter <= bit_counter + 1;
                    if (bit_counter < 9)
                        //Increment through the start, data,
                        //and stop bits of the packaged data byte
                        tx_serial <= shift_reg[bit_counter + 1];
                    else begin
                        sending <= 0;
                        tx_serial <= 1;       // idle
                    end
                end
            end
        end
    end
endmodule