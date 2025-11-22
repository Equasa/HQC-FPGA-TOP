`timescale 1ns/1ps

module tb_hqc_decap_wrapper;

    // --------------------
    // DUT I/O
    // --------------------
    reg  clk;
    reg  rst;
    reg  rx;          // keep idle-high; not used here
    wire tx;          // unused
    wire trig;        // unused

    // --------------------
    // Instantiate DUT
    // --------------------
    hqc_decap_wrapper dut (
        .clk (clk),
        .rst (rst),
        .rx  (rx),
        .tx  (tx),
        .trig(trig)
         );

    // 50 MHz clock (20 ns)
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // Keep UART RX idle
    initial rx = 1'b1;

    // ----------------------
    // Sizes (match RTL)
    // ----------------------
    localparam integer CT_BYTES = 4481;
    localparam integer SK_BYTES = 2296; // multiple of 8

    // Fixed-size byte buffers (Verilog-2001)
    reg [7:0] ct_buf [0:CT_BYTES-1];
    reg [7:0] sk_buf [0:SK_BYTES-1];

    integer f, ch, i, nread;

    // Pack 8 bytes into a 64-bit word (BIG-ENDIAN):
    //   word[63:56]=b0, [55:48]=b1, ..., [7:0]=b7
    function [63:0] pack64_le(
        input [7:0] b0, b1, b2, b3, b4, b5, b6, b7
    );
        pack64_le = {b7,b6,b5,b4,b3,b2,b1,b0};
    endfunction

    // -------- Optional helpers to peek nicely --------
    task show_first_bytes;
        integer k;
        reg [63:0] w0;
        begin
            if (^dut.loader.ct_mem[0] !== 1'bx) begin
                $display("CT[0..7]:");
                for (k=0;k<8;k=k+1) $display("  ct_mem[%0d] = 0x%02h", k, dut.loader.ct_mem[k]);
            end
            if (^dut.loader.sk_mem[0] !== 1'bx) begin
                w0 = dut.loader.sk_mem[0];
                $display("SK word 0 (64b) = 0x%016h", w0);
                $display("SK word 0 bytes (MSB..LSB): %02h %02h %02h %02h %02h %02h %02h %02h",
                    w0[63:56], w0[55:48], w0[47:40], w0[39:32], w0[31:24], w0[23:16], w0[15:8], w0[7:0]);
            end
        end
    endtask

    initial begin
        // ---------------- Reset ----------------
        rst = 1'b1;
        repeat (100) @(posedge clk);
        rst = 1'b0;
        repeat (100) @(posedge clk);

        // --------------- Read files ---------------
        // Clear/pad buffers
        for (i = 0; i < CT_BYTES; i = i + 1) ct_buf[i] = 8'h00;
        for (i = 0; i < SK_BYTES; i = i + 1) sk_buf[i] = 8'h00;

        // Ciphertext
        f = $fopen("/home/benjamin/Master-thesis/hqc-data-generator/ciphertext.bin", "rb");
        if (f == 0) $fatal(1, "Failed to open ciphertext.bin");
        nread = 0;
        while (nread < CT_BYTES) begin
            ch = $fgetc(f);
            if (ch == -1) break;
            ct_buf[nread] = ch[7:0];
            nread = nread + 1;
        end
        $fclose(f);
        $display("[%0t] Read %0d CT bytes", $time, nread);

        // Secret key
        f = $fopen("/home/benjamin/Master-thesis/hqc-data-generator/secret_key.bin", "rb");
        if (f == 0) $fatal(1, "Failed to open test-privatekey.bin");
        nread = 0;
        while (nread < SK_BYTES) begin
            ch = $fgetc(f);
            if (ch == -1) break;
            sk_buf[nread] = ch[7:0];
            nread = nread + 1;
        end
        $fclose(f);
        $display("[%0t] Read %0d SK bytes", $time, nread);

        // --------------- Backdoor write DUT memories ---------------
        // CT: 8-bit entries (sequential, no endianness issues)
        for (i = 0; i < CT_BYTES; i = i + 1)
            dut.loader.ct_mem[i] = ct_buf[i];

        // SK: 64-bit entries (BIG-ENDIAN pack)
        // Each 64-bit word gets 8 consecutive file bytes b0..b7 into [63:56]..[7:0]
        for (i = 0; i < SK_BYTES; i = i + 8)
            dut.loader.sk_mem[i>>3] = pack64_le(
                sk_buf[i+0], sk_buf[i+1], sk_buf[i+2], sk_buf[i+3],
                sk_buf[i+4], sk_buf[i+5], sk_buf[i+6], sk_buf[i+7]
            );

        $display("[%0t] Backdoor CT/SK memories loaded (BE for SK).", $time);
        show_first_bytes();

        // --------------- Let wrapper start decap naturally ---------------
        // We ONLY pulse uart_done one cycle so wrapper leaves LOAD -> DECAP.
        repeat (10) @(posedge clk);
        force dut.uart_done = 1'b1;   // emulate "loader finished"
        @(posedge clk);
        force dut.uart_done = 1'b0;
        release dut.uart_done;

        $display("[%0t] uart_done pulsed; waiting for real dec_done...", $time);

        // --------------- Wait for the REAL dec_done ---------------
        fork
            begin : wait_done
                wait (dut.dec_done === 1'b1);
                $display("[%0t] dec_done asserted.", $time);
            end
            begin : timeout
                #(200_000_000); // 200 ms sim time @ 1ns timescale
                $display("[%0t] TIMEOUT waiting for dec_done.", $time);
            end
        join_any
        disable fork;

        // --------------- Inspect the produced data ---------------
        if (^dut.ss_mem[0] !== 1'bx) begin
            $display("ss_mem[0] = 0x%016h  (bytes MSB..LSB: %02h %02h %02h %02h %02h %02h %02h %02h)",
                     dut.ss_mem[0],
                     dut.ss_mem[0][63:56], dut.ss_mem[0][55:48], dut.ss_mem[0][47:40], dut.ss_mem[0][39:32],
                     dut.ss_mem[0][31:24], dut.ss_mem[0][23:16], dut.ss_mem[0][15:8],  dut.ss_mem[0][7:0]);
        end else begin
            $display("Note: ss_mem not visible (optimized?)");
        end

        #100000;
        $stop;
    end

    // Wave dump
    initial begin
        $dumpfile("tb_hqc_decap_wrapper.vcd");
        $dumpvars(0, tb_hqc_decap_wrapper);
    end

endmodule
