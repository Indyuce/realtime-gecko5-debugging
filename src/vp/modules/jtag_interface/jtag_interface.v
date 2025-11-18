module jtag_interface(
    // input wire TCK,
    // input wire TMS,
    // input wire TDI,
    // output wire TDO,

    // Leds and RGB signals for debugging purposes
    output wire [9:0] red,
    output wire [9:0] blue,
    output wire [9:0] green,
    output wire [3:0] rgbRow,
    
    // Bus Interface Signals
    input wire system_clock,
    input wire system_reset,
    output wire [31:0] address_dataOUT,
    output wire [3:0] byte_enableOUT,
    output wire [7:0] burstSizeOUT,
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

    // Arbitrer Signals
    output wire request,
    input wire busGranted
);

    wire s_TDO, s_JTDI, s_JTCK, s_JRTI2, s_JRTI1, s_JSHIFT, s_JUPDATE, s_JRSTN, s_JCE2, s_JCE1;
    wire s_JTDO1, s_JTDO2;

    JTAGG JTAGG(
        // If those 4 lines are uncommented, our JTAGG module will be used and will not be connected to actual JTAG pins
        // Can be uncommented if for simulation purposes
        // .TCK(TCK),
        // .TMS(TMS),
        // .TDI(TDI),
        // .TDO(s_TDO),
        .JTDO2(s_JTDO2),
        .JTDO1(s_JTDO1),
        .JTDI(s_JTDI),
        .JTCK(s_JTCK),
        .JRTI2(s_JRTI2),
        .JRTI1(s_JRTI1),
        .JSHIFT(s_JSHIFT),
        .JUPDATE(s_JUPDATE),
        .JRSTN(s_JRSTN),
        .JCE2(s_JCE2),
        .JCE1(s_JCE1)
    );

    jtag_support jtag_support_inst (
        .JTCK(s_JTCK),
        .JTDI(s_JTDI),
        .JSHIFT(s_JSHIFT),
        .JUPDATE(s_JUPDATE),
        .JRSTN(s_JRSTN),
        .JCE1(s_JCE1),
        .JCE2(s_JCE2),
        .JRTI1(s_JRTI1),
        .JRTI2(s_JRTI2),
        .JTDO1(s_JTDO1),
        .JTDO2(s_JTDO2),
        .system_clock(system_clock), 
        .system_reset(system_reset),
        .address_dataOUT(address_dataOUT),
        .byte_enableOUT(byte_enableOUT),
        .burst_sizeOUT(burstSizeOUT),
        .read_n_writeOUT(read_n_writeOUT),
        .begin_transactionOUT(begin_transactionOUT),
        .end_transactionOUT(end_transactionOUT),
        .data_validOUT(data_validOUT),
        .busyOUT(busyOUT),
        .address_dataIN(address_dataIN),
        .end_transactionIN(end_transactionIN),
        .data_validIN(data_validIN),
        .busyIN(busyIN),
        .errorIN(errorIN),
        .request(request),
        .granted(busGranted),
        .rgbRow(rgbRow),
        .red(red),
        .blue(blue),
        .green(green)
    );
    
endmodule