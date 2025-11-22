// -----------------------------------------------------------------------------
// RS decode wrapper around VHDL entity `reed_solomon_decode`
// UART protocol:
//   - After reset: sends 'R'
//   - Receives exactly CODEWORD_BYTES (46) into cdw_mem[0..]
//   - Starts decoder (hold ap_start until ap_ready)
//   - On ap_done: sends 'D', then streams min(observed, MESSAGE_BYTES=16)
//   - Sends 'R' and repeats
// -----------------------------------------------------------------------------
// Vivado-friendly RAM inference fixes:
//   * cdw_mem: single write port via mux (host OR core), single sync read port
//   * msg_mem: core write port + host sync read port (1-cycle latency), prime state
// -----------------------------------------------------------------------------
module rs_decode_wrapper #(
    // BRAM address widths from your VHDL ports
    parameter int unsigned CDW_AW         = 6,    // cdw depth 2^6 = 64
    parameter int unsigned MSG_AW         = 13,   // msg depth 2^13 = 8192

    // Exact I/O sizes for your RS variant
    parameter int unsigned CODEWORD_BYTES = 46,   // bytes we will load
    parameter int unsigned MESSAGE_BYTES  = 16    // bytes we will return
)(
    input  wire clk,
    input  wire rst,
    input  wire rx,
    output wire tx,
    output wire trig
);
    localparam int unsigned CDW_DEPTH = (1 << CDW_AW);
    localparam int unsigned MSG_DEPTH = (1 << MSG_AW);

    // Cast constants to packed widths where helpful
    localparam logic [MSG_AW-1:0] MESSAGE_BYTES_U = MESSAGE_BYTES[MSG_AW-1:0];

    // ---------------------------
    // UART Rx/Tx
    // ---------------------------
    wire       uart_rx_valid;
    wire [7:0] uart_rx_data;
    uart_rx #(
        .BIT_RATE(115_200),
        .PAYLOAD_BITS(8),
        .CLK_HZ(50_000_000)
    ) u_rx (
        .clk(clk),
        .resetn(~rst),
        .uart_rxd(rx),
        .uart_rx_en(1'b1),
        .uart_rx_break(),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_data(uart_rx_data)
    );

    reg        send_en;
    reg [7:0]  send_data;
    wire       uart_busy;
    uart_sender u_txsend (
        .clk(clk),
        .rst(rst),
        .send_en(send_en),
        .send_data(send_data),
        .busy(uart_busy),
        .tx(tx)
    );

    // ---------------------------
    // Soft reset (for the core)
    // ---------------------------
    reg        soft_rst;
    reg [9:0]  soft_rst_cnt;
    wire       rst_core = rst | soft_rst;

    // ---------------------------
    // Memories (simple BRAM-style)
    // ---------------------------
    // Codeword memory (8-bit), BRAM hint
    (* ram_style = "block" *)
    reg [7:0] cdw_mem [0:CDW_DEPTH-1];

    // Message buffer written by core, read by host (sync read)
    (* ram_style = "block" *)
    reg [7:0] msg_mem [0:MSG_DEPTH-1];

    // Track highest message address written by the core this round + wrote_any flag
    reg [MSG_AW-1:0] msg_high_addr;
    reg              msg_wrote_any;

    // ---------------------------
    // VHDL core interface signals
    // ---------------------------
    wire        ap_done, ap_ready, ap_idle;
    reg         ap_start;
    reg         start_armed;  // handshake latch

    // msg write port from core
    wire [MSG_AW-1:0] msg_V_address1;
    wire              msg_V_ce1;
    wire              msg_V_we1;
    wire [7:0]        msg_V_d1;

    // cdw read port0 for core
    wire [CDW_AW-1:0] cdw_V_address0;
    wire              cdw_V_ce0;
    reg  [7:0]        cdw_V_q0;

    // cdw write port1 from core
    wire [CDW_AW-1:0] cdw_V_address1;
    wire              cdw_V_ce1;
    wire              cdw_V_we1;
    wire [7:0]        cdw_V_d1;

    // ---------------------------
    // Host-side loader bookkeeping (exactly CODEWORD_BYTES)
    // (No direct writes to cdw_mem here; all writes go through the muxed port B below)
    // ---------------------------
    reg [CDW_AW-1:0] load_idx;
    reg              loading;
    reg [15:0]       load_cnt;   // counts received bytes (46 max)

    always @(posedge clk) begin
        if (rst) begin
            load_idx <= '0;
            load_cnt <= '0;
        end else if (loading && uart_rx_valid) begin
            if (load_cnt < CODEWORD_BYTES) begin
                load_idx <= load_idx + 1'b1;  // 46 < 64, safe
                load_cnt <= load_cnt + 1'b1;
            end
        end
    end

    // ---------------------------
    // cdw_mem: Port A (core sync read), Port B (muxed host/core write)
    // ---------------------------
    // Host-side write intent (during load)
    wire                     host_we    = loading && uart_rx_valid && (load_cnt < CODEWORD_BYTES);
    wire [7:0]               host_din   = uart_rx_data;
    wire [CDW_AW-1:0]        host_addr  = load_idx;

    // Core-side write intent (port1)
    wire                     core_we    = (cdw_V_ce1 & cdw_V_we1);
    wire [7:0]               core_din   = cdw_V_d1;
    wire [CDW_AW-1:0]        core_addr  = cdw_V_address1;

    // Select who owns the single physical write port B this cycle
    wire                     cdw_wr_sel_host = loading;

    wire                     cdw_we_b   = cdw_wr_sel_host ? host_we   : core_we;
    wire [7:0]               cdw_din_b  = cdw_wr_sel_host ? host_din  : core_din;
    wire [CDW_AW-1:0]        cdw_addr_b = cdw_wr_sel_host ? host_addr : core_addr;

    always @(posedge clk) begin
        // Port A: core synchronous read
        if (cdw_V_ce0)
            cdw_V_q0 <= cdw_mem[cdw_V_address0];

        // Port B: synchronous write (host OR core)
        if (cdw_we_b)
            cdw_mem[cdw_addr_b] <= cdw_din_b;
    end

    // ---------------------------
    // msg_mem: core write (port1) + host synchronous read port
    // ---------------------------
    reg [MSG_AW-1:0] msg_rd_addr;
    reg              msg_rd_en;
    reg [7:0]        msg_rd_data;

    always @(posedge clk) begin
        // Core write port
        if (msg_V_ce1 & msg_V_we1) begin
            msg_mem[msg_V_address1] <= msg_V_d1;
            msg_wrote_any <= 1'b1;
            if (msg_V_address1 > msg_high_addr)
                msg_high_addr <= msg_V_address1;
        end

        // Host read port (synchronous)
        if (msg_rd_en)
            msg_rd_data <= msg_mem[msg_rd_addr];
    end

    // ---------------------------
    // Instantiate the VHDL core
    // ---------------------------
    reed_solomon_decode u_rs (
        .ap_clk (clk),
        .ap_rst (rst_core),
        .ap_start(ap_start),
        .ap_done(ap_done),
        .ap_idle(ap_idle),
        .ap_ready(ap_ready),

        .msg_V_address1(msg_V_address1),
        .msg_V_ce1     (msg_V_ce1),
        .msg_V_we1     (msg_V_we1),
        .msg_V_d1      (msg_V_d1),

        .cdw_V_address0(cdw_V_address0),
        .cdw_V_ce0     (cdw_V_ce0),
        .cdw_V_q0      (cdw_V_q0),

        .cdw_V_address1(cdw_V_address1),
        .cdw_V_ce1     (cdw_V_ce1),
        .cdw_V_we1     (cdw_V_we1),
        .cdw_V_d1      (cdw_V_d1)
    );

    // ---------------------------
    // Control FSM
    // ---------------------------
    typedef enum logic [2:0] {
        S_IDLE       = 3'd0,
        S_SOFTRESET  = 3'd1,
        S_LOAD       = 3'd2,
        S_DECODE     = 3'd3,
        S_SEND_HDR   = 3'd4,
        S_SEND_PRIME = 3'd5, // new: absorb BRAM read latency
        S_SEND_MSG   = 3'd6,
        S_SEND_TAIL  = 3'd7
    } state_t;

    state_t state;

    // Send window / counters
    reg [MSG_AW-1:0] send_idx;
    reg [MSG_AW-1:0] send_len;  // = min(observed, MESSAGE_BYTES)
    wire [MSG_AW-1:0] observed_len = msg_wrote_any ? (msg_high_addr + {{(MSG_AW-1){1'b0}},1'b1}) : '0;

    // Trigger mirrors start pulse
    assign trig = ap_start;

    // Min helper
    function automatic [MSG_AW-1:0] min_len(
        input [MSG_AW-1:0] a,
        input [MSG_AW-1:0] b
    );
        min_len = (a < b) ? a : b;
    endfunction

    // FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= S_IDLE;
            send_en       <= 1'b0;
            send_data     <= 8'h00;
            soft_rst      <= 1'b0;
            soft_rst_cnt  <= 10'd0;
            ap_start      <= 1'b0;
            start_armed   <= 1'b0;
            loading       <= 1'b0;
            load_idx      <= '0;
            load_cnt      <= '0;
            msg_high_addr <= '0;
            msg_wrote_any <= 1'b0;
            send_idx      <= '0;
            send_len      <= '0;
            msg_rd_en     <= 1'b0;
            msg_rd_addr   <= '0;
        end else begin
            // defaults each cycle
            send_en   <= 1'b0;
            ap_start  <= 1'b0;
            msg_rd_en <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (!uart_busy) begin
                        send_data <= "R";
                        send_en   <= 1'b1;

                        // soft reset before every session
                        soft_rst     <= 1'b1;
                        soft_rst_cnt <= 10'd0;

                        // prep
                        msg_high_addr <= '0;
                        msg_wrote_any <= 1'b0;
                        load_idx      <= '0;
                        load_cnt      <= '0;
                        start_armed   <= 1'b0;

                        state         <= S_SOFTRESET;
                    end
                end

                S_SOFTRESET: begin
                    soft_rst_cnt <= soft_rst_cnt + 10'd1;
                    if (soft_rst_cnt == 10'd1023) begin
                        soft_rst <= 1'b0;
                        // start loading codeword
                        loading  <= 1'b1;
                        state    <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    // Finish precisely when 46 bytes received
                    if (loading && (load_cnt == CODEWORD_BYTES)) begin
                        loading <= 1'b0;
                        if (!uart_busy) begin
                            send_data <= "L";   // load done ack (debug)
                            send_en   <= 1'b1;
                        end
                        state <= S_DECODE;
                    end
                end

                S_DECODE: begin
                    // Hold ap_start high until ap_ready acknowledges (ap_ctrl_hs)
                    if (!start_armed) begin
                        ap_start <= 1'b1;
                        if (ap_ready) begin
                            ap_start    <= 1'b0;
                            start_armed <= 1'b1;
                        end
                    end

                    // Wait for completion
                    if (ap_done) begin
                        start_armed <= 1'b0;

                        // Send min(observed writes, 16)
                        send_len <= min_len(observed_len, MESSAGE_BYTES_U);
                        send_idx <= '0;
                        state    <= S_SEND_HDR;
                    end
                end

                S_SEND_HDR: begin
                    if (!uart_busy) begin
                        send_data <= "D"; // "Decode done"
                        send_en   <= 1'b1;

                        // Prime the first BRAM read
                        msg_rd_addr <= '0;
                        if (send_len != '0)
                            msg_rd_en <= 1'b1;

                        state <= S_SEND_PRIME;
                    end
                end

                S_SEND_PRIME: begin
                    // One cycle later, msg_rd_data holds byte 0 (if any)
                    state <= S_SEND_MSG;
                end

                S_SEND_MSG: begin
                    if (send_idx < send_len) begin
                        if (!uart_busy) begin
                            // Send the data captured last cycle
                            send_data <= msg_rd_data;
                            send_en   <= 1'b1;

                            // Queue the next BRAM read (if any)
                            if ((send_idx + 1'b1) < send_len) begin
                                msg_rd_addr <= send_idx + 1'b1;
                                msg_rd_en   <= 1'b1; // pulse this cycle for next read
                            end

                            send_idx <= send_idx + 1'b1;
                        end
                    end else begin
                        state <= S_SEND_TAIL;
                    end
                end

                S_SEND_TAIL: begin
                    if (!uart_busy) begin
                        send_data <= "R"; // ready for next round
                        send_en   <= 1'b1;

                        // Prepare for next capture
                        msg_high_addr <= '0;
                        msg_wrote_any <= 1'b0;
                        soft_rst      <= 1'b1;
                        soft_rst_cnt  <= 10'd0;
                        state         <= S_SOFTRESET;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
