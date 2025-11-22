module uart_sender (
    input  wire       clk,
    input  wire       rst,
    input  wire       send_en,
    input  wire [7:0] send_data,
    output reg        busy,
    output wire       tx
);

    reg        uart_tx_en;
    reg [7:0]  uart_tx_data;
    wire       uart_tx_busy;

    uart_tx #(
        .BIT_RATE(115_200),
        .PAYLOAD_BITS(8),
        .CLK_HZ(50_000_000)
    ) u_tx (
        .clk(clk),
        .resetn(~rst),
        .uart_txd(tx),
        .uart_tx_busy(uart_tx_busy),
        .uart_tx_en(uart_tx_en),
        .uart_tx_data(uart_tx_data)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_tx_en   <= 1'b0;
            uart_tx_data <= 8'h00;
            busy         <= 1'b0;
        end else begin
            uart_tx_en <= 1'b0; // default

            if (send_en && !uart_tx_busy) begin
                uart_tx_data <= send_data;
                uart_tx_en   <= 1'b1;
                busy         <= 1'b1;
            end else if (!uart_tx_busy) begin
                busy <= 1'b0;
            end
        end
    end

endmodule
