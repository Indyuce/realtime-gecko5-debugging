module ipcore(
    input wire JTCK,
    input wire JTDI,
    input wire JRTI1,
    input wire JRTI2,
    input wire JSHIFT,
    input wire JUPDATE,
    input wire JRSTN,
    input wire JCE1,
    input wire JCE2,
    output wire JTD1,
    output wire JTD2,

    // Chain1 outputs
    // pingpong buffer connections
    output wire [8:0] pp_address,
    output wire pp_writeEnable,
    output wire [31:0] pp_dataIn,
    input wire [31:0] pp_dataOut,
    output wire pp_switch,

    /// Connection with the DMA
    input wire system_clk,
    output wire [31:0] DMA_address,
    output wire DMA_launch_write,
    output wire DMA_launch_read,
    output wire DMA_launch_simple_switch,
    output wire [3:0] DMA_byte_enable,
    output wire [7:0] DMA_burst_size_OUT,
    input wire DMA_busy,
    input wire DMA_operation_done,
    input wire [7:0] DMA_block_size_IN,
    output wire [7:0] DMA_block_size_OUT,

    // Debugging and status signals
    output wire [5:0] status_reg_out
);

wire s_JTDI_1, s_JTDI_2;

// Driving JTDI lines based on JCE signals
assign s_JTDI_1 = (JCE1) ? JTDI : 1'bz;
assign s_JTDI_2 = (JCE2) ? JTDI : 1'bz;

// Here only chain1 is used, chain2 is not used in this design
chain1 instruction_chain1 (
    .JTCK(JTCK),
    .JTDI(s_JTDI_1),
    .JRTI1(JRTI1),
    .JSHIFT(JSHIFT),
    .JUPDATE(JUPDATE),
    .JRSTN(JRSTN),
    .JCE1(JCE1),
    .JTD1(JTD1),
    .pp_address(pp_address),
    .pp_writeEnable(pp_writeEnable),
    .pp_dataIn(pp_dataIn),
    .pp_dataOut(pp_dataOut),
    .pp_switch(pp_switch),
    .system_clk(system_clk),
    .DMA_address(DMA_address),
    .DMA_launch_read(DMA_launch_read),
    .DMA_launch_write(DMA_launch_write),
    .DMA_launch_simple_switch(DMA_launch_simple_switch),
    .DMA_burst_size_OUT(DMA_burst_size_OUT),
    .DMA_byte_enable(DMA_byte_enable),
    .DMA_busy(DMA_busy),
    .DMA_operation_done(DMA_operation_done), 
    .DMA_block_size_IN(DMA_block_size_IN),
    .DMA_block_size_OUT(DMA_block_size_OUT),
    .status_reg_out(status_reg_out)
);



// Not used here
// chain2 instruction_chain2 (
//     .JTCK(JTCK),
//     .JTDI(s_JTDI_2),
//     .JRTI2(JRTI2),
//     .JSHIFT(JSHIFT),
//     .JUPDATE(JUPDATE),
//     .JRSTN(JRSTN),
//     .JCE2(JCE2),
//     .JTD2(JTD2),
//     .rgbRow()
// );

endmodule