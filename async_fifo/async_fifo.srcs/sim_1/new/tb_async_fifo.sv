`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/19/2026 03:24:00 PM
// Design Name: 
// Module Name: tb_async_fifo
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



module tb_async_fifo;

    // -------------------------------------------------------------
    // 1. Tham số và Tín hiệu kết nối
    // -------------------------------------------------------------
    localparam int DATA_WIDTH    = 32;
    localparam int FIFO_DEPTH    = 1024;
    localparam int TOTAL_ITEMS   = 10000;

    localparam int WR_CLK_PERIOD = 10; // 100 MHz
    localparam int RD_CLK_PERIOD = 25; // 40 MHz

    // Write Interface
    logic                  wr_clk;
    logic                  wr_rst_n;
    logic                  wr_en;
    logic [DATA_WIDTH-1:0] din;
    logic                  full;

    // Read Interface
    logic                  rd_clk;
    logic                  rd_rst_n;
    logic                  rd_en;
    logic [DATA_WIDTH-1:0] dout;
    logic                  empty;

    // Thống kê nghiệm thu
    int items_written = 0;
    int items_read    = 0;
    int error_count   = 0;

    // -------------------------------------------------------------
    // 2. Khởi tạo DUT
    // -------------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .din      (din),
        .full     (full),
        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .dout     (dout),
        .empty    (empty)
    );

    // -------------------------------------------------------------
    // 3. Xung Clock bất đồng bộ
    // -------------------------------------------------------------
    initial begin
        wr_clk = 0;
        forever #(WR_CLK_PERIOD / 2.0) wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 0;
        forever #(RD_CLK_PERIOD / 2.0) rd_clk = ~rd_clk;
    end

    // -------------------------------------------------------------
    // 4. Kịch bản nghiệm thu 10,000 số
    // -------------------------------------------------------------
    initial begin
        $display("================================================================");
        $display("   BAT DAU TEST NGHIEM THU ASYNC FIFO: BOM 10,000 SO LIEN TUC   ");
        $display("   wr_clk = 100MHz (10ns)  |  rd_clk = 40MHz (25ns)             ");
        $display("================================================================");

        // Reset hệ thống
        wr_rst_n <= 1'b0;
        rd_rst_n <= 1'b0;
        wr_en    <= 1'b0;
        rd_en    <= 1'b0;
        din      <= '0;

        #(WR_CLK_PERIOD * 5);
        @(negedge wr_clk) wr_rst_n <= 1'b1;
        @(negedge rd_clk) rd_rst_n <= 1'b1;
        #(RD_CLK_PERIOD * 2);
        $display("[INFO] He thong da Reset. Bat dau truyen nhan...");

        fork
            // ---------------------------------------------------------
            // Producer Thread: Bơm liên tục từ 0 -> 9999
            // ---------------------------------------------------------
            begin : writer_thread
                while (items_written < TOTAL_ITEMS) begin
                    @(negedge wr_clk);
                    if (!full) begin
                        wr_en <= 1'b1;
                        din   <= items_written;
                        items_written++;
                    end else begin
                        wr_en <= 1'b0;
                    end
                end
                @(negedge wr_clk);
                wr_en <= 1'b0;
                $display("[INFO] Producer: Da bom du %0d so vao FIFO.", items_written);
            end

            // ---------------------------------------------------------
            // Consumer Thread: Đọc và xác thực (Căn chuẩn 1 nhịp trễ BRAM)
            // ---------------------------------------------------------
            begin : reader_thread
                automatic logic [DATA_WIDTH-1:0] expected_val = 0;

                while (items_read < TOTAL_ITEMS) begin
                    @(negedge rd_clk);
                    if (!empty) begin
                        rd_en <= 1'b1;
                        
                        // Chờ cạnh lên để kích hoạt đọc BRAM
                        @(posedge rd_clk);
                        #1; // Đợi 1ps sau cạnh lên để dout cập nhật xong
                        rd_en <= 1'b0;

                        // So sánh dữ liệu thực tế với kỳ vọng
                        if (dout !== expected_val) begin
                            $display("[ERROR] Data Corruption! Nhan: %0d | Ky vong: %0d (Time: %0t)", dout, expected_val, $time);
                            error_count++;
                        end

                        expected_val++;
                        items_read++;

                        if (items_read % 2000 == 0) begin
                            $display("[PROGRESS] Da doc va xac thuc thanh cong %0d / %0d so...", items_read, TOTAL_ITEMS);
                        end
                    end else begin
                        rd_en <= 1'b0;
                    end
                end
                $display("[INFO] Consumer: Da doc va xac thuc du %0d so.", items_read);
            end
        join

        #(RD_CLK_PERIOD * 10);

        // -------------------------------------------------------------
        // 5. Tổng kết nghiệm thu
        // -------------------------------------------------------------
        $display("================================================================");
        $display("                 TONG KET TEST NGHIEM THU                       ");
        $display("================================================================");
        $display("Tong so phan tu da bom vao : %0d", items_written);
        $display("Tong so phan tu da doc ra  : %0d", items_read);
        $display("Tong so loi phat hien      : %0d", error_count);
        $display("Trang thai co Empty cuoi   : %b (Ky vong: 1)", empty);
        $display("Trang thai co Full cuoi    : %b (Ky vong: 0)", full);

        if ((error_count == 0) && (items_read == TOTAL_ITEMS) && empty) begin
            $display("\n>>> [PASSED] DATCHUAN NGHIEM THU: KHONG MAT, KHONG TRUNG LAP SO NAO! <<<");
        end else begin
            $display("\n>>> [FAILED] KHONG DAT TIEU CHI NGHIEM THU! <<<");
        end
        $display("================================================================");
        $finish;
    end

endmodule