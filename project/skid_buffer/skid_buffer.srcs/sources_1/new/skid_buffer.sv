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
