module jtag_support(
    // JTAG signals
    input wire JTCK, 
    input wire  JTDI, 
    input wire JSHIFT, 
    input wire JUPDATE, 
    input wire  JRSTN,
    input wire JCE1, 
    input wire JCE2, 
    input wire JRTI1, 
    input wire JRTI2, 
    output  wire JTDO1, 
    output  wire JTDO2,

    // Bus architecture signals
    input wire system_clock,
    input wire system_reset,
    output wire [31:0] address_dataOUT,
    output wire [3:0] byte_enableOUT,
    output wire [7:0] burst_sizeOUT,
    output wire read_n_writeOUT,
    output wire begin_transactionOUT,
    output wire end_transactionOUT,
    output wire data_validOUT,
    output wire busyOUT,
    input wire [31:0] address_dataIN,
    input wire end_transactionIN,
    input wire data_validIN,
    input wire busyIN,
    input wire errorIN,

    // arbitrer signals
    output wire request,
    input wire granted,

    // Visual clues
    output [3:0] rgbRow,
    output [9:0] red,
    output [9:0] blue,
    output [9:0] green
);

wire [8:0] s_pp_address_ipcore;
wire s_pp_writeEnable_ipcore;
wire [31:0] s_pp_dataIn_ipcore;
wire [31:0] s_pp_dataOut_ipcore;
wire s_pp_switch_ipcore;

wire [31:0] s_DMA_address;
wire s_DMA_launch_write;
wire s_DMA_launch_read;
wire s_DMA_launch_simple_switch;
wire [3:0] s_DMA_byte_enable;
wire [7:0] s_DMA_burst_size_OUT;
wire [7:0] s_DMA_block_size_IN;
wire [7:0] s_DMA_block_size_OUT;
wire s_DMA_busy;
wire s_DMA_operation_done;

wire [8:0] s_pp_address_dma;
wire s_pp_writeEnable_dma;
wire [31:0] s_pp_dataIn_dma;
wire [31:0] s_pp_dataOut_dma;

wire [5:0] s_status_reg_out;
wire [7:0] s_dma_cur_state;

wire sync_s_dma_data_ready;
wire sync_s_dma_readReady;
wire [3:0] sync_s_dma_byte_enable;
wire [31:0] sync_s_dma_address;
wire sync_switch_ready;

wire s_reset, s_nreset;
assign s_nreset = JRSTN & ~system_reset;
assign s_reset = ~s_nreset;

// Debugging signals
assign rgbRow = 4'b0000;
assign green = {~s_DMA_operation_done, 9'h1FF};
// assign green = {~s_status_reg_out};
// assign green = {~s_dma_cur_state};

// instantiate the ipcore module
ipcore ipcore (
    .JTCK(JTCK),
    .JTDI(JTDI),
    .JRTI1(JRTI1),
    .JRTI2(JRTI2),
    .JSHIFT(JSHIFT),
    .JUPDATE(JUPDATE),
    .JRSTN(JRSTN),
    .JCE1(JCE1),
    .JCE2(JCE2),
    .JTD1(JTDO1),
    .JTD2(JTDO2),

    // Chain1 outputs
    .pp_address(s_pp_address_ipcore), 
    .pp_writeEnable(s_pp_writeEnable_ipcore), 
    .pp_dataIn(s_pp_dataIn_ipcore), 
    .pp_dataOut(s_pp_dataOut_ipcore), 
    .pp_switch(s_pp_switch_ipcore), 

    // DMA connections
    .system_clk(system_clock),
    .DMA_address(s_DMA_address),
    .DMA_launch_write(s_DMA_launch_write),
    .DMA_launch_read(s_DMA_launch_read),
    .DMA_launch_simple_switch(s_DMA_launch_simple_switch),
    .DMA_byte_enable(s_DMA_byte_enable),
    .DMA_burst_size_OUT(s_DMA_burst_size_OUT),
    .DMA_busy(s_DMA_busy),
    .DMA_block_size_IN(s_DMA_block_size_OUT),
    .DMA_block_size_OUT(s_DMA_block_size_IN),
    .DMA_operation_done(s_DMA_operation_done),

    // Visual clues
    .status_reg_out(s_status_reg_out)
);

// Instantiate the Ping-Pong Buffer
pingpongbuffer pingpongbuffer_inst (
    .clockA(JTCK),
    .clockB(~system_clock),
    .addressA(s_pp_address_ipcore),
    .addressB(s_pp_address_dma),
    .writeEnableA(s_pp_writeEnable_ipcore),
    .writeEnableB(s_pp_writeEnable_dma),
    .dataInA(s_pp_dataIn_ipcore),
    .dataInB(s_pp_dataIn_dma),
    .dataOutA(s_pp_dataOut_ipcore),
    .dataOutB(s_pp_dataOut_dma),
    .switch(s_pp_switch_ipcore),
    .reset(s_nreset)
);

// Instantiate the DMA module
DMA dma_inst (
    .clock(system_clock),
    .n_reset(s_nreset),
    .ipcore_launch_write(s_DMA_launch_write),
    .ipcore_launch_read(s_DMA_launch_read),
    .ipcore_launch_simple_switch(s_DMA_launch_simple_switch),
    .ipcore_byte_enable(s_DMA_byte_enable),
    .ipcore_address(s_DMA_address),
    .ipcore_burst_size(s_DMA_burst_size_OUT),
    .ipcore_dma_busy(s_DMA_busy),
    .ipcore_operation_ended(s_DMA_operation_done),
    .ipcore_block_sizeIN(s_DMA_block_size_IN),
    .ipcore_block_sizeOUT(s_DMA_block_size_OUT),

    // Buffer interface
    .pp_address(s_pp_address_dma),
    .pp_dataIn(s_pp_dataIn_dma),
    .pp_writeEnable(s_pp_writeEnable_dma),
    .pp_dataOut(s_pp_dataOut_dma),

    // Bus interface
    .address_dataIN(address_dataIN),
    .end_transactionIN(end_transactionIN),
    .data_validIN(data_validIN),
    .busyIN(busyIN),
    .bus_errorIN(errorIN),
    .address_dataOUT(address_dataOUT),
    .byte_enableOUT(byte_enableOUT),
    .burst_sizeOUT(burst_sizeOUT),
    .read_n_writeOUT(read_n_writeOUT),
    .begin_transactionOUT(begin_transactionOUT),
    .end_transactionOUT(end_transactionOUT),
    .data_validOUT(data_validOUT),
    .busyOUT(busyOUT),

    // Arbitrer interface
    .requestTransaction(request),
    .transactionGranted(granted),

    .s_dma_cur_state(s_dma_cur_state)
);

endmodule