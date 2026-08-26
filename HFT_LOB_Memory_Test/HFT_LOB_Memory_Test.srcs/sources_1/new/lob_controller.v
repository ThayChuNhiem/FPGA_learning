`timescale 1ns / 1ps
module lob_controller (
    input clk,
    input reset,
    input valid_in,
    input [9:0] price_in,
    input [71:0] order_info_in,
    output wire [15:0] head_ptr_out,
    output wire [71:0] order_read_out
);

    // Dùng 1 cycle đầu tiên để ghi, cycle sau để đọc kiểm chứng
    reg we_bram, we_uram;
    
    always @(posedge clk) begin
        if (reset) begin
            we_bram <= 0;
            we_uram <= 0;
        end else begin
            we_bram <= valid_in;
            we_uram <= valid_in;
        end
    end

    fis_bram bram_inst (
        .clk(clk),
        .we(we_bram),
        .addr(price_in),
        .din(16'hABCD), // Ghi thử 1 con trỏ giả lập
        .dout(head_ptr_out)
    );

    dms_uram uram_inst (
        .clk(clk),
        .we(we_uram),
        .addr(12'h123), // Địa chỉ cấp phát tĩnh để test
        .din(order_info_in),
        .dout(order_read_out)
    );
endmodule