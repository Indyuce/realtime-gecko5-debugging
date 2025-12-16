`timescale 1ns/1ps

`define SIMULATE 1

module tb_reg_read;
    
    //////////////////////////////////////////////////////////////////////////
    // JTAG signals
    //////////////////////////////////////////////////////////////////////////
    reg TCK;
    reg TMS;
    reg TDI;
    wire TDO;
    
    //////////////////////////////////////////////////////////////////////////
    // SoC signals
    //////////////////////////////////////////////////////////////////////////
    reg sys_clk;
    reg sys_reset;

    //////////////////////////////////////////////////////////////////////////
    // Emulated bus & arbiter signals
    //////////////////////////////////////////////////////////////////////////




    //////////////////////////////////////////////////////////////////////////
    // DUT
    //////////////////////////////////////////////////////////////////////////

    localparam drlen = 53'd8;

    reg [128:0] reg_tdo_out;

    // Instantiate DUT
    jtag_if dut (
        .TCK(TCK),
        .TMS(TMS),
        .TDI(TDI),
        .TDO(TDO),

        // CPU 0 signals
        .cpu0_clk_i(sys_clk)
    );
    //////////////////////////////////////////////////////////////////////////
    // Start of testbench
    //////////////////////////////////////////////////////////////////////////

    // Clock generation : 4ns period
    initial begin
        TCK = 0;
        forever #2 TCK = ~TCK;
    end
    // system clock, 10x faster
    initial begin
        sys_clk = 0;
        forever #0.2 sys_clk = ~sys_clk;
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
    task send_dr(input [128:0] dr_value, input integer dr_len);
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

            reg_tdo_out[i-1] = TDO; // !! SKIP FIRST STATUS BIT !!
        end
        // Terminate sequence
        jtag_clock(1, 0); // -> Update-DR
        jtag_clock(0, 0); // -> Run-Test/Idle
    end
    endtask

    //////////////////////////////////////////////////////////////////////////
    // Setup burst command
    //////////////////////////////////////////////////////////////////////////
    task setup_burst(input [3:0] opcode, input [31:0] address, input [15:0] count);
        logic [52:0] cmd; // bits [52:0] total 53 bits
    begin

            // biu will not be happy
            if (count == 16'd0) begin
                $error("setup_burst: word count must be > 0");
            end

            // Build command
            cmd = 53'h0;                // submodule command
            cmd[51:48] = opcode;        // opcode 48:51
            cmd[47:16] = address;       // address 16:47 (32 bits)
            cmd[15:0]  = count;         // count 0:15

            // send dr task
            send_dr(cmd, 53);
    end
    endtask

    //////////////////////////////////////////////////////////////////////////
    // Main seq
    //////////////////////////////////////////////////////////////////////////
    initial begin
        $dumpfile("tb_reg_read.vcd");
        $dumpvars(0, tb_reg_read);


        //////////////////////////////////
        // Init
        //////////////////////////////////

        reg_tdo_out = 0; // reset tdo register

        // Init
        sys_reset = 1;
        TMS = 1;
        TDI = 0;
        repeat(5) @(posedge TCK); // reset TAP (>=5 cycles with TMS=1)
        TMS = 0;
        sys_reset = 0;
        repeat(10) @(posedge TCK); // Idle

        //////////////////////////////////
        // Select debug controler
        //////////////////////////////////

        send_ir(8'h32); // Select IR 0x32
        repeat(10) @(posedge TCK); // Idle

        //////////////////////////////////
        // Select CPU0 submodule
        //////////////////////////////////
        send_dr(3'b101, 3);
        repeat(10) @(posedge TCK); // Idle

        //////////////////////////////////
        // Burst setup command
        //////////////////////////////////
        // opcode 0x7    = burst read 32-bit words
        // 16'd1         = read/write 1 word
        // 32'h0000_1000 = address to read from/write to
        setup_burst(4'h7, 32'h0000_0000, 16'd1);

        repeat(20) @(posedge sys_clk); // Slave takes some time to respond

        //////////////////////////////////
        // Slave returns word read
        //////////////////////////////////

        repeat(3) @(posedge TCK); // Idle

        //////////////////////////////////
        // Burst-read DR scan
        //////////////////////////////////
        send_dr(72'h0, 72); // read 72 bits

        repeat(20) @(posedge TCK); // Idle

        // end of test

        $finish;
    end

endmodule
