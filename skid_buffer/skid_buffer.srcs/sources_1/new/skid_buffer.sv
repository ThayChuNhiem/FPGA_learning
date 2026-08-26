`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/20/2026 04:34:20 PM
// Design Name: 
// Module Name: skid_buffer
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


module skid_buffer #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // AXI4-Stream Slave Interface (Input)
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,

    // AXI4-Stream Master Interface (Output)
    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic                  m_axis_tvalid,
    input  logic                  m_axis_tready
);

    logic [DATA_WIDTH - 1 : 0 ]     data_reg;
    logic [DATA_WIDTH - 1 : 0]      skid_reg;
    
    logic skid_valid;
    
    assign m_axis_tdata = data_reg;
    
    wire s_handshake = s_axis_tready & s_axis_tvalid;
    wire m_handshake = m_axis_tvalid & m_axis_tready;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            data_reg <= '0;
            skid_reg <= '0;
            skid_valid <= 1'b0;
            m_axis_tvalid <= 1'b0;  //master khong nhan du lieu
            s_axis_tready <= 1'b1;  //slave luon trong trang thai san sang sau reset
        end else begin
            if(skid_valid) begin
                if(m_axis_tready) begin
                    data_reg <= skid_reg;
                    skid_valid <= 1'b0;
                    s_axis_tready <= 1'b1;
                end
            end else begin
                
            
            end
        end
    end

endmodule

/* 
// Hai thanh ghi lưu trữ
    logic [DATA_WIDTH-1:0] data_reg; // Luôn là thanh ghi xuất ra ngoài
    logic [DATA_WIDTH-1:0] skid_reg; // Thanh ghi phụ để hứng khi bị stall
    logic                  skid_valid;
    // Ngõ ra luôn nối trực tiếp từ data_reg (Đảm bảo 100% Registered Output)
    assign m_axis_tdata = data_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg      <= '0;
            skid_reg      <= '0;
            skid_valid    <= 1'b0;
            m_axis_tvalid <= 1'b0;
            s_axis_tready <= 1'b1;
        end else begin
            // -------------------------------------------------------------
            // TRƯỜNG HỢP 1: Đang có dữ liệu kẹt trong Skid Register (FULL)
            // Lúc này: data_reg chứa D0, skid_reg chứa D1, s_axis_tready = 0
            // -------------------------------------------------------------
            if (skid_valid) begin
                if (m_axis_tready) begin
                    // Slave vừa đọc xong D0 ở chu kỳ này!
                    // => NẠP D1 TỪ SKID VÀO DATA_REG ĐỂ CHU KỲ SAU SLAVE ĐỌC TIẾP
                    data_reg      <= skid_reg;   // <--- CHÍNH LÀ Ở ĐÂY!
                    skid_valid    <= 1'b0;       // Giải phóng Skid Register
                    s_axis_tready <= 1'b1;       // Báo cho bên gửi có thể bơm tiếp
                end
                // Nếu m_axis_tready = 0: Tiếp tục giữ nguyên trạng thái chờ Slave
            end
            // -------------------------------------------------------------
            // TRƯỜNG HỢP 2: Skid Register đang rỗng (!skid_valid)
            // -------------------------------------------------------------
            else begin
                if (m_axis_tready || !m_axis_tvalid) begin
                    // Đầu ra sẵn sàng nhận data mới trực tiếp vào data_reg
                    if (s_axis_tvalid) begin
                        data_reg      <= s_axis_tdata; // Nạp thẳng vào data_reg
                        m_axis_tvalid <= 1'b1;
                    end else begin
                        m_axis_tvalid <= 1'b0;         // Không có data -> hạ valid
                    end
                    s_axis_tready <= 1'b1;
                end else begin
                    // Đầu ra đang bận (m_axis_tready = 0 và m_axis_tvalid = 1)
                    // Nhưng bên gửi vẫn gửi thêm 1 gói tới (s_axis_tvalid = 1)
                    if (s_axis_tvalid && s_axis_tready) begin
                        skid_reg      <= s_axis_tdata; // Hứng gói mới vào skid_reg
                        skid_valid    <= 1'b1;         // Đánh dấu skid đã đầy
                        s_axis_tready <= 1'b0;         // Khóa bên gửi ở nhịp sau!
                    end
                end
            end
        end
    end
*/