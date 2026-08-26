`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench:     tb_i2c_core
// Description:   Kiểm tra tính đúng đắn của i2c_core qua mô phỏng (Simulation)
//                Tích hợp I2C Slave Model ảo (giả lập chip nhớ EEPROM / Cảm biến)
//////////////////////////////////////////////////////////////////////////////////

module tb_i2c_core;

    // Clock & Reset
    logic clk;
    logic rst_n;

    // Giao diện điều khiển
    logic        cmd_valid;
    logic        cmd_ready;
    logic [6:0]  cmd_addr;
    logic        cmd_rw;
    logic [7:0]  cmd_reg_addr;
    logic [7:0]  cmd_wr_data;
    logic [7:0]  cmd_rd_data;
    logic        cmd_rd_valid;
    logic        cmd_done;
    logic        ack_err;
    logic        busy;

    // Đường dây I2C
    wire scl;
    wire sda;

    // Điện trở kéo lên (Pull-up Resistors mô phỏng ngoài board mạch)
    pullup(scl);
    pullup(sda);

    //--------------------------------------------------------------------------
    // Khởi tạo Device Under Test (DUT)
    // Tăng I2C_FREQ lên 1MHz trong mô phỏng để waveform chạy nhanh hơn
    //--------------------------------------------------------------------------
    i2c_core #(
        .CLK_FREQ   (100_000_000), // 100 MHz
        .I2C_FREQ   (1_000_000),   // 1 MHz (cho mô phỏng nhanh)
        .FILTER_LEN (2)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .cmd_valid   (cmd_valid),
        .cmd_ready   (cmd_ready),
        .cmd_addr    (cmd_addr),
        .cmd_rw      (cmd_rw),
        .cmd_reg_addr(cmd_reg_addr),
        .cmd_wr_data (cmd_wr_data),
        .cmd_rd_data (cmd_rd_data),
        .cmd_rd_valid(cmd_rd_valid),
        .cmd_done    (cmd_done),
        .ack_err     (ack_err),
        .busy        (busy),
        .scl         (scl),
        .sda         (sda)
    );

    // Tạo xung clock 100MHz (Chu kỳ 10ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // MÔ HÌNH I2C SLAVE ẢO (BEHAVIORAL MODEL: Địa chỉ 7'h50)
    // Giả lập một chip nhớ nhỏ (Register Map 256 bytes)
    //--------------------------------------------------------------------------
    localparam [6:0] SLAVE_ADDR = 7'h50;
    logic [7:0] memory [0:255];
    logic [7:0] reg_ptr;
    logic       slave_sda_drive_low;

    assign sda = slave_sda_drive_low ? 1'b0 : 1'bz;

    initial begin
        slave_sda_drive_low = 1'b0;
        // Khởi tạo một số giá trị mặc định trong bộ nhớ
        for (int i = 0; i < 256; i++) memory[i] = 8'h00;
        memory[8'h10] = 8'hA5; // Giá trị ban đầu tại thanh ghi 0x10
    end

    // Tiến trình I2C Slave giả lập
    initial begin
        forever begin
            logic [7:0] shift_in;
            logic [7:0] shift_out;

            slave_sda_drive_low = 1'b0;

            // 1. Chờ START condition (SDA rơi khi SCL cao)
            @(negedge sda);
            if (scl == 1'b1) begin
                // Bắt 8 bit (7-bit Addr + R/W)
                for (int i = 7; i >= 0; i--) begin
                    @(posedge scl);
                    shift_in[i] = sda;
                end

                // Kiểm tra đúng địa chỉ Slave không?
                if (shift_in[7:1] == SLAVE_ADDR) begin
                    // Phát ACK cho Byte địa chỉ (Kéo SDA=0 ở xung clock thứ 9)
                    @(negedge scl);
                    slave_sda_drive_low = 1'b1;
                    @(negedge scl);
                    slave_sda_drive_low = 1'b0;

                    if (shift_in[0] == 1'b0) begin
                        // LỆNH GHI: Nhận Register Address
                        for (int i = 7; i >= 0; i--) begin
                            @(posedge scl);
                            shift_in[i] = sda;
                        end
                        reg_ptr = shift_in;

                        // Phát ACK cho Register Address
                        @(negedge scl);
                        slave_sda_drive_low = 1'b1;
                        @(negedge scl);
                        slave_sda_drive_low = 1'b0;

                        // Chờ xem Master gửi Data ghi tiếp hay phát Repeated START
                        fork
                            begin : wait_write_data
                                for (int i = 7; i >= 0; i--) begin
                                    @(posedge scl);
                                    shift_in[i] = sda;
                                end
                                memory[reg_ptr] = shift_in; // Ghi vào RAM
                                // Phát ACK cho Data
                                @(negedge scl);
                                slave_sda_drive_low = 1'b1;
                                @(negedge scl);
                                slave_sda_drive_low = 1'b0;
                            end
                            begin : wait_rep_start
                                @(negedge sda);
                                if (scl == 1'b1) begin
                                    disable wait_write_data;
                                    // Repeated Start detected
                                end
                            end
                        join_any
                    end else begin
                        // LỆNH ĐỌC: Xuất dữ liệu từ memory[reg_ptr] ra SDA
                        shift_out = memory[reg_ptr];
                        for (int i = 7; i >= 0; i--) begin
                            @(negedge scl);
                            slave_sda_drive_low = ~shift_out[i];
                        end
                        // Nhận NACK từ Master ở xung thứ 9
                        @(posedge scl);
                        @(negedge scl);
                        slave_sda_drive_low = 1'b0; // Thả bus
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // KỊCH BẢN KIỂM THỬ (TEST SEQUENCE)
    //--------------------------------------------------------------------------
    initial begin
        // 1. Reset hệ thống
        rst_n        = 0;
        cmd_valid    = 0;
        cmd_addr     = 0;
        cmd_rw       = 0;
        cmd_reg_addr = 0;
        cmd_wr_data  = 0;

        #100;
        rst_n = 1;
        #100;

        $display("=== [TEST 1] Ghi byte 0x3C vao thanh ghi 0x20 cua Slave 0x50 ===");
        @(posedge clk);
        while (!cmd_ready) @(posedge clk);
        cmd_addr     = 7'h50;
        cmd_rw       = 1'b0; // Ghi
        cmd_reg_addr = 8'h20;
        cmd_wr_data  = 8'h3C;
        cmd_valid    = 1'b1;
        @(posedge clk);
        cmd_valid    = 1'b0;

        // Đợi hoàn thành
        @(posedge cmd_done);
        #50;
        if (!ack_err && memory[8'h20] == 8'h3C) begin
            $display("[TEST 1 PASSED] Ghi thanh cong: memory[0x20] = 0x%02X", memory[8'h20]);
        end else begin
            $display("[TEST 1 FAILED] Ghi that bai! ack_err=%b", ack_err);
        end

        #500;

        $display("=== [TEST 2] Doc lai thanh ghi 0x20 tu Slave 0x50 ===");
        @(posedge clk);
        while (!cmd_ready) @(posedge clk);
        cmd_addr     = 7'h50;
        cmd_rw       = 1'b1; // Đọc
        cmd_reg_addr = 8'h20;
        cmd_valid    = 1'b1;
        @(posedge clk);
        cmd_valid    = 1'b0;

        // Đợi nhận dữ liệu
        @(posedge cmd_rd_valid);
        $display("[TEST 2 DATA] Nhan ve: 0x%02X (Ky vong: 0x3C)", cmd_rd_data);
        @(posedge cmd_done);
        #50;
        if (!ack_err && cmd_rd_data == 8'h3C) begin
            $display("[TEST 2 PASSED] Doc thanh cong!");
        end else begin
            $display("[TEST 2 FAILED] Doc that bai!");
        end

        #500;

        $display("=== [TEST 3] Thu ket noi toi Slave khong ton tai (0x33) -> Phai bao ACK_ERR ===");
        @(posedge clk);
        while (!cmd_ready) @(posedge clk);
        cmd_addr     = 7'h33; // Dia chi khong co thiet bi nao phan hoi
        cmd_rw       = 1'b0;
        cmd_reg_addr = 8'h00;
        cmd_wr_data  = 8'hFF;
        cmd_valid    = 1'b1;
        @(posedge clk);
        cmd_valid    = 1'b0;

        @(posedge cmd_done);
        #50;
        if (ack_err) begin
            $display("[TEST 3 PASSED] Core bat loi NACK chinh xac (ack_err = 1)!");
        end else begin
            $display("[TEST 3 FAILED] Core khong phat hien duoc NACK!");
        end

        #1000;
        $display("=== TAT CA CAC TESTBENCH HOAN TAT ===");
        $finish;
    end

endmodule
