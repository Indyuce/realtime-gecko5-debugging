`timescale 1ps/1ps

module tb_jtagsupport;

    // Testbench signals
    reg JTCK;
    reg JTDI;
    reg JSHIFT;
    reg JUPDATE;
    reg JRSTN;
    reg JCE1;
    reg JCE2;
    reg JRTI1;
    reg JRTI2;
    wire JTDO1;
    wire JTDO2;

    reg [31:0] address_dataIN;
    reg end_transactionIN;
    reg data_validIN;
    reg busyIN;
    reg errorIN;

    wire [31:0] address_dataOUT;
    wire [3:0] byte_enableOUT;
    wire [7:0] busrt_sizeOUT;
    wire read_n_writeOUT;
    wire begin_transactionOUT;
    wire end_transactionOUT;
    wire data_validOUT;
    wire busyOUT;

    wire request;
    reg granted;
    reg [31:0] memory_0x55555555;

    reg system_clock;

    // Instantiate the DUT (Device Under Test)
    jtag_support dut (
        .JTCK(JTCK),
        .JTDI(JTDI),
        .JSHIFT(JSHIFT),
        .JUPDATE(JUPDATE),
        .JRSTN(JRSTN),
        .JCE1(JCE1),
        .JCE2(JCE2),
        .JRTI1(JRTI1),
        .JRTI2(JRTI2),
        .JTDO1(JTDO1),
        .JTDO2(JTDO2),
        .system_clock(system_clock), // Assuming JTCK is the system clock
        .system_reset(~JRSTN),
        .address_dataOUT(address_dataOUT),
        .byte_enableOUT(byte_enableOUT),
        .burst_sizeOUT(busrt_sizeOUT),
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
        .granted(granted)
    );

    // Clock generation
    initial begin
        JTCK = 0;
        forever #2 JTCK = ~JTCK; // 100 MHz clock
    end

    initial begin
        system_clock = 0;
        forever #1 system_clock = ~system_clock; // 100 MHz clock
    end

    integer i;
    task sendInstruction(input [35:0] instruction);
        begin
            JRTI1 = 0;
            #8;
            JCE1 = 1;
            #4;
            for (i = 0; i < 36; i = i + 1) begin
                JTDI = instruction[i];
                JSHIFT = 1;
                #4;
            end
            JCE1 = 0;
            JSHIFT = 0;
            #8;
            JUPDATE = 1;
            #4;
            JUPDATE = 0;
            JRTI1 = 1;
            #4;
        end
    endtask


    initial begin
        // Initialize signals
        JTDI = 0;
        JSHIFT = 0;
        JUPDATE = 0;
        JRSTN = 1;
        JCE1 = 0;
        JCE2 = 0;
        JRTI1 = 1;
        JRTI2 = 1;
        granted = 0;
        busyIN = 0;
        errorIN = 0;
        data_validIN = 0;
        end_transactionIN = 0;
        address_dataIN = 0;
        memory_0x55555555 = 32'hDEADBEEF;

        // Reset the DUT
        #8;
        JRSTN = 0;
        #8;
        JRSTN = 1;
        #8;

        // Write in the address register
        sendInstruction(36'b010101010101010101010101010101010001);
        $display("Value of address reg: %b", dut.ipcore.instruction_chain1.address_reg);

        sendInstruction(36'b11110010);
        $display("Value of byte enable reg: %b", dut.ipcore.instruction_chain1.byte_enable_reg);

        sendInstruction(36'b100011);
        // sendInstruction(36'b11000000011);
        $display("Value of burst size reg: %b", dut.ipcore.instruction_chain1.busrt_size_reg);

        // Read the status reg of the ipcore
        sendInstruction(36'b00000);

        // Start sending data
        sendInstruction(36'hABCDEF8);

        sendInstruction(36'hAAAAAA8);
        sendInstruction(36'hBBBBBB8);
        sendInstruction(36'hCCCCCC8);
        sendInstruction(36'hDDDDDD8);
        sendInstruction(36'hEEEEEE8);
        sendInstruction(36'hFFFFFF8);


        #80;
        // Write at address 0x55555555
        #50;
        sendInstruction(36'b01010);
        #16;
        busyIN = 1; // Simulate busy state
        #20;
        busyIN = 0; // Clear busy state
        #4;
        busyIN = 1; // Simulate busy state
        #16;
        busyIN = 0; // Clear busy state



        #160;

        // // Read from address 0x55555555
        // sendInstruction(36'hFB);

        // #40;
        // data_validIN = 1;

        // #120;
        // data_validIN = 0;
        // end_transactionIN = 1;

        // #4;
        // end_transactionIN = 0;

        // #160;

        

        $finish;

    end

    initial begin
        $dumpfile("test_jtagsupport.vcd");
        $dumpvars(0, tb_jtagsupport);
    end

    always @(posedge system_clock) begin
        if (data_validOUT == 1'b1) begin
            memory_0x55555555 = 32'hFFFFFFFF;
            $display("Data written to memory: %h at clock cycel : %d", address_dataOUT, $time);
        end

    end
    always @(posedge system_clock) begin
        if (end_transactionOUT) begin
            $display("End transaction signal received");
        end
    end

    always @(posedge JTCK) begin
        if (request) begin
            granted = 1;
        end else begin
            granted = 0;
        end
    end

    always @(posedge system_clock) begin
        if (JRSTN == 1'b0) begin
            address_dataIN <= 32'hA0000000;
        end else if (data_validIN == 1'b1) begin
            address_dataIN <= address_dataIN + 1;
        end
    end

endmodule