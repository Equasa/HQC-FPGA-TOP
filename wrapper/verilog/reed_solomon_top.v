// -----------------------------------------------------------------------------
// CW305 Top-Level for HQC Decapsulation
// -----------------------------------------------------------------------------

module cw305_top_rs (
    input  wire         clk_hs2,   // 50 MHz from Husky
    //input  wire         rst_n,       // Active high reset from ChipWhisperer
    input  wire         tio_rx,    // UART RX from Husky TX
    output wire         tio_tx,    // UART TX to Husky RX
    output wire         trig       // Triggger output for Husky    
);
    
    // Hold reset high for ~2^16 cycles after config
    reg [15:0] por = 16'd0;
    always @(posedge clk_hs2)
        por <= por + !por[15];            // stop incrementing once MSB=1
    
    wire rst = ~por[15];

    // Instantiate wrapper
    rs_decode_wrapper dut (
        .clk(clk_hs2),   // use 100 MHz PLL clock
        .rst(rst),
        .rx(tio_rx),
        .tx(tio_tx),
        .trig(trig)
    );

endmodule
