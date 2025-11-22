module uart_loader #(
    parameter CT_BYTES = 4481,   // ciphertext size in bytes
    parameter SK_BYTES = 2296    // secret key size in bytes
)(
    input  wire clk,
    input  wire rst,
    input  wire rx,

    input  wire start,          // 1-cycle pulse from wrapper
    output reg  done,
    output reg  success,

    input  wire [12:0] ct_addr,
    input  wire        ct_ce,
    output reg  [7:0]  ct_data,

    input  wire [8:0]  sk_addr,
    input  wire        sk_ce,
    output reg  [63:0] sk_data
);

    // UART Receiver (Ben Marshalls)
    wire       uart_rx_valid;
    wire [7:0] uart_rx_data;

    uart_rx #(
        //-----------------------------------------
        // Testparameters used for simulation
        //-----------------------------------------
        //.BIT_RATE(5_000_000),  
        //.PAYLOAD_BITS(8),
        //.CLK_HZ(100_000_000)
        //-----------------------------------------
        // Productionparameters used for simulation
        //-----------------------------------------
        .BIT_RATE(115_200),  
        .PAYLOAD_BITS(8),
        .CLK_HZ(50_000_000)
    ) u_rx (
        .clk          (clk),
        .resetn       (~rst),     // active-low for Marshall's implementation
        .uart_rxd     (rx),
        .uart_rx_en   (1'b1),
        .uart_rx_break(),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_data (uart_rx_data)
    );

    // Memory storage
    reg [7:0]  ct_mem [0:CT_BYTES-1];
    reg [63:0] sk_mem [0:(SK_BYTES/8)-1];

    // implemented to be slave to decap module
    always @(posedge clk) begin
        if (ct_ce)
            ct_data <= ct_mem[ct_addr];
        if (sk_ce)
            sk_data <= sk_mem[sk_addr];
    end

    // State encoding
    localparam S_IDLE    = 0,
               S_LOAD_CT = 1,
               S_LOAD_SK = 2,
               S_DONE    = 3;

    reg [1:0] state;
    reg [12:0] ct_count;
    reg [12:0] sk_total;

    // Little-endian pack support
    reg [7:0]  sk_byte [0:7];  // collects 8 incoming bytes
    reg [2:0]  sk_byte_count;  // 0..7
    reg [8:0]  sk_word_idx;    // index into sk_mem[] (2312/8 = 289 -> 9 bits)

    // Start control
    reg started;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            started <= 1'b0;
        end else if (start) begin
            started <= 1'b1;
        end else if (state == S_DONE) begin
            started <= 1'b0;
        end
    end

    // Loader state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= S_IDLE;
            done           <= 1'b0;
            success        <= 1'b0;

            ct_count       <= 13'd0;

            sk_total       <= 13'd0;
            sk_byte_count  <= 3'd0;
            sk_word_idx    <= 9'd0;

        end else begin
            case (state)
                S_IDLE: begin
                    done    <= 1'b0;
                    success <= 1'b0;

                    if (started) begin
                        state          <= S_LOAD_CT;
                        ct_count       <= 13'd0;

                        sk_total       <= 13'd0;
                        sk_byte_count  <= 3'd0;
                        sk_word_idx    <= 9'd0;
                    end
                end

                // Receive CT bytes
                S_LOAD_CT: begin
                    if (uart_rx_valid) begin
                        ct_mem[ct_count] <= uart_rx_data;
                        ct_count         <= ct_count + 13'd1;
                        if (ct_count == CT_BYTES-1)
                            state <= S_LOAD_SK;
                    end
                end

                // Receive SK bytes and pack 8 at a time into 64b words (LITTLE-ENDIAN in-lane)
                // First byte received -> bits [7:0], second -> [15:8], ..., eighth -> [63:56].
                S_LOAD_SK: begin
                    if (uart_rx_valid) begin
                        // Accumulate the byte
                        sk_byte[sk_byte_count] <= uart_rx_data;
                        sk_total               <= sk_total + 13'd1;

                        if (sk_byte_count == 3'd7) begin
                            // 8th byte just arrived: commit a 64-bit word
                            // LE packing per 64-bit lane:
                            //   {b7,b6,b5,b4,b3,b2,b1,b0} with b0 in [7:0]
                            sk_mem[sk_word_idx] <= {
                                uart_rx_data,         // b7 -> [63:56]
                                sk_byte[6],           // b6 -> [55:48]
                                sk_byte[5],           // b5 -> [47:40]
                                sk_byte[4],           // b4 -> [39:32]
                                sk_byte[3],           // b3 -> [31:24]
                                sk_byte[2],           // b2 -> [23:16]
                                sk_byte[1],           // b1 -> [15:8]
                                sk_byte[0]            // b0 -> [7:0]
                            };
                            sk_word_idx   <= sk_word_idx + 9'd1;
                            sk_byte_count <= 3'd0;
                        end else begin
                            sk_byte_count <= sk_byte_count + 3'd1;
                        end

                        // When we've received exactly SK_BYTES bytes, we're done.
                        // (SK_BYTES is a multiple of 8, so we always finish on a word boundary.)
                        if (sk_total == SK_BYTES-1) begin
                            state   <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    done    <= 1'b1;
                    success <= 1'b1;
                    if (!started)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
    

endmodule
