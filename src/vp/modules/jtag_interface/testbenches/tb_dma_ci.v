`timescale 1ns / 1ps

module tb_dma_ci;

    // Parameters
    localparam [7:0] CUSTOM_INSTRUCTION_ID = 8'd49;

    // Inputs
    reg start;
    reg clock;
    reg reset;
    reg [31:0] valueA;
    reg [31:0] valueB;
    reg [7:0] iseId;

    // Outputs
    wire done;
    wire [31:0] result;

    // Internal signals
    wire s_dataReady;
    wire s_readReady;
    wire [3:0] s_byteEnable;
    wire [31:0] s_address_to_read;
    wire s_endTransaction;
    wire s_dataValid;
    wire s_address_data;

    // Instantiate the Unit Under Test (UUT)
    dma_ci #(.customInstructionId(CUSTOM_INSTRUCTION_ID)) uut (
        .start(start),
        .clock(clock),
        .reset(reset),
        .valueA(valueA),
        .valueB(valueB),
        .iseId(iseId),
        .done(done),
        .result(result)
    );

    // Clock generation
    initial begin
        clock = 0;
        forever #5 clock = ~clock; // 100 MHz clock
    end

    // Testbench logic
    initial begin
        // Initialize inputs
        start = 0;
        reset = 0;
        valueA = 32'h0;
        valueB = 32'h0;
        iseId = 8'h0;

        // Reset the design
        #10 reset = 1;
        #10 reset = 0;

        // Test case 1: Start a transaction with matching ISE ID
        #10 iseId = CUSTOM_INSTRUCTION_ID;
        valueA = 32'h12345678;
        valueB = 32'h00FFFFF1; // is_read = 1
        start = 1;
        #10 start = 0;

        // Wait for done signal
        // wait(done);
        #50;

        // Test case 2: Start a transaction with non-matching ISE ID
        #50; // Non-matching ID
        valueA = 32'h87654321;
        valueB = 32'h00FFFFF0; // is_read = 0
        start = 1;
        #10 start = 0;

        // Wait for done signal
        // wait(done);
        #10;

        // End simulation
        #100 $finish;
    end

    initial begin
        $dumpfile("test_dma_ci.vcd");
        $dumpvars(0, tb_dma_ci);
    end

endmodule