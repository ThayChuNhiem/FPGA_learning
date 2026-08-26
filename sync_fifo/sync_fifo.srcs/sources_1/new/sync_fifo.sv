`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/19/2026 01:01:44 PM
// Design Name: 
// Module Name: sync_fifo
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


module sync_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 1024
)(
    input  logic                  clk, rst_n,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] din,
    output logic                  full,
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] dout,
    output logic                  empty,
    output logic [$clog2(FIFO_DEPTH):0] data_count
);
    
    localparam ADD_WIDTH = $clog2(FIFO_DEPTH);  // so bit can de luu do sau cua fifo
    localparam PTR_WIDTH = ADD_WIDTH + 1;       // so bit can cua con tro pointer
    
    //ep cho kieu luu vao bram
    (*ram_style = "block"*) logic [DATA_WIDTH -1 : 0] mem [0 : FIFO_DEPTH -1];
    
    //khai bao con tro doc va ghi
    logic [PTR_WIDTH -1 : 0] rd_ptr;
    logic [PTR_WIDTH -1 : 0] wr_ptr;
    
    //check golden rules
    wire read_valid = rd_en && !empty;
    wire write_valid = wr_en && !full;
    
    //quan ly pointer write va read
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            wr_ptr <= '0;
        end else begin
            if(read_valid) rd_ptr <= rd_ptr + 1'b1;
            if(write_valid) wr_ptr <= wr_ptr + 1'b1;
        end
    end
    
    //quan ly ghi va doc
    always @(posedge clk ) begin
        if(read_valid) dout <= mem[rd_ptr[ADD_WIDTH-1:0]];
        if(write_valid) mem[wr_ptr[ADD_WIDTH-1:0]] <= din;
    end 
    
    //full
    assign full = (wr_ptr[PTR_WIDTH - 1] != rd_ptr[PTR_WIDTH - 1]) &
     (wr_ptr[PTR_WIDTH - 2 : 0 ] == rd_ptr[PTR_WIDTH -2 : 0]);
     
     //empty
     assign empty = (rd_ptr == wr_ptr);
     
     //data count
     assign data_count = wr_ptr - rd_ptr;
    
endmodule
