`timescale 1ns/1ps

module Core_tb;

    reg         CLK;
    reg         RST;
    reg  [7:0]  Rx_Byte_in;
    reg         Rx_DV_in;
    reg         Tx_Done_in;

    wire        Tx_DV_out;
    wire [7:0]  Tx_Byte_out;
    wire [7:0]  c_out;

    //==================================================//
    //                    DUT Instance                  //
    //==================================================//
    Core dut (
        .CLK(CLK),
        .RST(RST),
        .Rx_Byte_in(Rx_Byte_in),
        .Rx_DV_in(Rx_DV_in),
        .Tx_Done_in(Tx_Done_in),
        .Tx_DV_out(Tx_DV_out),
        .Tx_Byte_out(Tx_Byte_out),
        .c_out(c_out)
    );

    //==================================================//
    //                     Clock 100MHz                 //
    //==================================================//
    initial CLK = 0;
    always #5 CLK = ~CLK;

    //==================================================//
    //               Task gửi 1 byte RX                 //
    //==================================================//
    task send_byte;
        input [7:0] data;
        begin
            @(posedge CLK);
            Rx_Byte_in <= data;
            Rx_DV_in   <= 1'b1;
            @(posedge CLK);
            Rx_DV_in   <= 1'b0;
        end
    endtask

    //==================================================//
    //                     Main TB                      //
    //==================================================//
    integer i;

    initial begin
        Rx_Byte_in = 8'h00;
        Rx_DV_in   = 1'b0;
        Tx_Done_in = 1'b0;

        // Reset
        RST = 1'b0;
        repeat(5) @(posedge CLK);
        RST = 1'b1;

        @(posedge CLK);
        $display("\n=========== START WORKING SESSION ===========\n");

        //==================================================//
        //        4 byte input (A_hi,A_lo,B_hi,B_lo)        //
        //==================================================//
        send_byte(8'h12);
        send_byte(8'h34);
        send_byte(8'hFF);
        send_byte(8'h80);

        $display("[TB] RX done. Waiting for first Tx_DV_out...");

        //==================================================//
        //             Nhận TX byte 1 (MSB)                //
        //==================================================//
        wait(Tx_DV_out == 1'b1);
        $display("[TB] TX Byte 1 (MSB): %h", Tx_Byte_out);

        //==================================================//
        //        Delay 25 cycles before next Tx_Done       //
        //==================================================//
        $display("[TB] Waiting 25 cycles before second TX DONE...");
        for (i = 0; i < 25; i = i + 1)
            @(posedge CLK);
		
        @(posedge CLK);
        Tx_Done_in <= 1'b1;
        @(posedge CLK);
        Tx_Done_in <= 1'b0;

        //==================================================//
        //        Delay 25 cycles before next Tx_Done       //
        //==================================================//
        $display("[TB] Waiting 25 cycles before second TX DONE...");
        for (i = 0; i < 25; i = i + 1)
            @(posedge CLK);

        //==================================================//
        //             Nhận TX byte 2 (LSB)                //
        //==================================================//
        // wait(Tx_DV_out == 1'b1);
        // $display("[TB] TX Byte 2 (LSB): %h", Tx_Byte_out);

        // Pulse Tx_Done_in for 1 cycle
        @(posedge CLK);
        Tx_Done_in <= 1'b1;
        @(posedge CLK);
        Tx_Done_in <= 1'b0;

        $display("[TB] Final c_out MSB: %h", c_out);

        #100;
        $finish;
    end

endmodule
