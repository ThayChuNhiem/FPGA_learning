`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/19/2026 02:43:38 PM
// Design Name: 
// Module Name: async_fifo
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

module async_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 1024
)(
    // Write Domain
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] din,
    output logic                  full,

    // Read Domain
    input  logic                  rd_clk,
    input  logic                  rd_rst_n,
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] dout,
    output logic                  empty
);
    //khai bao so bit can de luu dia chi / index
    //i2c - 
    localparam ADD_WIDTH = $clog2(FIFO_DEPTH);
    //so bit cua pointer can
    localparam PTR_WIDTH = ADD_WIDTH + 1;
    
    //khai bao kieu bram
    (*ram_style = "block"*) logic [DATA_WIDTH - 1 : 0] mem [0 : FIFO_DEPTH -1];
    
    //khai bao pointer cho binary va gray
    logic [PTR_WIDTH - 1 : 0 ] wr_ptr_bin, wr_ptr_gray;
    logic [PTR_WIDTH - 1 : 0 ] rd_ptr_bin, rd_ptr_gray;

    //khai bao cac pointer cdc
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH - 1 :0 ] wr_ptr_sync_1, wr_ptr_sync_2;
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH - 1 :0 ] rd_ptr_sync_1, rd_ptr_sync_2;
    
    
    wire read_valid = rd_en && !empty;
    wire write_valid = wr_en && !full;
    
    
    //fifo
    always_ff @(posedge wr_clk) begin
        if(write_valid) mem[wr_ptr_bin[ADD_WIDTH -1 :0]] <= din;
    end
    
    always_ff @(posedge rd_clk) begin
        if(read_valid) dout <= mem[rd_ptr_bin[ADD_WIDTH -1 :0]];
    end
    
    //xu ly co full tai wr_clk
    logic [PTR_WIDTH - 1 : 0] wr_ptr_bin_next;
    logic [PTR_WIDTH - 1 : 0] wr_ptr_gray_next;
    
    //xu li mach to hop cho next_ptr -> khong bi tre 1 chu ky
    assign wr_ptr_bin_next = wr_ptr_bin + (write_valid ? 1'b1 : 1'b0);
    assign wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
    
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            wr_ptr_bin <= '0;
            wr_ptr_gray <= '0;
        end else begin
            wr_ptr_bin <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end
    
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            rd_ptr_sync_1 <= '0;
            rd_ptr_sync_2 <= '0;
        end else begin
            rd_ptr_sync_1 <= rd_ptr_gray;
            rd_ptr_sync_2 <= rd_ptr_sync_1;
        end
    end
    
    assign full = (wr_ptr_gray == {~rd_ptr_sync_2[PTR_WIDTH - 1 : PTR_WIDTH -2],
                                    rd_ptr_sync_2[PTR_WIDTH -3 : 0]});
    
    //xu li empty tai rd_clk
    logic [PTR_WIDTH - 1 : 0] rd_ptr_bin_next;
    logic [PTR_WIDTH - 1 : 0] rd_ptr_gray_next;
    
    assign rd_ptr_bin_next = rd_ptr_bin + (read_valid ? 1'b1 : 1'b0);
    assign rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;
    
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            rd_ptr_bin <= '0;
            rd_ptr_gray <= '0;
        end else begin
            rd_ptr_bin <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end
    
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            wr_ptr_sync_1 <= '0;
            wr_ptr_sync_2 <= '0;
        end else begin
            wr_ptr_sync_1 <= wr_ptr_gray;
            wr_ptr_sync_2 <= wr_ptr_sync_1;
        end
    end
    
    assign empty = (wr_ptr_sync_2 == rd_ptr_gray); 
endmodule

