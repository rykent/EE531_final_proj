//////////////////////////////////////////////////////////////////////////////////
// Company: Cal Poly
// Engineer: Glen Hayashibara
// 
// Create Date: 03/09/2026 12:38:23 PM
// Design Name: UART Receiver
// Module Name: uart_rx
// Description: Used for deserializing the signal from the UART   
//////////////////////////////////////////////////////////////////////////////////

module uart_rx #(
    parameter CLKS_PER_BIT = 10417
)(
    input  logic        clk,
    input  logic        reset_n,
    input  logic        rx_serial,
    output logic [7:0]  rx_data,
    output logic        rx_valid
);

    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } state_t;
    //States of deserializing the rx_serial signal
    state_t state;

    logic [15:0] clk_count;
    logic [2:0]  bit_index;
    logic [7:0]  rx_shift;
    
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= RX_IDLE;
        rx_valid <= 0;
        rx_data <= 0;
        rx_shift <= 0;
        clk_count <= 0;
        bit_index <= 0;
    end
    else begin
        rx_valid <= 0;
        case(state)
        //Wait for start bit
        RX_IDLE: begin
            clk_count <= 0;
            bit_index <= 0;
            if (rx_serial == 0)
                state <= RX_START;
        end

        //Align to center of start bit
        RX_START: begin
            if (clk_count == (CLKS_PER_BIT/2)) begin
                clk_count <= 0;
                if (rx_serial == 0)
                    state <= RX_DATA;
                else
                    state <= RX_IDLE;
            end
            else
                clk_count <= clk_count + 1;
        end

        //Read 8 data bits
        RX_DATA: begin
            if (clk_count < CLKS_PER_BIT-1)
                clk_count <= clk_count + 1;
            else begin
                clk_count <= 0;
                rx_shift[bit_index] <= rx_serial;
                if (bit_index < 7)
                    bit_index <= bit_index + 1;
                else begin
                    bit_index <= 0;
                    state <= RX_STOP;
                end
            end
        end

        //Stop bit
        RX_STOP: begin
            if (clk_count < CLKS_PER_BIT-1)
                clk_count <= clk_count + 1;
            else begin
                rx_data <= rx_shift;
                rx_valid <= 1;
                clk_count <= 0;
                state <= RX_IDLE;
            end
        end

        endcase
    end
end

endmodule