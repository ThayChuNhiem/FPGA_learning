module top_led_chaser (
    input  wire        CLOCK_50,  // Clock 50MHz từ PIN_Y2 trên DE2-115
    input  wire [0:0]  KEY,       // Nút nhấn reset KEY[0] (PIN_AB28)
    output reg  [17:0] LEDR       // 18 LED đỏ (LEDR[0] -> LEDR[17])
);

    
    reg [25:0] counter;
    reg        tick_1hz;

    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) begin
            counter  <= 26'd0;
            tick_1hz <= 1'b0;
        end else begin
            if (counter == 26'd49_999_999) begin
                counter  <= 26'd0;
                tick_1hz <= 1'b1;
            end else begin
                counter  <= counter + 1'b1;
                tick_1hz <= 1'b0;
            end
        end
    end

    // 2. Khối dịch LED (Shift Register)
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) begin
            LEDR <= 18'b0000_0000_0000_0000_01; // Sáng LEDR[0] ban đầu
        end else if (tick_1hz) begin
            LEDR <= {LEDR[16:0], LEDR[17]};    // Dịch trái xoay vòng
        end
    end

endmodule