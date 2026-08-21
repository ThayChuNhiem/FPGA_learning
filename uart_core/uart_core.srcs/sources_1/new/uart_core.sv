`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/17/2026 02:53:15 PM
// Design Name: 
// Module Name: uart_core
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_core #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst_n,

    // TX Interface
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_busy,
    output logic       tx_pin,

    // RX Interface
    input  logic       rx_pin,
    output logic [7:0] rx_data,
    output logic       rx_valid
    );
    //so chu ki clk can de luu 1 bit
    localparam int CLK_PER_BIT = CLK_FREQ / BAUD_RATE;
    //so bit can de cho bo dem thoi gian
    localparam int CLKS_WIDTH = $clog2(CLK_PER_BIT);
    
    
    //2 tang ff de chong matastability
    //  trong do rx_pin la tin dau vao bat dong bo nen can qua 2 ff
    //  di qua 2 ff la rx_sync va rx_sync_1
    logic rx_sync, rx_sync_1;
    
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            rx_sync <= 1'b1;
            rx_sync_1 <= 1'b1;
        end 
        else begin
            rx_sync_1 <= rx_pin;
            rx_sync <= rx_sync_1;
        end
            
    end
    
    //4 trang thai may phat UART transmit
    typedef enum logic [1:0] {
        TX_IDLE = 2'b00,
        TX_START = 2'b01,
        TX_DATA = 2'b10,
        TX_STOP = 2'b11
    }tx_state_t;
    
    tx_state_t tx_state;
    logic   [CLKS_WIDTH-1:0]   tx_clk_cnt;      //bo dem do dau clk
    logic   [2:0]              tx_bit_index;    //index du lieu dang truyen
    logic   [7:0]              tx_shift_reg;    //thanh ghi dem ghi du lieu can truyen
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tx_state <= TX_IDLE;
            tx_clk_cnt <= '0;
            tx_bit_index <= '0;
            tx_shift_reg <= '0;
            tx_busy <= 1'b0;
            tx_pin <= 1'b1;
        end else begin
            case(tx_state)
                TX_IDLE : begin
                    tx_pin <= 1'b1;
                    tx_busy <= 1'b0;
                    if(tx_start) begin
                        tx_busy <= 1'b1;            // ra tin hieu ban
                        tx_shift_reg <= tx_data;    // chot data roi gui
                        tx_state <= TX_START;       // chuyen sang qua trinh gui
                        tx_clk_cnt <= '0;           // reset bo dem
                    end         
                end
                
                TX_START : begin
                    tx_pin <= 1'b0;     //tao bit start roi giu trong thoi gian 1 bit
                    if(tx_clk_cnt < CLK_PER_BIT - 1'b1)
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                     else begin
                        tx_clk_cnt <= '0;       //reset bo dem
                        tx_bit_index <= '0;     //reset index
                        tx_state <= TX_DATA;    //chuyen sang state data
                     end
                end
                
                TX_DATA : begin
                    tx_pin <= tx_shift_reg[tx_bit_index];
                    if(tx_clk_cnt < CLK_PER_BIT - 1'b1)
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    else begin
                        tx_clk_cnt <= '0;
                        if(tx_bit_index < 3'd7) 
                            tx_bit_index <= tx_bit_index + 1'b1;
                        else 
                            tx_state <= TX_STOP;
                    end
                end
                
                TX_STOP : begin
                    tx_pin <= 1'b1; //ra dau hieu stop
                    if(tx_clk_cnt < CLK_PER_BIT - 1'b1)
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    else begin
                        tx_clk_cnt <= '0;
                        tx_busy <= 1'b0;
                        tx_state <= TX_IDLE;
                    end
                end
                
                default : tx_state <= TX_IDLE;
            endcase
        end
    end
    
    
    //4 trang thai may nhan UART receive
    typedef enum logic [1:0] {
        RX_IDLE =   2'b00,
        RX_START =  2'b01,
        RX_DATA =   2'b10,
        RX_STOP =   2'b11
    }rx_state_t;
    
    rx_state_t  rx_state;   //khai bao thanh ghi
    logic   [CLKS_WIDTH-1:0]   rx_clk_cnt;      //bo dem do dau clk
    logic   [2:0]              rx_bit_index;    //index du lieu dang nhan
    logic   [7:0]              rx_shift_reg;    //thanh ghi dem ghi du lieu can nhan
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_state <= RX_IDLE;
            rx_data <= '0;
            rx_valid <= 1'b0;
            rx_clk_cnt <= '0;
            rx_bit_index <= '0;
            rx_shift_reg <= '0;
        end else begin
            rx_valid <= 1'b0;   //valid chi trong 1 chu ki
            case(rx_state)
                RX_IDLE : begin
                    rx_clk_cnt <= '0;
                    rx_bit_index <= '0;
                    if(rx_sync == 1'b0)         //nhan tin hieu start
                        rx_state <= RX_START;
                end
                
                RX_START : begin
                    if(rx_clk_cnt == (CLK_PER_BIT / 2) - 1'b1) begin    //dem bit o giua de do nhieu
                        if(!rx_sync) begin
                            rx_clk_cnt <= '0;   //reset bo dem ve 0
                            rx_state <= RX_DATA;
                        end else 
                            rx_state <= RX_IDLE;
                    end else
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                end
                
                RX_DATA : begin
                    if(rx_clk_cnt < CLK_PER_BIT - 1'b1) //van lay bit o giua
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    else begin
                        rx_clk_cnt <= '0;
                        rx_shift_reg[rx_bit_index] <= rx_sync;
                        if(rx_bit_index < 3'd7)
                            rx_bit_index <= rx_bit_index + 1'b1;
                        else begin
                            rx_state <= RX_STOP;
                            rx_clk_cnt <= '0;
                        end
                    end
                end
                
                RX_STOP : begin
                    if(rx_clk_cnt < CLK_PER_BIT - 1'b1)
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    else begin
                        rx_clk_cnt <= '0;
                        if(rx_sync) begin
                            rx_valid <= 1'b1;
                            rx_data <= rx_shift_reg;
                        end
                        rx_state <= RX_IDLE;
                    end
                end
                
                default : rx_state <= RX_IDLE;
            endcase
        end
    end
endmodule
