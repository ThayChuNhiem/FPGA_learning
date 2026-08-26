`timescale 1ns / 1ps

module tb_top_led_chaser();

    // Khai báo reg cho đầu vào (inputs của DUT)
    reg CLOCK_50;
    reg [0:0] KEY;

    // Khai báo wire cho đầu ra (outputs của DUT)
    wire [17:0] LEDR;

    // Kết nối với Module chính (DUT)
    top_led_chaser uut (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .LEDR(LEDR)
    );

    // 1. Tạo xung Clock 50MHz (Chu kỳ T = 20ns -> đảo trạng thái mỗi 10ns)
    initial begin
        CLOCK_50 = 0;
        forever #10 CLOCK_50 = ~CLOCK_50;
    end

    // 2. Kịch bản Reset và Điều khiển
    initial begin
        // Giả sử KEY[0] là nút Reset (active low)
        KEY[0] = 0;      // Bật Reset
        #100;            // Giữ Reset trong 100ns
        KEY[0] = 1;      // Giải phóng Reset
        
        // Chạy tiếp trong khoảng thời gian nhất định
        #10000;
        $stop;
    end

endmodule