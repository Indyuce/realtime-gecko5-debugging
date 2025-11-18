`timescale 1ps/1ps

module tb_pingpongbuffer;

    // Parameters
    parameter bitwidth = 32;
    parameter nrOfEntries = 512;

    // Testbench signals
    reg clock;
    reg [$clog2(nrOfEntries)-1:0] addressA;
    reg [$clog2(nrOfEntries)-1:0] addressB;
    reg [bitwidth-1:0] dataInA;
    reg [bitwidth-1:0] dataInB;
    wire [bitwidth-1:0] dataOutA;
    wire [bitwidth-1:0] dataOutB;
    reg writeEnableA;
    reg writeEnableB;
    reg switch;
    reg reset;
    wire [bitwidth-1:0] popData;

    // Clock generation (4ps period)
    initial clock = 0;
    always #2 clock = ~clock;

    // DUT instantiation
    pingpongbuffer uut (
        .clock(clock), 
        .addressA(addressA),
        .addressB(addressB),
        .writeEnableA(writeEnableA),
        .writeEnableB(writeEnableB),
        .dataInA(dataInA),
        .dataInB(dataInB),
        .dataOutA(dataOutA),
        .dataOutB(dataOutB),
        .switch(switch),
        .reset(reset)
    );

    // Testbench logic
    initial begin
        // Initialize signals
        addressA = 0;
        addressB = 0;
        dataInA = 0;
        dataInB = 0;
        writeEnableA = 0;
        writeEnableB = 0;
        switch = 0;
        reset = 1;

        // Wait for a few clock cycles
        #12;
        reset = 0; // Release reset

        // Write to the first half of the buffer
        dataInA = 32'hFFFFFFF0;
        addressA = 0;
        writeEnableA = 1;
        dataInB = 32'h00;
        addressB = 0;
        writeEnableB = 1;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF1;
        addressA = 1;
        dataInB = 32'h01;
        addressB = 1;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF2;
        addressA = 2;
        dataInB = 32'h02;
        addressB = 2;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF3;
        addressA = 3;
        dataInB = 32'h03;
        addressB = 3;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF4;
        addressA = 4;
        dataInB = 32'h04;
        addressB = 4;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF5;
        addressA = 5;
        dataInB = 32'h05;
        addressB = 5;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF6;
        addressA = 6;
        dataInB = 32'h06;
        addressB = 6;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF7;
        addressA = 7;
        dataInB = 32'h07;
        addressB = 7;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF8;
        addressA = 8;
        dataInB = 32'h08;
        addressB = 8;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFF9;
        addressA = 9;
        dataInB = 32'h09;
        addressB = 9;
        #4; // Wait for one clock cycle
        dataInA = 32'hFFFFFFFA;
        addressA = 10;
        dataInB = 32'h0A;
        addressB = 10;
        #4; // Wait for one clock cycle
        writeEnableA = 0; // Stop writing data
        addressA = 0; // Reset addressA
        dataInA = 0; // Reset dataInA
        addressB = 0; // Reset addressB
        dataInB = 0; // Reset dataInB
        writeEnableB = 0; // Stop writing data

        // Toggle the switch
        switch = 1;
        #4; // Wait for one clock cycle
        switch = 0;

        // Read the first half of the buffer
        addressB = 0;
        addressA = 0;
        #4; // Wait for one clock cycle
        addressB = 1;
        addressA = 1;
        #4; // Wait for one clock cycle
        addressB = 2;
        addressA = 2;
        #4; // Wait for one clock cycle
        addressB = 3;
        addressA = 3;
        #4; // Wait for one clock cycle
        addressB = 4;
        addressA = 4;






  
        #20;
        $finish;
    end

    // Monitor signals
    initial begin
        $dumpfile("test_pingpong.vcd");
        $dumpvars(0, tb_pingpongbuffer);
    end


endmodule