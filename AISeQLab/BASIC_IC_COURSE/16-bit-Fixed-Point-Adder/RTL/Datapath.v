/*
 *-----------------------------------------------------------------------------
 * Title       : Datapath
 * Description : 8-bit signed fixed-point adder with clock and reset
 * Author      : Pham Hoai Luan
 * Date        : 2025-11-04
 *-----------------------------------------------------------------------------
 * Format      : Q4.3 (1 sign, 4 integer, 3 fractional)
 * Function    : c_out_ = a_in + b_in  (saturation)
 *-----------------------------------------------------------------------------
 */

module Datapath (
    input  wire                 CLK,
	input  wire					RST,
	input  wire					En_in,
    input  wire signed [15:0]   a_in,        // input A (Q4.3)
    input  wire signed [15:0]   b_in,        // input B (Q4.3)
    output reg  signed [15:0]   c_out,       // output C (Q4.3)
	output reg 					c_valid_out
);

    //==================================================//
    //                   	Wire                      	//
    //==================================================//
	
    wire signed [16:0] 			sum_w;   

	//==================================================//
    //              Combinational Circuits              //
    //==================================================//
	
    assign sum_w 				= a_in + b_in;

	//==================================================//
    //              	Sequential Circuits             //
    //==================================================//
	
    always @(posedge CLK or negedge RST) begin
		if(RST == 0) begin
			c_out				<= 0;
			c_valid_out			<= 0;
		end
        else begin
			if(En_in) begin
				c_valid_out		<= 1;
				if (sum_w > 32767)
					c_out 		<= 17'sd32767;
				else if (sum_w < -32768)
					c_out 		<= -17'sd32768;
				else
					c_out 		<= sum_w[15:0];
			end
			else begin
				c_out			<= c_out;
				c_valid_out		<= 0;
			end
		end
    end

endmodule
