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

    // Tín hiệu điều khiển của Slave ảo
    logic       slave_sda_drive_low;
    assign sda = slave_sda_drive_low ? 1'b0 : 1'bz;

    // Monitor chẩn đoán lỗi
    always @(dut.state) begin
        $display("[DIAG TIME %0t] State changed to %s (%0d)", $time, dut.state.name(), dut.state);
    end

    always @(posedge dut.ack_err) begin
        $display("[DIAG TIME %0t] !!! ACK_ERR TRIGGERED in State %s (%0d) !!! Phase=%b, sda_clean=%b, sda=%b, slave_low=%b",
                 $time, dut.state.name(), dut.state, dut.phase, dut.sda_in_clean, sda, slave_sda_drive_low);
    end

    //--------------------------------------------------------------------------
    // MÔ HÌNH I2C SLAVE ẢO (BEHAVIORAL MODEL: Địa chỉ 7'h50)
    // Giả lập một chip nhớ nhỏ (Register Map 256 bytes)
    //--------------------------------------------------------------------------
    localparam [6:0] SLAVE_ADDR = 7'h50;
    logic [7:0] memory [0:255];
    logic [7:0] reg_ptr;

    initial begin
        slave_sda_drive_low = 1'b0;
        for (int i = 0; i < 256; i++) memory[i] = 8'h00;
        memory[8'h10] = 8'hA5;
    end

    // Tiến trình I2C Slave giả lập
    initial begin
        forever begin
            logic [7:0] shift_in;
            logic [7:0] shift_out;
            bit         is_rep_start;

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
                    // Phát ACK cho Byte địa chỉ
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
                        is_rep_start = 1'b0;
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
                                forever begin
                                    @(negedge sda);
                                    if (scl == 1'b1) begin
                                        is_rep_start = 1'b1;
                                        break;
                                    end
                                end
                            end
                        join_any
                        disable fork; // Dọn dẹp sạch tiến trình còn lại trong fork

                        if (is_rep_start) begin
                            $display("[SLAVE TIME %0t] >>> REPEATED START DETECTED! <<<", $time);
                            // Repeated Start detected -> Bắt tiếp byte địa chỉ đọc
                            for (int i = 7; i >= 0; i--) begin
                                @(posedge scl);
                                shift_in[i] = sda;
                            end
                            $display("[SLAVE TIME %0t] >>> Received Addr: 0x%02X (Expected: 0xA1) <<<", $time, shift_in);
                            if (shift_in[7:1] == SLAVE_ADDR) begin
                                $display("[SLAVE TIME %0t] >>> Address MATCH! Driving ACK <<<", $time);
                                // Phát ACK cho Byte địa chỉ đọc
                                @(negedge scl);
                                slave_sda_drive_low = 1'b1;
                                @(negedge scl);
                                slave_sda_drive_low = 1'b0;

                                if (shift_in[0] == 1'b1) begin
                                    // Xuất dữ liệu từ RAM ra SDA cho Master đọc
                                    shift_out = memory[reg_ptr];
                                    for (int i = 7; i >= 0; i--) begin
                                        slave_sda_drive_low = ~shift_out[i];
                                        @(negedge scl);
                                    end
                                    slave_sda_drive_low = 1'b0; // Thả bus để Master gửi NACK
                                    @(negedge scl);
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // Ghi nhận xung rd_valid
    logic rd_valid_seen;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_valid_seen <= 1'b0;
        else if (cmd_valid) rd_valid_seen <= 1'b0;
        else if (cmd_rd_valid) rd_valid_seen <= 1'b1;
    end

    // Ghi nhận xung ack_err (chốt lại để không bị lỡ khi FSM về IDLE)
    logic ack_err_seen;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) ack_err_seen <= 1'b0;
        else if (cmd_valid) ack_err_seen <= 1'b0;
        else if (ack_err) ack_err_seen <= 1'b1;
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

        // -------------------------------------------------------------
        // TEST 1: Ghi byte 0x3C vào thanh ghi 0x20 của Slave 0x50
        // -------------------------------------------------------------
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

        @(posedge cmd_done);
        #50;
        if (!ack_err_seen && memory[8'h20] == 8'h3C) begin
            $display("[TEST 1 PASSED] Ghi thanh cong: memory[0x20] = 0x%02X", memory[8'h20]);
        end else begin
            $display("[TEST 1 FAILED] Ghi that bai! ack_err=%b, memory[0x20]=0x%02X", ack_err_seen, memory[8'h20]);
        end

        #500;

        // -------------------------------------------------------------
        // TEST 2: Đọc lại thanh ghi 0x20 từ Slave 0x50 (Repeated START)
        // -------------------------------------------------------------
        $display("=== [TEST 2] Doc lai thanh ghi 0x20 tu Slave 0x50 ===");
        @(posedge clk);
        while (!cmd_ready) @(posedge clk);
        cmd_addr     = 7'h50;
        cmd_rw       = 1'b1; // Đọc
        cmd_reg_addr = 8'h20;
        cmd_valid    = 1'b1;
        @(posedge clk);
        cmd_valid    = 1'b0;

        // Chờ cmd_done
        fork
            begin
                @(posedge cmd_done);
            end
            begin
                #100_000;
                $display("[TEST 2 TIMEOUT] Het thoi gian cho!");
            end
        join_any
        disable fork;

        #50;
        if (!ack_err_seen && rd_valid_seen && (cmd_rd_data == 8'h3C)) begin
            $display("[TEST 2 PASSED] Doc thanh cong! Nhan ve: 0x%02X", cmd_rd_data);
        end else begin
            $display("[TEST 2 FAILED] Doc that bai! ack_err=%b, rd_valid=%b, cmd_rd_data=0x%02X", 
                     ack_err_seen, rd_valid_seen, cmd_rd_data);
        end

        #500;

        // -------------------------------------------------------------
        // TEST 3: Thử kết nối tới Slave không tồn tại (0x33) -> Bắt lỗi NACK
        // -------------------------------------------------------------
        $display("=== [TEST 3] Thu ket noi toi Slave khong ton tai (0x33) -> Phai bao ACK_ERR ===");
        @(posedge clk);
        while (!cmd_ready) @(posedge clk);
        cmd_addr     = 7'h33; // Địa chỉ không tồn tại
        cmd_rw       = 1'b0;
        cmd_reg_addr = 8'h00;
        cmd_wr_data  = 8'hFF;
        cmd_valid    = 1'b1;
        @(posedge clk);
        cmd_valid    = 1'b0;

        @(posedge cmd_done);
        #50;
        if (ack_err || ack_err_seen) begin
            $display("[TEST 3 PASSED] Core bat loi NACK chinh xac (ack_err = 1)!");
        end else begin
            $display("[TEST 3 FAILED] Core khong phat hien duoc NACK! ack_err=%b", ack_err);
        end

        #1000;
        $display("=== TAT CA CAC TESTBENCH HOAN TAT ===");
        $finish;
    end

endmodule
