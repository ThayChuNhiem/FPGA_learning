`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:   i2c_core
// Description:   Khung mẫu rỗng để bạn tự thực hành viết I2C Core từ đầu
//
// Hướng dẫn gợi ý các bước tự viết:
// 1. Tính toán bộ chia tần (CLKS_PER_QUARTER) và bộ đếm pha (phase: 0, 1, 2, 3).
// 2. Viết bộ đồng bộ 2-stage FF và bộ lọc nhiễu Glitch Filter cho SCL/SDA ngõ vào.
// 3. Gán ngõ ra Open-Drain: assign scl = ... ; assign sda = ... ;
// 4. Định nghĩa các trạng thái FSM (typedef enum).
// 5. Viết FSM điều khiển luồng (chọn phong cách 1 khối hoặc 2 khối tùy bạn).
//////////////////////////////////////////////////////////////////////////////////

module i2c_core #(
    parameter int CLK_FREQ   = 100_000_000, // Tần số clock hệ thống (Hz)
    parameter int I2C_FREQ   = 100_000,     // Tần số I2C SCL (Hz)
    parameter int FILTER_LEN = 4            // Độ dài bộ lọc chống nhiễu ngõ vào
)(
    // Clock & Reset
    input  logic        clk,
    input  logic        rst_n,

    // Giao diện điều khiển (User Interface)
    input  logic        cmd_valid,
    output logic        cmd_ready,
    input  logic [6:0]  cmd_addr,
    input  logic        cmd_rw,             // 0: GHI (Write), 1: ĐỌC (Read)
    input  logic [7:0]  cmd_reg_addr,       // Địa chỉ thanh ghi (Sub-address)
    input  logic [7:0]  cmd_wr_data,        // Dữ liệu ghi
    
    output logic [7:0]  cmd_rd_data,        // Dữ liệu đọc về
    output logic        cmd_rd_valid,       // Xung báo đọc dữ liệu hợp lệ
    output logic        cmd_done,           // Xung báo hoàn thành giao dịch
    output logic        ack_err,            // Cờ báo lỗi NACK
    output logic        busy,               // Báo module đang bận

    // Chân vật lý I2C (Open-Drain)
    inout  wire         scl,
    inout  wire         sda
);

    // =========================================================================
    // TODO 1: Tính toán tham số timing và bộ chia xung 4 pha
    // =========================================================================

    /*
    chia 1 chu ki cua i2c lam 4 phase : 
        phase 0 : scl = 0, update du lieu len sda
        phase 1 : scl = 1, sda giu nguyen gia tri, can kiem tra clock stretching
        phase 2 : scl = 1, lay gia tri tu sda
        phase 3 : scl = 0, chuyen state
    */
    localparam CLKS_PER_PHASE = CLK_FREQ / (I2C_FREQ * 4);  // so clk moi phase
    localparam COUNTER_WIDTH  = $clog2(CLKS_PER_PHASE);     //so bit can de dem clk
    
    logic [COUNTER_WIDTH - 1 : 0]   counter;        //dem clk cho tung phase
    logic [1:0]                     phase;          //gan gia tri tung phase
    logic                           phase_tick;     //phase tick de bao da het phase
    
    logic   sda_drive_low;     //dieu khien sda
    logic   scl_drive_low;     //dieu khien scl
    logic   sda_in_clean;      //nhan tin hieu sda
    logic   scl_in_clean;      //nhan tin hieu scl
    
    logic clk_stretch;         //stretch khi master muon scl = 0 nhung slave giu scl = 1
    assign clk_stretch = (!scl_drive_low & !scl_in_clean);
    
    //bo dem counter
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n | !busy) begin
            counter     <=  '0;
            phase       <=  '0;
            phase_tick  <=  1'b0;
        end else begin
            if(busy) begin
                if(phase == 2'b01 && clk_stretch) begin
                    counter <= counter; //stretch thi counter giu nguyen
                end else begin
                    if(counter == (CLKS_PER_PHASE - 1)) begin
                        counter     <= '0;
                        phase_tick  <= 1'b1;
                        phase       <= phase + 1'b1;  
                    end
                end
            end
        end
    end 



    // =========================================================================
    // TODO 2: Khử Metastability (2-stage FF) và bộ lọc số Glitch Filter
    // =========================================================================

    logic [1:0]                 scl_sync_ff, sda_sync_ff; //di qua ff de on dinh
    logic [FILTER_LEN -1 :0]    scl_filter, sda_filter;   //chi khi giu nguyen gia tri trong filter_len chu ki thi moi duoc nhan
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            //khi reset thi tat ca la 1
            scl_sync_ff     <= '1;
            sda_sync_ff     <= '1;
            scl_filter      <= '1;
            sda_filter      <= '1;
            sda_in_clean    <= '1;
            scl_in_clean    <= '1; 
        end else begin
            //loc qua ff
            scl_sync_ff     <= {scl_sync_ff[0], scl};
            sda_sync_ff     <= {sda_sync_ff[0], sda};
            //luu lai gia tri trong filter_len chu ki
            scl_filter      <= {scl_filter[FILTER_LEN - 2 : 0], scl_sync_ff[1]};
            sda_filter      <= {sda_filter[FILTER_LEN - 2 : 0], sda_sync_ff[1]};
            //neu hop le thi cho ra _in_clean
            if(&scl_filter)         scl_in_clean <= 1'b1;
            else if(~|scl_filter)   scl_in_clean <= 1'b0;
            
            if(&sda_filter)         sda_in_clean <= 1'b1;
            else if(~|sda_filter)   sda_in_clean <= 1'b0; 
            
        end
    end

    //==========================================================================
    // TODO 3: ĐỊNH NGHĨA TRẠNG THÁI FSM
    //==========================================================================
    
    typedef enum logic [3:0] {
        ST_IDLE         = 4'd0,     //trang thai nghi
        ST_START        = 4'd1,     //trang nhan tin hieu dau vao
        ST_WR_DEV_ADD   = 4'd2,     //gui di vi tri cua thiet bi va wr(0)
        ST_ACK_DEV_ADD  = 4'd3,     //nhan ack xem thiet bi da xac nhan chua
        ST_WR_REG_ADD   = 4'd4,     //gui di vi tri thanh ghi cua thiet bi
        ST_ACK_REG_ADD  = 4'd5,     //nhan ack xem vi tri thanh ghi do co hop le khong
        
        //phan ghi
        ST_WR_DATA      = 4'd6,     //gui di data
        ST_ACK_WR_DATA  = 4'd7,     //nhan ack xem slave da nhan duoc chua
        
        //phan doc
        ST_REP_START    = 4'd8,     //tao lai tin hieu start
        ST_WR_DEV_ADD_R = 4'd9,     //gui lai vi tri thiet bi 1 lan nua cung read(1)
        ST_ACK_DEV_ADD_R= 4'd10,    //nhan ack
        ST_READ_DATA    = 4'd11,    //doc data
        ST_READ_NACK    = 4'd12,    //gui tin hieu da doc xong
        
        //phan stop va error
        ST_STOP         = 4'd13,    //da hoan thanh
        ST_ERR          =4'd14      //bi loi
    } state_t;
    
    state_t state;
    
    logic [7:0]     tx_shift_data;      //du lieu can truyen
    logic [7:0]     rx_shift_data;      //du lieu nhan duoc
    logic [2:0]     bit_cnt;            //dem index
    
    logic [6:0]     saved_addr;         //luu lai dia chi thiet bi
    logic           saved_rw;           //luu lai xem la write hay read
    logic [7:0]     saved_reg_addr;     //luu lai dia chi thanh ghi
    logic [7:0]     saved_wr_data;      //luu tru data de gui di trong thoi gian kha dai
    
    
    assign cmd_ready = (state == ST_IDLE);
    assign busy      = (state != ST_IDLE);
    
    
    //==========================================================================
    // [KHỐI DUY NHẤT]: TIẾN TRÌNH TUẦN TỰ (1-PROCESS FSM)
    //==========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state               <= ST_IDLE;
            sda_drive_low       <= 1'b0;    //reset thi ca scl va sda deu la 1
            scl_drive_low       <= 1'b0;
            tx_shift_data       <= '0;
            rx_shift_data       <= '0;
            bit_cnt                 <= '0;
            saved_addr          <= '0;
            saved_rw            <= 1'b0;
            saved_reg_addr      <= '0;
            saved_wr_data       <= '0;
            cmd_rd_data         <= '0;
            cmd_rd_valid        <= 1'b0;
            cmd_done            <= 1'b0;
            ack_err             <= 1'b0;
        end else begin 
            cmd_rd_valid        <= 1'b0;
            cmd_done            <= 1'b0;
            
            //xu li FSM
            case(phase)
                //IDLE
                ST_IDLE : begin
                    sda_drive_low   <= 1'b0;
                    scl_drive_low   <= 1'b0;
                    ack_err         <= 1'b0;
                    //nhan tin hieu valid se chup lai du lieu va chuyen sang start
                    if(cmd_valid) begin
                        saved_addr          <= cmd_addr;
                        saved_rw            <= cmd_rw;
                        saved_reg_addr      <= cmd_reg_addr;
                        saved_wr_data       <= cmd_wr_data;
                        state               <= ST_START;
                    end
                end
                
                
                //START
                ST_START : begin
                    //tao xung clock : phase 1,2 : sda va scl =1
                                     //phase 3 : scl =1 va sda = 0 : tin hieu start
                                     //phase 4 : scl = 0 va cho du lieu vao tx_shift_data voi bit 0 (write), can gan them ca cnt 
                    case(phase)
                        2'b00, 2'b01 : begin
                            scl_drive_low <= 1'b0;
                            sda_drive_low <= 1'b0;
                        end
                        
                        2'b10 : sda_drive_low <= 1'b1;
                        
                        2'b11 : begin
                            scl_drive_low   <= 1'b1;
                            bit_cnt         <= 3'd7;
                            tx_shift_data   <= {saved_addr, 1'b0};
                            state           <= ST_WR_DEV_ADD;        
                        end
                    endcase
                end
                
                //ST_WR_DEV_ADD gui di dia chi cua thiet bi
                ST_WR_DEV_ADD : begin
                    case(phase)
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= ~ tx_shift_data[7]; end
                        2'b01 : scl_drive_low   <= 1'b0;
                        2'b10 : scl_drive_low   <= 1'b0;
                        2'b11 : begin
                            scl_drive_low       <= 1'b1;
                            if(phase_tick) begin
                                tx_shift_data   <= {tx_shift_data[6:0], 1'b0};
                                if(bit_cnt == 0) state <= ST_ACK_DEV_ADD;
                                else bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    endcase
                end
                
                //ST_ACK_DEV_ADD cho tin hieu ack de xem phan hoi cua slave sau khi gui dia chi cua thiet bi
                ST_ACK_DEV_ADD : begin
                    case(phase)
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01 : scl_drive_low <= 1'b0;
                        2'b10 : begin
                            scl_drive_low       <= 1'b0;
                            if(phase_tick & sda_in_clean != 1'b0) begin
                                ack_err <= 1'b1;
                                state   <= ST_ERR;
                            end
                        end
                        2'b11 : begin
                            scl_drive_low   <= 1'b1;
                            tx_shift_data   <= saved_reg_addr;
                            bit_cnt         <= 3'd7;
                            state           <= ST_WR_REG_ADD;
                        end
                    endcase
                end
                
                //ST_WR_REG_ADD gui di dia chi cua thanh ghi
                ST_WR_REG_ADD : begin
                    case(phase)
                        2'b00 : begin scl_drive_low <= 2'b1; sda_drive_low <= ~ tx_shift_data[7]; end
                        2'b01, 2'b10 : scl_drive_low   <= 2'b0;
                        2'b11 : begin
                                scl_drive_low <= 2'b0;
                                if(phase_tick) begin
                                    tx_shift_data <= {tx_shift_data[6:0], 1'b0};
                                    if(bit_cnt == 0 ) state <= ST_ACK_REG_ADD;
                                    else bit_cnt <= bit_cnt - 1'b1;
                                end
                        end
                    endcase
                end
                
                //ST_ACK_REG_ADD nhan ve ack xem slave da nhan ve dia chi reg chua
                ST_ACK_REG_ADD : begin
                    case(phase) 
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01 : scl_drive_low <= 1'b1;
                        2'b10 : begin
                            scl_drive_low <= 1'b0;
                            if(phase_tick & sda_in_clean != 1'b0) begin
                                ack_err <= 1'b1;
                                state   <= ST_ERR;
                            end
                        end
                        2'b11 : begin
                            scl_drive_low <= 1'b1;
                            // kiem tra cmd_rw neu = 1 thi la read, 0 la write
                            if(!cmd_rw) begin state <= ST_WR_DATA; tx_shift_data <= saved_wr_data; end
                            else state <= ST_REP_START;
                        end
                    endcase
                end
                
                //viet chi write truoc
                //ST_WR_DATA gui data cho slave
                ST_WR_DATA : begin
                    case(phase)
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= ~ tx_shift_data[7]; end
                        2'b01, 2'b10 : scl_drive_low <= 1'b0;
                        2'b11 : begin
                            scl_drive_low <= 1'b1;
                            if(phase_tick) begin
                                tx_shift_data <= {tx_shift_data[6:0], 1'b0};
                                if(bit_cnt == 0) state <= ST_ACK_WR_DATA;
                                else bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    endcase
                end
                //ST_ACK_WR_DATA nhan ack tu slave
                ST_ACK_WR_DATA : begin
                    case(phase) 
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01 : scl_drive_low <= 1'b0;
                        2'b10 : begin
                            scl_drive_low   <= 1'b0;
                            if(phase_tick & sda_in_clean != 1'b0) begin
                                ack_err <= 1'b1;
                                state   <= ST_ERR;
                            end 
                        end
                        2'b11 : begin
                            scl_drive_low <= 1'b1;
                            state         <= ST_STOP;
                        end
                    endcase
                end
                
                //phan Read
                //ST_REP_START
                ST_REP_START : begin
                    case(phase) 
                        2'b00, 2'b01 : begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b0; end
                        2'b10 : sda_drive_low <= 1'b1;
                        2'b11 : begin
                            scl_drive_low       <= 1'b1;
                            bit_cnt             <= 3'd7;
                            tx_shift_data       <= {saved_addr, 1'b1}; //bit 1 la de thong bao read
                            state               <= ST_WR_DEV_ADD_R;
                        end
                    endcase
                end
                
                //ST_WR_DEV_ADD_R gui lai dia chi can doc 
                ST_WR_DEV_ADD_R : begin
                    case(phase) 
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= tx_shift_data[7]; end
                        2'b01, 2'b10 : scl_drive_low <= 1'b0;
                        2'b11 : begin
                            scl_drive_low   <= 1'b1;
                            if(phase_tick) begin
                                tx_shift_data   <= {tx_shift_data[6:0], 1'b0};
                                if(bit_cnt == 0) state <=  ST_ACK_DEV_ADD_R;
                                else bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    endcase
                end
                
                //nhan ack sau khi gui lai dia chi slave
                ST_ACK_DEV_ADD_R : begin
                    case(phase)
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b1; end
                        2'b01 : scl_drive_low   <= 1'b0;
                        2'b10 : begin
                            scl_drive_low <= 1'b0;
                            if(phase_tick & sda_in_clean != 0) begin
                                ack_err <= 1'b1;
                                state   <= ST_ERR;
                            end
                        end
                        2'b11 : begin
                            scl_drive_low   <= 1'b1;
                            bit_cnt         <= 3'd7;
                            state           <= ST_READ_DATA;
                        end
                    endcase
                end
                
                //ST_READ_DATA doc du lieu duoc gui tu slave
                ST_READ_DATA : begin
                    case(phase)
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01 : scl_drive_low <= 1'b0;
                        2'b10 : begin
                            scl_drive_low   <= 1'b0;
                            if(phase_tick) rx_shift_data   <= {rx_shift_data[6:0], sda_in_clean}; 
                        end
                        2'b11 : begin
                            scl_drive_low <= 1'b1;
                            if(phase_tick) begin
                                if(bit_cnt == 0) state <= ST_READ_NACK;
                                else bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    endcase
                end
                
                //ST_READ_NACK doc xong thi gui lai ack cho slave
                ST_READ_NACK : begin
                    case(phase)
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; end
                        2'b01 : scl_drive_low <= 1'b0;
                        2'b10 :begin
                            scl_drive_low <= 1'b0;
                            if(phase_tick) begin
                                cmd_rd_data <= rx_shift_data;
                                cmd_rd_valid   <= 1'b1;
                            end
                        end
                        2'b11 : begin
                            scl_drive_low   <= 1'b1; 
                            state           <= ST_STOP;
                        end
                    endcase
                end
                
                //ST_ERR va ST_STOP
                ST_ERR, ST_STOP : begin
                    case(phase)
                        // tin hieu stop se la trong luc scl = 1, sda di tu 0 -> 1 
                        2'b00 : begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b1; end
                        2'b01 : begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b1; end
                        2'b10 : sda_drive_low <= 1'b0;
                        2'b11 : begin
                            scl_drive_low   <= 1'b0;
                            sda_drive_low   <= 1'b0;
                            cmd_done        <= 1'b1;
                            state           <= ST_IDLE;
                        end
                    endcase
                end
            endcase
        end
    end

endmodule
