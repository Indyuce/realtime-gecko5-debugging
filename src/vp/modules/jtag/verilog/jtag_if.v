module jtag_if (

    // Signals only for iverilog simulation
`ifdef SIMULATE
    input wire TCK,
    input wire TMS,
    input wire TDI,
    output wire TDO,
`endif

    // Debug RGB array signals
    output [9:0] red,
    output [9:0] green,
    output [9:0] blue,

    // System bus signals
    input wire         sb_clock_i,
    input wire         sb_reset_i,
    input wire         sb_grant_i,
    output wire        sb_request_o,
    output wire [31:0] sb_address_data_o,
    output wire [3:0]  sb_byte_enables_o,
    output wire [7:0]  sb_burst_size_o,
    output wire        sb_read_n_write_o,
    output wire        sb_begin_transaction_o,
    output wire        sb_end_transaction_o,
    output wire        sb_data_valid_o,
    input wire [31:0]  sb_address_data_i,
    input wire         sb_end_transaction_i,
    input wire         sb_data_valid_i,
    input wire         sb_busy_i,
    input wire         sb_error_i
);

    ///////////////////////////////////////////////////////////////////////
    //
    // JTAGG layer
    //
    ///////////////////////////////////////////////////////////////////////

    wire s_JTDI, s_JTCK, s_JRTI2, s_JRTI1, s_JSHIFT, s_JUPDATE, s_JRSTN, s_JCE2, s_JCE1;
    wire s_JTDO1, s_JTDO2;
    wire s_JPAUSE = 1'b0; // Does nothing according to docs

    JTAGG lattice_jtagg_core (

        // If those 4 lines are defined, the JTAGG module will not be connected to actual JTAG pins
        // Lines added for simulation and removed when uploading to VP
`ifdef SIMULATE
        .TCK(TCK),
        .TMS(TMS),
        .TDI(TDI),
        .TDO(TDO),    
`endif

        // !! DO NOT UNCOMMENT ANY OF THESE !!
        // Otherwise compiler will not link to JTAGG hardware primitive
        .JTDO1(s_JTDO1),
        .JTDO2(s_JTDO2),
        .JTDI(s_JTDI),
        .JTCK(s_JTCK),
        .JRTI1(s_JRTI1),
        .JRTI2(s_JRTI2),
        .JSHIFT(s_JSHIFT),
        .JUPDATE(s_JUPDATE),
        .JRSTN(s_JRSTN),
        .JCE1(s_JCE1),
        .JCE2(s_JCE2)
    );


    ///////////////////////////////////////////////////////////////////////
    //
    // Latch bus input signals to avoid
    // long critical paths and retroactive loops
    // Input signals are not exposed to layers below
    //
    ///////////////////////////////////////////////////////////////////////

    reg         _sb_grant_i;
    reg [31:0]  _sb_address_data_i;
    reg         _sb_end_transaction_i;
    reg         _sb_data_valid_i;
    reg         _sb_busy_i;
    reg         _sb_error_i;

    always @(posedge sb_clock_i) begin
        _sb_grant_i            <= sb_grant_i;
        _sb_address_data_i     <= sb_address_data_i;
        _sb_end_transaction_i  <= sb_end_transaction_i;
        _sb_data_valid_i       <= sb_data_valid_i;
        _sb_busy_i             <= sb_busy_i;
        _sb_error_i            <= sb_error_i;
    end

    ///////////////////////////////////////////////////////////////////////
    //
    // JTAGG patch layer
    //
    ///////////////////////////////////////////////////////////////////////
/*
    wire s_resetAdbg;
    wire s_pauseAdbg, s_captureAdbg;
    wire s_selectAdbg;

    jtagg_patch jtagg_patch_impl (
        .JTCK(s_JTCK),
        .JRTI(s_JRTI1),
        .JSHIFT(s_JSHIFT),
        .JUPDATE(s_JUPDATE),
        .JRSTN(s_JRSTN),
        .JCE(s_JCE1),

        .rst_o(s_resetAdbg),

        .pause_dr(s_pauseAdbg),
        .capture_dr(s_captureAdbg),

        .debug_select(s_selectAdbg)
    );
*/

    wire s_JCAPTURE = s_JCE1 && !s_JSHIFT;

    /*
     * First interface problem:
     * We need a signal high when 0x32 is loaded in IR.
     * Solution so far: IMPORTANT HYPOTHESIS IS THAT
     * ONCE THE DEBUG CHAIN IS SELECTED, NO OTHER CHAIN
     * IS USED LATER ON BEFORE SYSTEM RESET.
     */ 
    reg reg_debugSelect = 1'b0;

    always @(posedge s_JTCK) begin
        reg_debugSelect      <= (s_JRTI1 | s_JCE1) ? 1'b1 : reg_debugSelect;
    end

    wire s_selectAdbg = reg_debugSelect;

    assign s_JTDO2 = 1'b0; // better for yosys

    ///////////////////////////////////////////////////////////////////////
    //
    // ADV DEBUG layer
    //
    ///////////////////////////////////////////////////////////////////////

    adbg_top #(
        //[comment to disable wishbone module]
        //.DBG_WISHBONE_SUPPORTED("NONE"),
        .DBG_CPU0_SUPPORTED("NONE"), // TODO
        .DBG_CPU1_SUPPORTED("NONE"), // TODO
        .DBG_JSP_SUPPORTED("NONE")
    ) adbg_top_impl (

        .tck_i(s_JTCK),
        .tdi_i(s_JTDI),
        .tdo_o(s_JTDO1),
        .rst_i(~s_JRSTN),

        .shift_dr_i(s_JSHIFT),
        .pause_dr_i(1'b0),
        .update_dr_i(s_JUPDATE),
        .capture_dr_i(s_JCAPTURE),
        .debug_select_i(s_selectAdbg),

        .red(red),
        .green(green),
        .blue(blue),

        .sb_clock_i(sb_clock_i),
        .sb_reset_i(sb_reset_i),
        .sb_grant_i(_sb_grant_i),
        .sb_request_o(sb_request_o),
        .sb_address_data_o(sb_address_data_o),
        .sb_byte_enables_o(sb_byte_enables_o),
        .sb_burst_size_o(sb_burst_size_o),
        .sb_read_n_write_o(sb_read_n_write_o),
        .sb_begin_transaction_o(sb_begin_transaction_o),
        .sb_end_transaction_o(sb_end_transaction_o),
        .sb_data_valid_o(sb_data_valid_o),
        .sb_address_data_i(_sb_address_data_i),
        .sb_end_transaction_i(_sb_end_transaction_i),
        .sb_data_valid_i(_sb_data_valid_i),
        .sb_busy_i(sb_busy_i), // forced to used non latched version to avoid busy timing problem
        .sb_error_i(_sb_error_i)
/*
    //input   wb_clk_i,
    //input   wb_rst_i,
    output [31:0] wb_adr_o,
    output [31:0] wb_dat_o,
    //input [31:0]  wb_dat_i,
    output        wb_cyc_o,
    output        wb_stb_o,
    output [3:0]  wb_sel_o,
    output        wb_we_o,
    //input         wb_ack_i,
    output        wb_cab_o,
    //input         wb_err_i,
    output [2:0]  wb_cti_o,
    output [1:0]  wb_bte_o,

    // CPU signals
    input         cpu0_clk_i,
    output [31:0] cpu0_addr_o,
    input [31:0]  cpu0_data_i,
    output [31:0] cpu0_data_o,
    input         cpu0_bp_i,
    output        cpu0_stall_o,
    output        cpu0_stb_o,
    output        cpu0_we_o,
    input         cpu0_ack_i,
    output        cpu0_rst_o,


    input         cpu1_clk_i,
    output [31:0] cpu1_addr_o,
    input [31:0]  cpu1_data_i,
    output [31:0] cpu1_data_o,
    input         cpu1_bp_i,
    output        cpu1_stall_o,
    output        cpu1_stb_o,
    output        cpu1_we_o,
    input         cpu1_ack_i,
    output        cpu1_rst_o,

    input [31:0]  wb_jsp_adr_i,
    output [31:0] wb_jsp_dat_o,
    input [31:0]  wb_jsp_dat_i,
    input         wb_jsp_cyc_i,
    input         wb_jsp_stb_i,
    input [3:0]   wb_jsp_sel_i,
    input         wb_jsp_we_i,
    output        wb_jsp_ack_o,
    input         wb_jsp_cab_i,
    output        wb_jsp_err_o,
    input [2:0]   wb_jsp_cti_i,
    input [1:0]   wb_jsp_bte_i,
    output        int_o
*/
    );

    
endmodule