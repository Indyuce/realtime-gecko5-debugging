// Unused top module, can be used for simulation purposes
module top(
    input wire          clock12MHz,
                        clock50MHz,
    // input wire TCK,
    // input wire TMS,
    // input wire TDI,
    // output wire TDO,
    output wire [9:0] red,
    output wire [9:0] blue,
    output wire [9:0] green,
    output wire [3:0] rgbRow
);

    wire s_TDO, s_JTDI, s_JTCK, s_JRTI2, s_JRTI1, s_JSHIFT, s_JUPDATE, s_JRSTN, s_JCE2, s_JCE1;
    wire s_JTDO1, s_JTDO2;

    JTAGG JTAGG(
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
        .system_clock(JTCK), // Assuming JTCK is the system clock
        .address_dataOUT(),
        .byte_enableOUT(),
        .busrt_sizeOUT(),
        .read_n_writeOUT(),
        .begin_transactionOUT(),
        .end_transactionOUT(),
        .data_validOUT(),
        .busyOUT(),
        .address_dataIN(32'b0),
        .end_transactionIN(1'b0),
        .data_validIN(1'b0),
        .busyIN(1'b0),
        .errorIN(1'b0),
        .request(),
        .granted(1'b0),
        .rgbRow(rgbRow),
        .red(red),
        .blue(blue),
        .green(green)
    );
    

endmodule
