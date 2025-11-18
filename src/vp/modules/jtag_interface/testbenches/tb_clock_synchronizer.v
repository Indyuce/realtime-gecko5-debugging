`timescale 1ns/1ps

module tb_clock_synchronizer;

    // Testbench signals
    reg clk_in;
    reg clk_out;
    reg[9:0] to_sync;
    reg n_reset;
    wire[9:0] sync_out;

    // Instantiate the DUT (Device Under Test)
    clock_synchronizer #(10) uut (
        .clockIn(clk_in),
        .clockOut(clk_out),
        .D(to_sync),
        .Q(sync_out),
        .reset(~n_reset)
    );

    // Clock generation for clk_in
    initial begin
        clk_in = 0;
        forever #5 clk_in = ~clk_in; // 10ns period
    end

    // Clock generation for clk_out
    initial begin
        clk_out = 0;
        forever #30 clk_out = ~clk_out; // 14ns period
    end

    // Test stimulus
    initial begin
        // Initialize inputs
        to_sync = 0; // Set to_sync high
        n_reset = 0;
        #10 n_reset = 1; // Release reset after 10ns


        #10 to_sync = 10'h3FF;
        #10 to_sync = 10'h0; // Set to_sync low

        // #10 to_sync = 10'h1FF; // Set to_sync high again

        // Finish simulation
        #900 $finish;
    end

    // Monitor signals
    initial begin
         $dumpfile("test_clock_sync.vcd");
        $dumpvars(0, tb_clock_synchronizer);
    end

endmodule