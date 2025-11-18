`timescale 1ns/1ps;

module tb_chain1;
    
    reg JTCK;
    reg JTDI;
    reg JRTI1;
    reg JSHIFT;
    reg JUPDATE;
    reg JRSTN;
    reg JCE1;
    reg s_dma_busy;
    reg system_clk;
    wire JTD1;

    // Instantiate the DUT (Device Under Test)
    chain1 dut (
        .JTCK(JTCK),
        .JTDI(JTDI),
        .JRTI1(JRTI1),
        .JSHIFT(JSHIFT),
        .JUPDATE(JUPDATE),
        .JRSTN(JRSTN),
        .JCE1(JCE1),
        .JTD1(JTD1),
        .pp_dataOut(32'hFFFFFFFF),
        .DMA_busy(s_dma_busy),
        .DMA_block_size_IN(8'b1),
        .system_clk(system_clk)
    );

    // Clock generation
    initial begin
        JTCK = 0; // Initialize JTCK
        system_clk = 0; // Initialize system clock
    end

    always #2 JTCK = ~JTCK;
    always #10 system_clk = ~system_clk;

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
        JTCK = 0;
        JTDI = 0;
        JRTI1 = 0;
        JSHIFT = 0;
        JUPDATE = 0;
        JRSTN = 1;
        JCE1 = 0;
        s_dma_busy = 1;

        // Reset the DUT
        #8;
        JRSTN = 0;
        #8;
        JRSTN = 1;
        #8;
        JRTI1 = 1;
        #8;


        // // try to read the address register 
        // sendInstruction(36'b100);
        // #12;
        // sendInstruction(36'b0);

        // // try to read the byte enable register and the busrt size register
        // sendInstruction(36'b101);
        // #12;
        // sendInstruction(36'b110);
        // #12;
        // sendInstruction(36'b000);

        // // Try to write in the buffer
        // sendInstruction(36'hABCDEF8);
        // sendInstruction(36'h1ABCDEF8);
        // sendInstruction(36'h2ABCDEF8);
        // sendInstruction(36'h0);


        // //Try to read from the buffer

        // sendInstruction(36'b1001);
        // #8;       
        // sendInstruction(36'b1001);
        // #8;       
        // sendInstruction(36'b1001);



        // Try to send a burst of data

        // set the burst size to 1
        sendInstruction(36'h13);

        // set the address to 0x55555555
        sendInstruction(36'h555555551);

        // Write some data in the buffer
        sendInstruction(36'hABCDEF8);
        sendInstruction(36'h1ABCDEF8);
        sendInstruction(36'h2ABCDEF8);

        // launch write operation
        sendInstruction(36'b1010);
        #20;
        s_dma_busy = 0;

        sendInstruction(36'b1100);

        #160;
        $finish;
    end

    initial begin
        $dumpfile("test_chain1.vcd");
        $dumpvars(0, tb_chain1);
    end

endmodule

    