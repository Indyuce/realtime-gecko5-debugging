// NOT IN USE ANYMORE

module jtagg_patch(

    input wire JTCK,
    input wire JRTI,
    input wire JSHIFT,
    input wire JUPDATE,
    input wire JRSTN,
    input wire JCE,

    output wire rst_o,
    output wire capture_dr,
    output wire pause_dr,
    output wire debug_select
);

    /*
     * First interface problem:
     * We need a signal high when 0x32 is loaded in IR.
     * Solution so far: IMPORTANT HYPOTHESIS IS THAT
     * ONCE THE DEBUG CHAIN IS SELECTED, NO OTHER CHAIN
     * IS USED LATER ON BEFORE SYSTEM RESET.
     */ 
    reg reg_debugSelect = 1'b0;

    always @(posedge JTCK) begin
        reg_debugSelect      <= (JRTI | JCE) ? 1'b1 : reg_debugSelect;
    end

    assign debug_select = reg_debugSelect;

   /*
    * Second problem (accurate fix)
    * 
    * JTAGG provides JCEn (Clock Cnable n) which is
    * high when TAP is either in CAPTURE or SHIFT and
    * when 0x3n is in IR. We only need when CAPTURE is high,
    * not SHIFT.
    * 
    * Note:
    * JSHIFT is HIGH on SHIFT-DR with either ER1 or ER2 in IR,
    * but if ER2 is in IR then JCE is not on anyway.
    */
    assign capture_dr = JCE && !JSHIFT;

    // Active high to active low.
    assign rst_o = ~JRSTN;

    assign pause_dr = 1'b0; // Does nothing according to docs

endmodule