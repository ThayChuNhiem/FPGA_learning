//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/12/2026 02:04:05 PM
// Design Name: 
// Module Name: fis_bram
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
module fis_bram (
    input clk,
    input we,             // Write Enable
    input [9:0] addr,     // Mức giá (Price level) - 1024 mức
    input [15:0] din,     // Con trỏ Head (Head Pointer)
    output reg [15:0] dout // Dữ liệu đọc ra
);
    // Attribute ép Vivado dùng BRAM
    (* ram_style = "block" *) reg [15:0] ram [0:1023]; 

    always @(posedge clk) begin
        if (we) begin
            ram[addr] <= din;
        end
        // Độ trễ 1 cycle
        dout <= ram[addr]; 
    end
endmodule
