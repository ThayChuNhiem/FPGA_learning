`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:   i2c_core_2block
// Architecture:  2-Process FSM (1 Khối Tổ Hợp Next-State + 1 Khối Tuần Tự)
//
// Phân chia kiến trúc:
// 1. KHỐI MẠCH TỔ HỢP (always_comb):
//    - Chuyên xác định trạng thái tiếp theo (next_state) dựa trên state hiện tại và điều kiện.
//    - Đảm bảo gán mặc định `next_state = state;` ở đầu khối để chống Latch 100%.
//
// 2. KHỐI MẠCH TUẦN TỰ (always_ff):
//    - Chốt trạng thái: state <= next_state tại mỗi sườn dương clk.
//    - Điều khiển các thanh ghi dữ liệu nội bộ (tx/rx_shift_reg, bit_cnt).
//    - Điều khiển ngõ ra Open-Drain (scl_drive_low, sda_drive_low) theo từng pha.
//////////////////////////////////////////////////////////////////////////////////

module i2c_core_2block #(
    parameter int CLK_FREQ   = 100_000_000, // Tần số clock hệ thống (Hz) - 100MHz
    parameter int I2C_FREQ   = 100_000,     // Tần số I2C SCL (Hz) - 100kHz
    parameter int FILTER_LEN = 4            // Độ dài bộ lọc chống nhiễu (chu kỳ clk)
)(
    // Clock & Reset
    input  logic        clk,
    input  logic        rst_n,

    // Giao diện điều khiển (User Interface)
    input  logic        cmd_valid,
    output logic        cmd_ready,
    input  logic [6:0]  cmd_addr,
    input  logic        cmd_rw,             // 0: Write, 1: Read
    input  logic [7:0]  cmd_reg_addr,
    input  logic [7:0]  cmd_wr_data,
    
    output logic [7:0]  cmd_rd_data,
    output logic        cmd_rd_valid,
    output logic        cmd_done,
    output logic        ack_err,
    output logic        busy,

    // Chân vật lý I2C (Open-Drain)
    inout  wire         scl,
    inout  wire         sda
);

    //==========================================================================
    // 1. TÍNH TOÁN BỘ TẠO XUNG 4 PHA (4-PHASE TIMING ENGINE)
    //==========================================================================
    // 4 pha (Phase):
    // 2'b00 (Phase 0): SCL=0, Cập nhật dữ liệu SDA (Data Setup)
    // 2'b01 (Phase 1): SCL=1 (Sườn lên), Kiểm tra Clock Stretching
    // 2'b10 (Phase 2): SCL=1 ổn định, Lấy mẫu SDA (Data Sample)
    // 2'b11 (Phase 3): SCL=0 (Sườn xuống), Chuyển bit / trạng thái
    //--------------------------------------------------------------------------
    localparam int CLKS_PER_QUARTER = CLK_FREQ / (I2C_FREQ * 4);
    localparam int Q_WIDTH          = $clog2(CLKS_PER_QUARTER);

    logic [Q_WIDTH-1:0] q_counter;
    logic [1:0]         phase;              // 2'b00: Q0, 2'b01: Q1, 2'b10: Q2, 2'b11: Q3
    logic               q_tick;             // Xung nhịp kết thúc 1/4 chu kỳ SCL

    logic scl_drive_low;
    logic sda_drive_low;
    logic scl_in_clean;
    logic sda_in_clean;

    // Clock Stretching Detection
    logic scl_stretch;
    assign scl_stretch = (!scl_drive_low && !scl_in_clean);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_counter <= '0;
            phase     <= 2'b00;
            q_tick    <= 1'b0;
        end else begin
            q_tick <= 1'b0;
            if (busy) begin
                if (phase == 2'b01 && scl_stretch) begin
                    q_counter <= q_counter; // Tạm dừng đếm khi Slave kéo ghìm SCL
                end else begin
                    if (q_counter == CLKS_PER_QUARTER - 1) begin
                        q_counter <= '0;
                        phase     <= phase + 1'b1;
                        q_tick    <= 1'b1;
                    end else begin
                        q_counter <= q_counter + 1'b1;
                    end
                end
            end else begin
                q_counter <= '0;
                phase     <= 2'b00;
                q_tick    <= 1'b0;
            end
        end
    end

    //==========================================================================
    // 2. CHỐNG METASTABILITY & BỘ LỌC NHIỄU SỐ (GLITCH FILTER)
    //==========================================================================
    logic [1:0]             scl_sync_ff, sda_sync_ff;
    logic [FILTER_LEN-1:0]  scl_filter_sr, sda_filter_sr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sync_ff    <= 2'b11;
            sda_sync_ff    <= 2'b11;
            scl_filter_sr  <= '1;
            sda_filter_sr  <= '1;
            scl_in_clean   <= 1'b1;
            sda_in_clean   <= 1'b1;
        end else begin
            scl_sync_ff <= {scl_sync_ff[0], scl};
            sda_sync_ff <= {sda_sync_ff[0], sda};

            scl_filter_sr <= {scl_filter_sr[FILTER_LEN-2:0], scl_sync_ff[1]};
            sda_filter_sr <= {sda_filter_sr[FILTER_LEN-2:0], sda_sync_ff[1]};

            if (&scl_filter_sr)        scl_in_clean <= 1'b1;
            else if (~|scl_filter_sr)  scl_in_clean <= 1'b0;

            if (&sda_filter_sr)        sda_in_clean <= 1'b1;
            else if (~|sda_filter_sr)  sda_in_clean <= 1'b0;
        end
    end

    // Gán chân vật lý Open-Drain
    assign scl = scl_drive_low ? 1'b0 : 1'bz;
    assign sda = sda_drive_low ? 1'b0 : 1'bz;

    //==========================================================================
    // 3. ĐỊNH NGHĨA TRẠNG THÁI FSM
    //==========================================================================
    typedef enum logic [3:0] {
        ST_IDLE          = 4'd0,  // Chờ lệnh từ người dùng
        ST_START         = 4'd1,  // Tạo điều kiện START
        ST_WR_DEV_ADDR   = 4'd2,  // Gửi 7-bit Slave Addr + 1-bit Write (0)
        ST_ACK_DEV_ADDR  = 4'd3,  // Bắt ACK từ Slave
        ST_WR_REG_ADDR   = 4'd4,  // Gửi 8-bit địa chỉ thanh ghi (Sub-address)
        ST_ACK_REG_ADDR  = 4'd5,  // Bắt ACK từ Slave
        // Nhánh GHI dữ liệu (Master Write)
        ST_WR_DATA       = 4'd6,  // Gửi 8-bit dữ liệu cần ghi
        ST_ACK_WR_DATA   = 4'd7,  // Bắt ACK sau khi ghi
        // Nhánh ĐỌC dữ liệu (Master Read)
        ST_REP_START     = 4'd8,  // Tạo điều kiện Repeated START
        ST_WR_DEV_ADDR_R = 4'd9,  // Gửi lại 7-bit Slave Addr + 1-bit Read (1)
        ST_ACK_DEV_ADDR_R= 4'd10, // Bắt ACK từ Slave
        ST_RD_DATA       = 4'd11, // Nhận 8-bit dữ liệu từ Slave
        ST_SEND_NACK     = 4'd12, // Master gửi NACK (1) để kết thúc đọc
        // Kết thúc & Lỗi
        ST_STOP          = 4'd13, // Tạo điều kiện STOP
        ST_ERR_STOP      = 4'd14  // STOP khẩn cấp khi gặp lỗi NACK
    } state_t;

    state_t state, next_state;

    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [2:0] bit_cnt;
    
    logic [6:0] saved_addr;
    logic       saved_rw;
    logic [7:0] saved_reg_addr;
    logic [7:0] saved_wr_data;

    assign cmd_ready = (state == ST_IDLE);
    assign busy      = (state != ST_IDLE);

    //==========================================================================
    // [KHỐI 1]: MẠCH TỔ HỢP ĐIỀU KHIỂN NEXT_STATE (COMBINATIONAL NEXT-STATE LOGIC)
    //==========================================================================
    always_comb begin
        // Giá trị mặc định: giữ nguyên trạng thái hiện tại (CHỐNG LATCH 100%)
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (cmd_valid) begin
                    next_state = ST_START;
                end
            end

            ST_START: begin
                if (phase == 2'b11 && q_tick) begin
                    next_state = ST_WR_DEV_ADDR;
                end
            end

            ST_WR_DEV_ADDR: begin
                if (phase == 2'b11 && q_tick && (bit_cnt == 3'd0)) begin
                    next_state = ST_ACK_DEV_ADDR;
                end
            end

            ST_ACK_DEV_ADDR: begin
                if (phase == 2'b10 && q_tick && (sda_in_clean != 1'b0)) begin
                    next_state = ST_ERR_STOP;
                end else if (phase == 2'b11 && q_tick) begin
                    next_state = ST_WR_REG_ADDR;
                end
            end

            ST_WR_REG_ADDR: begin
                if (phase == 2'b11 && q_tick && (bit_cnt == 3'd0)) begin
                    next_state = ST_ACK_REG_ADDR;
                end
            end

            ST_ACK_REG_ADDR: begin
                if (phase == 2'b10 && q_tick && (sda_in_clean != 1'b0)) begin
                    next_state = ST_ERR_STOP;
                end else if (phase == 2'b11 && q_tick) begin
                    if (saved_rw == 1'b0)
                        next_state = ST_WR_DATA;
                    else
                        next_state = ST_REP_START;
                end
            end

            ST_WR_DATA: begin
                if (phase == 2'b11 && q_tick && (bit_cnt == 3'd0)) begin
                    next_state = ST_ACK_WR_DATA;
                end
            end

            ST_ACK_WR_DATA: begin
                if (phase == 2'b10 && q_tick && (sda_in_clean != 1'b0)) begin
                    next_state = ST_ERR_STOP;
                end else if (phase == 2'b11 && q_tick) begin
                    next_state = ST_STOP;
                end
            end

            ST_REP_START: begin
                if (phase == 2'b11 && q_tick) begin
                    next_state = ST_WR_DEV_ADDR_R;
                end
            end

            ST_WR_DEV_ADDR_R: begin
                if (phase == 2'b11 && q_tick && (bit_cnt == 3'd0)) begin
                    next_state = ST_ACK_DEV_ADDR_R;
                end
            end

            ST_ACK_DEV_ADDR_R: begin
                if (phase == 2'b10 && q_tick && (sda_in_clean != 1'b0)) begin
                    next_state = ST_ERR_STOP;
                end else if (phase == 2'b11 && q_tick) begin
                    next_state = ST_RD_DATA;
                end
            end

            ST_RD_DATA: begin
                if (phase == 2'b11 && q_tick && (bit_cnt == 3'd0)) begin
                    next_state = ST_SEND_NACK;
                end
            end

            ST_SEND_NACK: begin
                if (phase == 2'b11 && q_tick) begin
                    next_state = ST_STOP;
                end
            end

            ST_STOP: begin
                if (phase == 2'b11 && q_tick) begin
                    next_state = ST_IDLE;
                end
            end

            ST_ERR_STOP: begin
                if (phase == 2'b11 && q_tick) begin
                    next_state = ST_IDLE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end

    //==========================================================================
    // [KHỐI 2]: MẠCH TUẦN TỰ CẬP NHẬT TRẠNG THÁI VÀ DỮ LIỆU (SEQUENTIAL PROCESS)
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            scl_drive_low   <= 1'b0;
            sda_drive_low   <= 1'b0;
            tx_shift_reg    <= '0;
            rx_shift_reg    <= '0;
            bit_cnt         <= '0;
            saved_addr      <= '0;
            saved_rw        <= '0;
            saved_reg_addr  <= '0;
            saved_wr_data   <= '0;
            cmd_rd_data     <= '0;
            cmd_rd_valid    <= 1'b0;
            cmd_done        <= 1'b0;
            ack_err         <= 1'b0;
        end else begin
            state <= next_state;

            cmd_rd_valid <= 1'b0;
            cmd_done     <= 1'b0;

            case (state)
                ST_IDLE: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    ack_err       <= 1'b0;

                    if (cmd_valid) begin
                        saved_addr     <= cmd_addr;
                        saved_rw       <= cmd_rw;
                        saved_reg_addr <= cmd_reg_addr;
                        saved_wr_data  <= cmd_wr_data;
                    end
                end

                ST_START: begin
                    case (phase)
                        2'b00, 2'b01: begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b0; end
                        2'b10:        begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b1; end // START Edge
                        2'b11: begin
                            scl_drive_low <= 1'b1; // Khóa bus bằng SCL=0
                            if (q_tick) begin
                                tx_shift_reg <= {saved_addr, 1'b0};
                                bit_cnt      <= 3'd7;
                            end
                        end
                    endcase
                end

                ST_WR_DEV_ADDR: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= ~tx_shift_reg[7]; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin scl_drive_low <= 1'b0; end
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick) begin
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                if (bit_cnt != 3'd0) bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    endcase
                end

                ST_ACK_DEV_ADDR: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin
                            scl_drive_low <= 1'b0;
                            if (q_tick && (sda_in_clean != 1'b0)) ack_err <= 1'b1;
                        end
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick && !ack_err) begin
                                tx_shift_reg <= saved_reg_addr;
                                bit_cnt      <= 3'd7;
                            end
                        end
                    endcase
                end

                ST_WR_REG_ADDR: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= ~tx_shift_reg[7]; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin scl_drive_low <= 1'b0; end
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick) begin
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                if (bit_cnt != 3'd0) bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    endcase
                end

                ST_ACK_REG_ADDR: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin
                            scl_drive_low <= 1'b0;
                            if (q_tick && (sda_in_clean != 1'b0)) ack_err <= 1'b1;
                        end
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick && !ack_err) begin
                                tx_shift_reg <= saved_wr_data;
                                bit_cnt      <= 3'd7;
                            end
                        end
                    endcase
                end

                ST_WR_DATA: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= ~tx_shift_reg[7]; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin scl_drive_low <= 1'b0; end
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick) begin
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                if (bit_cnt != 3'd0) bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    endcase
                end

                ST_ACK_WR_DATA: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin
                            scl_drive_low <= 1'b0;
                            if (q_tick && (sda_in_clean != 1'b0)) ack_err <= 1'b1;
                        end
                        2'b11: begin scl_drive_low <= 1'b1; end
                    endcase
                end

                ST_REP_START: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01: begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b0; end
                        2'b10: begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b1; end // Sr Edge
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick) begin
                                tx_shift_reg <= {saved_addr, 1'b1};
                                bit_cnt      <= 3'd7;
                            end
                        end
                    endcase
                end

                ST_WR_DEV_ADDR_R: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= ~tx_shift_reg[7]; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin scl_drive_low <= 1'b0; end
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick) begin
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                if (bit_cnt != 3'd0) bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    endcase
                end

                ST_ACK_DEV_ADDR_R: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin
                            scl_drive_low <= 1'b0;
                            if (q_tick && (sda_in_clean != 1'b0)) ack_err <= 1'b1;
                        end
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick && !ack_err) bit_cnt <= 3'd7;
                        end
                    endcase
                end

                ST_RD_DATA: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin
                            scl_drive_low <= 1'b0;
                            if (q_tick) rx_shift_reg <= {rx_shift_reg[6:0], sda_in_clean};
                        end
                        2'b11: begin
                            scl_drive_low <= 1'b1;
                            if (q_tick && (bit_cnt != 3'd0)) bit_cnt <= bit_cnt - 1'b1;
                        end
                    endcase
                end

                ST_SEND_NACK: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01: begin scl_drive_low <= 1'b0; end
                        2'b10: begin
                            scl_drive_low <= 1'b0;
                            if (q_tick) begin
                                cmd_rd_data  <= rx_shift_reg;
                                cmd_rd_valid <= 1'b1;
                            end
                        end
                        2'b11: begin scl_drive_low <= 1'b1; end
                    endcase
                end

                ST_STOP, ST_ERR_STOP: begin
                    case (phase)
                        2'b00: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b1; end
                        2'b01: begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b1; end
                        2'b10: begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b0; end // STOP Edge
                        2'b11: begin
                            scl_drive_low <= 1'b0;
                            sda_drive_low <= 1'b0;
                            if (q_tick) cmd_done <= 1'b1;
                        end
                    endcase
                end

                default: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                end
            endcase
        end
    end

endmodule
