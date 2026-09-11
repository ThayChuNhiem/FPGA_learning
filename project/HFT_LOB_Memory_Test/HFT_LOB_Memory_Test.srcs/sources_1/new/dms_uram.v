`timescale 1ns / 1ps
module dms_uram (
    input clk,
    input we,
    input [11:0] addr,    // Địa chỉ (Max 4096 Orders)
    input [71:0] din,     // Chi tiết Order (Phù hợp độ rộng 72-bit của URAM)
    output reg [71:0] dout
);
    // Attribute ép Vivado dùng URAM
    (* ram_style = "ultra" *) reg [71:0] ram [0:4095]; 
    
    reg [71:0] pipe_reg; // Thanh ghi đường ống stage 1

    always @(posedge clk) begin
        if (we) begin
            ram[addr] <= din;
        end
        // Đọc từ URAM vào Pipeline register
        pipe_reg <= ram[addr]; 
    end

    // Pipeline stage 2 (Đạt chuẩn 2-cycle latency cho URAM)
    always @(posedge clk) begin
        dout <= pipe_reg;
    end
endmodule