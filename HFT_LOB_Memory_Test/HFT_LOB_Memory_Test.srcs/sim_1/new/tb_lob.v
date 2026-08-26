//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/12/2026 02:08:02 PM
// Design Name: 
// Module Name: tb_lob
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


`timescale 1ns / 1ps
module tb_lob();
    reg clk;
    reg reset;
    reg valid_in;
    reg [9:0] price_in;
    reg [71:0] order_info_in;
    
    wire [15:0] head_ptr_out;
    wire [71:0] order_read_out;

    lob_controller uut (
        .clk(clk), .reset(reset), .valid_in(valid_in),
        .price_in(price_in), .order_info_in(order_info_in),
        .head_ptr_out(head_ptr_out), .order_read_out(order_read_out)
    );

    // Tạo xung nhịp 250MHz (chu kỳ 4ns) - Tốc độ chuẩn cho HFT
    always #2 clk = ~clk; 

    initial begin
        // Khởi tạo
        clk = 0; reset = 1; valid_in = 0;
        price_in = 0; order_info_in = 0;
        
        #10 reset = 0;
        
        // Bơm gói tin Add Order giả lập
        #4 valid_in = 1; price_in = 10'd500; order_info_in = 72'hFFFF_EEEE_DDDD_CCCC;
        #4 valid_in = 0; // Tắt ghi, chuyển sang đọc
        
        // Đợi để quan sát độ trễ (Latency)
        #20;
        $finish;
    end
endmodule
