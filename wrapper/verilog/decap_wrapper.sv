module hqc_decap_wrapper (
    input  wire clk,
    input  wire rst,
    input  wire rx,       // UART input from PC
    output wire tx,       
    output wire trig      
);

    // Internal control regs
    reg dec_start;   
    reg uart_start;

    // Wires from modules
    wire uart_done, uart_success;
    wire dec_done, dec_ready;
    wire rst_hqc = rst | soft_rst;
    
    wire [12:0] ct_addr;
    wire        ct_ce;
    wire [7:0]  ct_q;

    wire [8:0]  sk_addr;
    wire        sk_ce;
    wire [63:0] sk_q;

    wire [31:0] success_bus;

    // Shared secret memory interface
    wire [2:0]  ss_addr;
    wire        ss_ce;
    wire        ss_we;
    wire [63:0] ss_d;
    reg  [63:0] ss_mem [0:7];   
    reg  [63:0] ss_q;

    reg        ss_cap_en;          // capture window open
    reg [7:0]  ss_written;         // one bit per 64b word
    wire       ss_all_written = &ss_written;  // optional early close
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ss_cap_en   <= 1'b0;
            ss_written  <= 8'b0;
        end else begin
            // open window at start of a new decap
            if (dec_start) begin
                ss_cap_en  <= 1'b1;
                ss_written <= 8'b0;
            end
    
            // close window when core finishes, or when we've captured all 8 words
            if (dec_done || ss_all_written)
                ss_cap_en <= 1'b0;
        end
    end
    
    always @(posedge clk) begin
        if (ss_ce)
            ss_q <= ss_mem[ss_addr];
        if (ss_ce && ss_we && ss_cap_en && !ss_written[ss_addr]) begin
            ss_mem[ss_addr]    <= ss_d;
            ss_written[ss_addr] <= 1'b1;
        end
    end
    

    // UART loader
    uart_loader loader (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .start(uart_start),
        .done(uart_done),
        .success(uart_success),

        .ct_addr(ct_addr),
        .ct_ce(ct_ce),
        .ct_data(ct_q),

        .sk_addr(sk_addr),
        .sk_ce(sk_ce),
        .sk_data(sk_q)
    );

    // UART sender (for status messages)
    reg        send_en;
    reg [7:0]  send_data;
    wire       uart_busy;

    uart_sender u_sender (
        .clk(clk),
        .rst(rst),
        .send_en(send_en),
        .send_data(send_data),
        .busy(uart_busy),
        .tx(tx)
    );

    // Decapsulation core
    crypto_kem_dec_hls u_dec (
        .ap_clk(clk),
        .ap_rst(rst_hqc),
        .ap_start(dec_start),
        .ap_done(dec_done),
        .ap_ready(dec_ready),
        .ap_return(success_bus),

        .ct_V_address0(ct_addr),
        .ct_V_ce0(ct_ce),
        .ct_V_q0(ct_q),

        .sk_V_address0(sk_addr),
        .sk_V_ce0(sk_ce),
        .sk_V_q0(sk_q),

        .ss_V_address0(ss_addr),
        .ss_V_ce0(ss_ce),
        .ss_V_we0(ss_we),
        .ss_V_d0(ss_d),
        .ss_V_q0(ss_q)
    );
    
    wire dec_success = success_bus[0];
    
    // Trigger pin mirrors dec_start
    assign trig = dec_start;
    
    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        DECAP,
        SEND,
        SOFTRESET
    } state_t;
    
    state_t state;

    reg        soft_rst;
    reg [9:0]  soft_rst_cnt;     

    reg [7:0] ss0_byte;
    always @(posedge clk or posedge rst) begin
        if (rst)
            ss0_byte <= 8'h00;
        else if (dec_done)
            ss0_byte <= ss_mem[0][7:0];
    end

    typedef enum logic [1:0] { PH_STATUS, PH_SS0, PH_R } send_phase_t;
    send_phase_t send_phase;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            send_phase  <= PH_STATUS;
            uart_start  <= 1'b0;
            dec_start   <= 1'b0;
            send_en     <= 1'b0;
            send_data   <= 8'h00;
            soft_rst     <= 1'b0;
            soft_rst_cnt <= '0;

        end else begin
            uart_start  <= 1'b0;
            dec_start   <= 1'b0;
            send_en     <= 1'b0;

            case (state)
                IDLE: begin
                    if (!uart_busy) begin
                        send_data  <= "R";       
                        send_en    <= 1'b1;
                        state      <= SOFTRESET;
                    end
                end

                SOFTRESET: begin
                    soft_rst     <= 1'b1;                    
                    soft_rst_cnt <= soft_rst_cnt + 10'd1;
                    ss_written   <= 8'b0;     
                    
                    if (soft_rst_cnt == 10'd1023) begin       
                    soft_rst     <= 1'b0;                   
                    soft_rst_cnt <= '0;
                    state        <= LOAD;                  
                    end
                end

                LOAD: begin
                    uart_start <= 1'b1;         
                    if (uart_done) begin
                        dec_start <= 1'b1;      
                        if (!uart_busy) begin
                            send_data <= "L";    
                            send_en   <= 1'b1;
                        end
                        state <= DECAP;
                    end
                end

                DECAP: begin
                    if (dec_done) begin
                        send_phase <= PH_STATUS; 
                        state      <= SEND;
                    end
                end

                SEND: begin
                    case (send_phase)
                        PH_STATUS: begin
                            if (!uart_busy) begin
                                send_data  <= dec_success ? "N" : "Y";
                                send_en    <= 1'b1;
                                send_phase <= PH_SS0;
                            end
                        end

                        PH_SS0: begin
                            if (!uart_busy) begin
                                send_data  <= ss0_byte;
                                send_en    <= 1'b1;
                                send_phase <= PH_R;
                            end
                        end

                        PH_R: begin
                            if (!uart_busy) begin
                                send_data  <= "R";      
                                send_en    <= 1'b1;
                                state      <= SOFTRESET;
                                send_phase <= PH_STATUS;
                            end
                        end
                    endcase
                end

            endcase
        end
    end


endmodule
