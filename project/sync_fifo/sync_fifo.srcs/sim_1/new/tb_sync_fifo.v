`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/19/2026 01:31:47 PM
// Design Name: 
// Module Name: tb_sync_fifo
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

module tb_sync_fifo;

    // -------------------------------------------------------------
    // 1. Tham số và Tín hiệu kết nối
    // -------------------------------------------------------------
    localparam int DATA_WIDTH = 32;
    localparam int FIFO_DEPTH = 1024;
    localparam int CLK_PERIOD = 10; // 100 MHz clock

    logic                  clk;
    logic                  rst_n;
    logic                  wr_en;
    logic [DATA_WIDTH-1:0] din;
    logic                  full;
    logic                  rd_en;
    logic [DATA_WIDTH-1:0] dout;
    logic                  empty;
    logic [$clog2(FIFO_DEPTH):0] data_count;

    // Mô hình hàng đợi tham chiếu (Golden Reference Queue) để tự đối chiếu dữ liệu
    logic [DATA_WIDTH-1:0] golden_queue[$];
    int error_count = 0;

    // -------------------------------------------------------------
    // 2. Khởi tạo DUT (Device Under Test)
    // -------------------------------------------------------------
    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_en      (wr_en),
        .din        (din),
        .full       (full),
        .rd_en      (rd_en),
        .dout       (dout),
        .empty      (empty),
        .data_count (data_count)
    );

    // -------------------------------------------------------------
    // 3. Tạo xung Clock
    // -------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // -------------------------------------------------------------
    // 4. Các Tasks hỗ trợ điều khiển
    // -------------------------------------------------------------
    // Task Reset hệ thống
    task automatic reset_dut();
        rst_n <= 1'b0;
        wr_en <= 1'b0;
        rd_en <= 1'b0;
        din   <= '0;
        golden_queue.delete();
        #(CLK_PERIOD * 3);
        @(negedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
        $display("[INFO] Reset hoan tat.");
    endtask

    // Task Ghi 1 phần tử
    task automatic write_data(input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        wr_en <= 1'b1;
        din   <= data;
        if (!full) begin
            golden_queue.push_back(data);
        end
        @(posedge clk);
        #1;
        wr_en <= 1'b0;
    endtask

    // Task Đọc 1 phần tử và kiểm tra dữ liệu
    task automatic read_and_check();
        logic [DATA_WIDTH-1:0] expected_data;
        @(negedge clk);
        if (!empty) begin
            expected_data = golden_queue.pop_front();
            rd_en <= 1'b1;
            @(posedge clk);
            #1; // Đợi sau cạnh lên để BRAM cập nhật dout (1 clk latency)
            rd_en <= 1'b0;
            
            if (dout !== expected_data) begin
                $display("[ERROR] Data mismatch! Thuc te: 0x%08X | Ky vong: 0x%08X (Time: %0t)", dout, expected_data, $time);
                error_count++;
            end
        end else begin
            rd_en <= 1'b1;
            @(posedge clk);
            #1;
            rd_en <= 1'b0;
        end
    endtask

    // -------------------------------------------------------------
    // 5. Kịch bản kiểm thử chính (Test Sequence)
    // -------------------------------------------------------------
    initial begin
        $display("==================================================");
        $display("         BAT DAU KIEM THU SYNC FIFO               ");
        $display("==================================================");

        // Kịch bản 1: Reset ban đầu
        reset_dut();
        assert(empty == 1'b1 && full == 1'b0 && data_count == 0)
            else begin $display("[ERROR] Loi co sau Reset!"); error_count++; end

        // Kịch bản 2: Ghi liên tục 1024 phần tử (Fill FIFO)
        $display("[TEST 1] Ghi day FIFO (1024 phan tu)...");
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            write_data($urandom());
        end
        
        #1;
        assert(full == 1'b1 && empty == 1'b0 && data_count == FIFO_DEPTH)
            $display("[PASS] FIFO da day chinh xac. full = 1, data_count = %0d", data_count);
        else begin
            $display("[ERROR] Co FULL khong bat dung! full = %b, count = %0d", full, data_count);
            error_count++;
        end

        // Kịch bản 3: Thử ghi tràn khi đang Full
        $display("[TEST 2] Kiem tra chong ghi tran khi dang FULL...");
        write_data(32'hDEAD_BEEF);
        #1;
        assert(data_count == FIFO_DEPTH && full == 1'b1)
            $display("[PASS] Chuc nang chong ghi tran hoat dong tot.");
        else begin
            $display("[ERROR] Ghi tran khong hop le!");
            error_count++;
        end

        // Kịch bản 4: Đọc toàn bộ ra (Drain FIFO)
        $display("[TEST 3] Doc toan bo 1024 phan tu ra va doi chieu...");
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            read_and_check();
        end

        #1;
        assert(empty == 1'b1 && full == 1'b0 && data_count == 0)
            $display("[PASS] FIFO da rong hoan toan. empty = 1, data_count = 0");
        else begin
            $display("[ERROR] Co EMPTY khong bat dung! empty = %b, count = %0d", empty, data_count);
            error_count++;
        end

        // Kịch bản 5: Ghi và Đọc đồng thời (Simultaneous Write & Read)
        $display("[TEST 4] Kiem tra Ghi & Doc dong thoi (500 chu ky)...");
        // Nạp trước 10 phần tử
        for (int i = 0; i < 10; i++) write_data($urandom());

        for (int i = 0; i < 500; i++) begin
            logic [DATA_WIDTH-1:0] test_val = $urandom();
            logic [DATA_WIDTH-1:0] exp_val;
            
            @(negedge clk);
            wr_en <= 1'b1;
            din   <= test_val;
            rd_en <= 1'b1;
            golden_queue.push_back(test_val);
            exp_val = golden_queue.pop_front();

            @(posedge clk);
            #1;
            wr_en <= 1'b0;
            rd_en <= 1'b0;

            if (dout !== exp_val) begin
                $display("[ERROR] Mismatch khi doc/ghi dong thoi! Thuc te: 0x%08X | Ky vong: 0x%08X", dout, exp_val);
                error_count++;
            end
        end

        // Xả nốt các phần tử còn lại
        while (golden_queue.size() > 0) begin
            read_and_check();
        end

        // ---------------------------------------------------------
        // 6. Tổng kết kết quả
        // ---------------------------------------------------------
        $display("==================================================");
        if (error_count == 0) begin
            $display(">>> ALL TESTS PASSED! KHONG CO LOI NAO. <<<");
        end else begin
            $display(">>> TEST THAT BAI VOI %0d LOI! <<<", error_count);
        end
        $display("==================================================");
        $finish;
    end

endmodule
