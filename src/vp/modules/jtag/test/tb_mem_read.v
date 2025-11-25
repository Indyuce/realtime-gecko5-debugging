`timescale 1ns/1ps

`define SIMULATE 1

module tb_select_module;
    
    reg TCK;
    reg TMS;
    reg TDI;
    wire TDO;

    localparam drlen = 32'd8;

    reg [drlen-1:0] reg_tdo_out;
    wire [1:0] s_tdo_module_out = reg_tdo_out[1:0];

    // Instantiate DUT
    jtag_if dut (
        .TCK(TCK),
        .TMS(TMS),
        .TDI(TDI),
        .TDO(TDO)
    );

    // Clock generation : 4ns period
    initial begin
        TCK = 0;
        forever #2 TCK = ~TCK;
    end

    // Util task
    task jtag_clock(input reg tms_val, input reg tdi_val);
    begin
        TMS = tms_val;
        TDI = tdi_val;
        @(posedge TCK);
    end
    endtask

    //////////////////////////////////////////////////////////////////////////
    // Perform IR (instruction register)
    //////////////////////////////////////////////////////////////////////////
    task send_ir(input [7:0] ir_value);
        integer i;
    begin
        // From Test-Logic-Reset to Shift-IR
        jtag_clock(1, 0); // -> Select-DR-Scan
        jtag_clock(1, 0); // -> Select-IR-Scan
        jtag_clock(0, 0); // -> Capture-IR
        jtag_clock(0, 0); // -> Shift-IR

        // Send bit-by-bit, LSB first
        // Last bit with TMS=1 (exit1-ir) otherwise will stay in shift-ir
        for (i = 0; i < 8; i = i + 1) begin
            jtag_clock(i == 7, ir_value[i]);
        end
        // Terminate sequence
        jtag_clock(1, 0); // -> Update-IR
        jtag_clock(0, 0); // -> Run-Test/Idle
    end
    endtask

    //////////////////////////////////////////////////////////////////////////
    // Perform a DR scan (both read and write)
    //////////////////////////////////////////////////////////////////////////
    task send_dr(input [63:0] dr_value, input integer dr_len);
        integer i;
    begin
        reg_tdo_out = 0;

        // From Run-Test/Idle to Shift-DR
        jtag_clock(1, 0); // -> Select-DR-Scan
        jtag_clock(0, 0); // -> Capture-DR
        jtag_clock(0, 0); // -> Shift-DR

        // Send bit-by-bit, LSB first
        // Last bit with TMS=1 (exit1-dr) otherwise will stay in shift-dr
        for (i = 0; i < dr_len; i = i + 1) begin
            jtag_clock(i == dr_len - 1, dr_value[i]);

            // TODO probleme avec 
            @(negedge TCK);
            reg_tdo_out[i] = TDO;
        end
        // Terminate sequence
        jtag_clock(1, 0); // -> Update-DR
        jtag_clock(0, 0); // -> Run-Test/Idle
    end
    endtask

    //////////////////////////////////////////////////////////////////////////
    // Main seq
    //////////////////////////////////////////////////////////////////////////
    initial begin
        $dumpfile("tb_select_module.vcd");
        $dumpvars(0, tb_select_module);

        reg_tdo_out = 0;

        // Init
        TMS = 1;
        TDI = 0;
        repeat(5) @(posedge TCK); // reset TAP (>=5 cycles avec TMS=1)
        TMS = 0;

        repeat(10) @(posedge TCK); // Idle

        send_ir(8'h38); // Envoyer IR 0h38
        repeat(10) @(posedge TCK); // Idle
        send_ir(8'h32); // Envoyer IR 0h32

        repeat(10) @(posedge TCK); // Idle

        send_dr(3'b110, 3);
        repeat(10) @(posedge TCK); // Idle
        send_dr(3'b100, 3);
        repeat(10) @(posedge TCK); // Idle
        send_dr(3'b101, 3);

        repeat(10) @(posedge TCK); // Idle

        $finish;
    end

endmodule
