

// // 
// // Module: uart_tx 
// // 
// // Notes:
// // - UART transmitter module.
// //

// module uart_tx(
// input  wire         clk         , // Top level system clock input.
// input  wire         resetn      , // Asynchronous active low reset.
// output wire         uart_txd    , // UART transmit pin.
// output wire         uart_tx_busy, // Module busy sending previous item.
// input  wire         uart_tx_en  , // Send the data on uart_tx_data
// input  wire [PAYLOAD_BITS-1:0]   uart_tx_data  // The data to be sent
// );

// // --------------------------------------------------------------------------- 
// // External parameters.
// // 

// //
// // Input bit rate of the UART line.
// parameter   BIT_RATE        = 115200; // bits / sec
// parameter   CLK_HZ          =    30_000_000;

// //
// // Number of data bits recieved per UART packet.
// parameter   PAYLOAD_BITS    = 8;

// //
// // Number of stop bits indicating the end of a packet.
// parameter   STOP_BITS       = 1;

// // --------------------------------------------------------------------------- 
// // Internal parameters.
// // 

// //
// // Number of clock cycles per uart bit.
// localparam integer CYCLES_PER_BIT = CLK_HZ / BIT_RATE;
// //
// // Size of the registers which store sample counts and bit durations.
// localparam       COUNT_REG_LEN      = 1+$clog2(CYCLES_PER_BIT);

// // --------------------------------------------------------------------------- 
// // Internal registers.
// // 

// //
// // Internally latched value of the uart_txd line. Helps break long timing
// // paths from the logic to the output pins.
// reg txd_reg;

// //
// // Storage for the serial data to be sent.
// reg [PAYLOAD_BITS-1:0] data_to_send;

// //
// // Counter for the number of cycles over a packet bit.
// reg [COUNT_REG_LEN-1:0] cycle_counter;

// //
// // Counter for the number of sent bits of the packet.
// reg [3:0] bit_counter;

// //
// // Current and next states of the internal FSM.
// reg [2:0] fsm_state;
// reg [2:0] n_fsm_state;

// localparam FSM_IDLE = 0;
// localparam FSM_START= 1;
// localparam FSM_SEND = 2;
// localparam FSM_STOP = 3;


// // --------------------------------------------------------------------------- 
// // FSM next state selection.
// // 

// assign uart_tx_busy = fsm_state != FSM_IDLE;
// assign uart_txd     = txd_reg;

// wire next_bit = (cycle_counter == CYCLES_PER_BIT-1);
// wire payload_done = bit_counter   == PAYLOAD_BITS  ;
// wire stop_done    = bit_counter   == STOP_BITS && fsm_state == FSM_STOP;

// //
// // Handle picking the next state.
// always @(*) begin : p_n_fsm_state
//     case(fsm_state)
//         FSM_IDLE : n_fsm_state = uart_tx_en   ? FSM_START: FSM_IDLE ;
//         FSM_START: n_fsm_state = next_bit     ? FSM_SEND : FSM_START;
//         FSM_SEND : n_fsm_state = payload_done ? FSM_STOP : FSM_SEND ;
//         FSM_STOP : n_fsm_state = stop_done    ? FSM_IDLE : FSM_STOP ;
//         default  : n_fsm_state = FSM_IDLE;
//     endcase
// end

// // --------------------------------------------------------------------------- 
// // Internal register setting and re-setting.
// // 

// //
// // Handle updates to the sent data register.
// integer i = 0;
// always @(posedge clk) begin : p_data_to_send
//     if(!resetn) begin
//         data_to_send <= {PAYLOAD_BITS{1'b0}};
//     end else if(fsm_state == FSM_IDLE && uart_tx_en) begin
//         data_to_send <= uart_tx_data;
//     end else if(fsm_state       == FSM_SEND       && next_bit ) begin
//         for ( i = PAYLOAD_BITS-2; i >= 0; i = i - 1) begin
//             data_to_send[i] <= data_to_send[i+1];
//         end
//     end
// end


// //
// // Increments the bit counter each time a new bit frame is sent.
// always @(posedge clk) begin : p_bit_counter
//     if(!resetn) begin
//         bit_counter <= 4'b0;
//     end else if(fsm_state != FSM_SEND && fsm_state != FSM_STOP) begin
//         bit_counter <= {COUNT_REG_LEN{1'b0}};
//     end else if(fsm_state == FSM_SEND && n_fsm_state == FSM_STOP) begin
//         bit_counter <= {COUNT_REG_LEN{1'b0}};
//     end else if(fsm_state == FSM_STOP&& next_bit) begin
//         bit_counter <= bit_counter + 1'b1;
//     end else if(fsm_state == FSM_SEND && next_bit) begin
//         bit_counter <= bit_counter + 1'b1;
//     end
// end


// //
// // Increments the cycle counter when sending.
// always @(posedge clk) begin : p_cycle_counter
//     if(!resetn) begin
//         cycle_counter <= {COUNT_REG_LEN{1'b0}};
//     end else if(next_bit) begin
//         cycle_counter <= {COUNT_REG_LEN{1'b0}};
//     end else if(fsm_state == FSM_START || 
//                 fsm_state == FSM_SEND  || 
//                 fsm_state == FSM_STOP   ) begin
//         cycle_counter <= cycle_counter + 1'b1;
//     end
// end


// //
// // Progresses the next FSM state.
// always @(posedge clk) begin : p_fsm_state
//     if(!resetn) begin
//         fsm_state <= FSM_IDLE;
//     end else begin
//         fsm_state <= n_fsm_state;
//     end
// end


// //
// // Responsible for updating the internal value of the txd_reg.
// always @(posedge clk) begin : p_txd_reg
//     if(!resetn) begin
//         txd_reg <= 1'b1;
//     end else if(fsm_state == FSM_IDLE) begin
//         txd_reg <= 1'b1;
//     end else if(fsm_state == FSM_START) begin
//         txd_reg <= 1'b0;
//     end else if(fsm_state == FSM_SEND) begin
//         txd_reg <= data_to_send[0];
//     end else if(fsm_state == FSM_STOP) begin
//         txd_reg <= 1'b1;
//     end
// end

// endmodule

module uart_tx(
  input  wire clk,
  input  wire resetn,          // active-low
  output wire uart_txd,
  output wire uart_tx_busy,
  input  wire uart_tx_en,
  input  wire [PAYLOAD_BITS-1:0] uart_tx_data
);
parameter BIT_RATE=115_200, CLK_HZ=50_000_000, PAYLOAD_BITS=8, STOP_BITS=1;

localparam integer CYCLES_PER_BIT = CLK_HZ / BIT_RATE;
localparam integer COUNT_W  = 1 + $clog2(CYCLES_PER_BIT);
localparam integer BITCNT_W = (PAYLOAD_BITS<=2)?2:1+$clog2(PAYLOAD_BITS);

reg [2:0] state, nstate;
localparam S_IDLE=0,S_START=1,S_SEND=2,S_STOP=3;

reg [COUNT_W-1:0]  cyc;
wire next_bit = (cyc==CYCLES_PER_BIT-1);

reg [BITCNT_W-1:0] bitc;
wire payload_last = (bitc==PAYLOAD_BITS-1);

reg [$clog2(STOP_BITS+1)-1:0] stopc;
wire stop_last = (stopc==STOP_BITS-1);

reg [PAYLOAD_BITS-1:0] sh;
reg tx;

assign uart_txd     = tx;
assign uart_tx_busy = (state!=S_IDLE);

always @(*) begin
  case (state)
    S_IDLE : nstate = uart_tx_en            ? S_START : S_IDLE;
    S_START: nstate = next_bit              ? S_SEND  : S_START;
    S_SEND : nstate = (next_bit && payload_last) ? S_STOP  : S_SEND;
    S_STOP : nstate = (next_bit && stop_last)    ? S_IDLE  : S_STOP;
    default: nstate = S_IDLE;
  endcase
end

// bit-time
always @(posedge clk) begin
  if(!resetn) cyc <= 0;
  else if(state==S_START||state==S_SEND||state==S_STOP)
    cyc <= next_bit ? 0 : (cyc+1'b1);
  else cyc <= 0;
end

// data shift
always @(posedge clk) begin
  if(!resetn) sh <= 0;
  else if(state==S_IDLE && uart_tx_en) sh <= uart_tx_data;
  else if(state==S_SEND && next_bit)   sh <= {1'b0, sh[PAYLOAD_BITS-1:1]};
end

// data bit counter
always @(posedge clk) begin
  if(!resetn) bitc <= 0;
  else if(state==S_START && next_bit)             bitc <= 0;
  else if(state==S_SEND && next_bit && !payload_last) bitc <= bitc + 1'b1;
  else if(state==S_SEND && next_bit &&  payload_last) bitc <= 0;
end

// stop counter
always @(posedge clk) begin
  if(!resetn) stopc <= 0;
  else if(state==S_STOP && next_bit && !stop_last) stopc <= stopc + 1'b1;
  else if(state!=S_STOP) stopc <= 0;
end

// state
always @(posedge clk) begin
  if(!resetn) state <= S_IDLE;
  else        state <= nstate;
end

// line
always @(posedge clk) begin
  if(!resetn)               tx <= 1'b1;
  else case (state)
    S_IDLE  : tx <= 1'b1;
    S_START : tx <= 1'b0;
    S_SEND  : tx <= sh[0];
    S_STOP  : tx <= 1'b1;
  endcase
end

endmodule
