`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/18/2026 04:57:31 PM
// Design Name: 
// Module Name: tb_uart_core
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


module tb_uart_core;

    // Parameters
    localparam int CLK_FREQ    = 100_000_000; // 100 MHz
    localparam int BAUD_RATE   = 115200;      // 115200 bps
    localparam time CLK_PERIOD = 10ns;        // 100 MHz clock period

    // DUT Signals
    logic       clk;
    logic       rst_n;

    // TX Interface
    logic [7:0] tx_data;
    logic       tx_start;
    logic       tx_busy;
    logic       tx_pin;

    // RX Interface
    logic       rx_pin;
    logic [7:0] rx_data;
    logic       rx_valid;

    // -------------------------------------------------------------------------
    // Instantiate DUT (Device Under Test)
    // -------------------------------------------------------------------------
    uart_core #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy),
        .tx_pin(tx_pin),
        .rx_pin(rx_pin),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    // -------------------------------------------------------------------------
    // Loopback: Nối trực tiếp dây tx_pin vòng lại rx_pin
    // -------------------------------------------------------------------------
    assign rx_pin = tx_pin;

    // Clock Generator (100 MHz)
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("=== START UART LOOPBACK TESTBENCH ===");
        
        // 1. Khởi tạo & Reset hệ thống
        rst_n    <= 1'b0;
        tx_start <= 1'b0;
        tx_data  <= 8'h00;
        repeat (10) @(posedge clk);
        rst_n    <= 1'b1;
        repeat (10) @(posedge clk);

        // 2. Phát ký tự 'A' (0x41) qua TX
        $display("[Time %0t ns] Sending byte 0x41 ('A')...", $time);
        @(posedge clk);
        tx_data  <= 8'h41; // Ký tự 'A'
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;

        // 3. Đợi và kiểm tra tín hiệu phản hồi tại RX
        @(posedge rx_valid);
        
        // Kiểm tra điều kiện nghiệm thu tại thời điểm rx_valid == 1
        if (rx_valid === 1'b1 && rx_data === 8'h41) begin
            $display("==================================================");
            $display("[Time %0t ns] -> TEST PASSED!", $time);
            $display("-> Condition Met: rx_valid = 1, rx_data = 0x%02X ('%c')", rx_data, rx_data);
            $display("==================================================");
        end else begin
            $display("==================================================");
            $error("[Time %0t ns] -> TEST FAILED! Expected: 0x41 ('A'), Received: 0x%02X", $time, rx_data);
            $display("==================================================");
        end

        // 4. Chờ TX kết thúc hoàn toàn rồi dừng mô phỏng
        wait (!tx_busy);
        repeat (50) @(posedge clk);
        
        $display("=== TEST COMPLETED ===");
        $finish;
    end

endmodule