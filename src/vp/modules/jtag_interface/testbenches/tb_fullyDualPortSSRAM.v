`timescale 1ns / 1ps

module tb_fullyDualPortSSRAM;

    reg [8:0] addressA, addressB;
    reg clockA, clockB;
    reg writeEnableA, writeEnableB;
    reg [31:0] dataInA, dataInB;

    wire [31:0] dataOutA, dataOutB;

    fullyDualPortSSRAM uut (
        .addressA(addressA),
        .addressB(addressB),
        .clockA(clockA),
        .clockB(clockB),
        .writeEnableA(writeEnableA),
        .writeEnableB(writeEnableB),
        .dataInA(dataInA),
        .dataInB(dataInB),
        .dataOutA(dataOutA),
        .dataOutB(dataOutB)
    );

    initial begin
        clockA = 0;
        forever #2 clockA = ~clockA;
    end

    initial begin
        clockB = 0;
        forever #2 clockB = ~clockB; 
    end

    // Test sequence
    initial begin
        // Initialize inputs
        addressA = 0;
        addressB = 0;
        writeEnableA = 0;
        writeEnableB = 0;
        dataInA = 0;
        dataInB = 0;

        #12;


        // write through port A and read from port A
        addressA = 9'h01;
        dataInA = 32'hDEADBEEF;
        writeEnableA = 1;
        #4;
        addressA = 9'h00;
        writeEnableA = 0;
        dataInA = 0;
        #12;

        // Read back data from port B
        addressB = 9'h01;
        #4;
        addressB = 9'h00;
        #4;


        // Write through port B and read from port B
        addressB = 9'h02;
        dataInB = 32'hCAFEBABE;
        writeEnableB = 1;
        #4;
        addressB = 9'h00;
        dataInB = 0;
        writeEnableB = 0;
        #12;

        // Read back data from port A
        addressB = 9'h01;
        // Read back data from port B
        addressA = 9'h02;
        #4;
        addressA = 9'h00;
        addressB = 9'h00;
        #4;
        

        // Test simultaneous writes
        addressA = 9'h1ff;
        dataInA = 32'h12345678;
        writeEnableA = 1;

        addressB = 9'h1fe;
        dataInB = 32'h87654321;
        writeEnableB = 1;

        #4;
        writeEnableA = 0;
        addressA = 9'h00;
        dataInA = 0;
        writeEnableB = 0;
        addressB = 9'h00;
        dataInB = 0;
        #12;

        // Read back data from both ports
        addressA = 9'h1ff;
        addressB = 9'h1fe;
        #10;

        // Finish simulation
        $finish;
    end

    initial begin
        $dumpfile("test_fullyDualPortSSRAM.vcd");
        $dumpvars(0, tb_fullyDualPortSSRAM);
    end

endmodule