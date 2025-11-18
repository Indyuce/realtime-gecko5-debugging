`timescale 1ns/1ps

module tb_DMA;

    // DUT signals
    reg clock;
    reg n_reset;
    reg ipcore_launch_write;
    reg ipcore_launch_read;
    reg [3:0] ipcore_byte_enable;
    reg [31:0] ipcore_address;
    reg [7:0] ipcore_burst_size;
    wire ipcore_dma_busy;
    wire [7:0] ipcore_block_sizeOUT;
    reg [7:0] ipcore_block_sizeIN;

    wire [8:0] pp_address;
    wire [31:0] pp_dataIn;
    wire pp_writeEnable;
    reg [31:0] pp_dataOut;

    reg [31:0] address_dataIN;
    reg end_transactionIN;
    reg data_validIN;
    reg busyIN;
    reg bus_errorIN;

    wire [31:0] address_dataOUT;
    wire [3:0] byte_enableOUT;
    wire [7:0] busrt_sizeOUT;
    wire read_n_writeOUT;
    wire begin_transactionOUT;
    wire end_transactionOUT;
    wire data_validOUT;
    wire busyOUT;

    wire requestTransaction;
    reg transactionGranted;

    wire [3:0] s_dma_cur_state;

    // Instantiate the DUT
    DMA dut (
        .clock(clock),
        .n_reset(n_reset),
        .ipcore_launch_write(ipcore_launch_write),
        .ipcore_launch_read(ipcore_launch_read),
        .ipcore_byte_enable(ipcore_byte_enable),
        .ipcore_address(ipcore_address),
        .ipcore_burst_size(ipcore_burst_size),
        .ipcore_dma_busy(ipcore_dma_busy),
        .ipcore_block_sizeIN(ipcore_block_sizeIN),
        .ipcore_block_sizeOUT(ipcore_block_sizeOUT),
        .pp_address(pp_address),
        .pp_dataIn(pp_dataIn),
        .pp_writeEnable(pp_writeEnable),
        .pp_dataOut(pp_dataOut),
        .address_dataIN(address_dataIN),
        .end_transactionIN(end_transactionIN),
        .data_validIN(data_validIN),
        .busyIN(busyIN),
        .bus_errorIN(bus_errorIN),
        .address_dataOUT(address_dataOUT),
        .byte_enableOUT(byte_enableOUT),
        .burst_sizeOUT(busrt_sizeOUT),
        .read_n_writeOUT(read_n_writeOUT),
        .begin_transactionOUT(begin_transactionOUT),
        .end_transactionOUT(end_transactionOUT),
        .data_validOUT(data_validOUT),
        .busyOUT(busyOUT),
        .requestTransaction(requestTransaction),
        .transactionGranted(transactionGranted),
        .s_dma_cur_state(s_dma_cur_state)
    );

    // Clock generation
    initial begin
        clock = 0;
        forever #2 clock = ~clock; // 100MHz clock
    end
    initial begin
        // Initialize all signals to default values
        n_reset = 0;
        ipcore_launch_write = 0;
        ipcore_launch_read = 0;
        ipcore_byte_enable = 4'b0000;
        ipcore_address = 32'b0;
        ipcore_burst_size = 8'b0;
        ipcore_block_sizeIN = 8'b0;
        pp_dataOut = 32'b0;
        address_dataIN = 32'b0;
        end_transactionIN = 0;
        data_validIN = 0;
        busyIN = 0;
        bus_errorIN = 0;
        transactionGranted = 0;

        // Release reset after 10ns
        #20 n_reset = 1;

        // Test write transaction
        #12 ipcore_launch_write = 1;
        ipcore_address = 32'hAABBCCDD;
        ipcore_burst_size = 8'd10;
        ipcore_byte_enable = 4'b1111;
        ipcore_block_sizeIN = 8'd19;

        #4 ipcore_launch_write = 0; // Deassert write signal
        transactionGranted = 1; // Grant transaction
        #20 transactionGranted = 0; // Simulate data input
        #4 busyIN = 1; // Simulate busy signal
        #40 busyIN = 0; // Simulate end of transaction
        #4 transactionGranted = 1; // Grant transaction

        #80;

        // n_reset = 0; // Assert reset
        // #4 n_reset = 1; // Deassert reset

        // // Test write transaction with error
        // #12 ipcore_launch_write = 1;
        // ipcore_address = 32'hAABBCCDD;
        // ipcore_burst_size = 8'd100;
        // ipcore_byte_enable = 4'b1111;
        // ipcore_block_sizeIN = 8'd200;
        // #4 ipcore_launch_write = 0; // Deassert write signal
        // transactionGranted = 1; // Grant transaction
        // #20 transactionGranted = 0; // Simulate data input
        // #100 bus_errorIN = 1; // Simulate bus error
        // #4 bus_errorIN = 0; // Clear bus error

        // // Test read transaction
        // #12 ipcore_launch_read = 1;
        // ipcore_address = 32'h00f00000;
        // ipcore_burst_size = 8'd10;
        // ipcore_byte_enable = 4'b1111;
        // ipcore_block_sizeIN = 8'd20;
        // #4 ipcore_launch_read = 0; // Deassert read signal
        // transactionGranted = 1; // Grant transaction
        // #20 transactionGranted = 0; // Simulate data input
        // #4 data_validIN = 1; // Simulate data valid signal
        // #80 data_validIN = 0; // Simulate end of transaction
        // #4 end_transactionIN = 1; // Grant transaction



        #800
        $finish;
    end

    // Monitor signals
    initial begin
        $dumpfile("test_dma.vcd");
        $dumpvars(0, tb_DMA);
    end
    
    always @(pp_address) begin
        pp_dataOut <= {24'hFFFFFF, pp_address}; // Simulate data input
    end

    always @(posedge clock) begin
        if (n_reset == 1'b0) begin
            address_dataIN <= 32'hA0000000;
        end else if (data_validIN == 1'b1) begin
            address_dataIN <= address_dataIN + 1;
        end
    end

endmodule
