module DMA #(
    parameter [31:0] Base = 32'h40000000)
    ( 
    input wire                    clock, n_reset,
    input wire                    ipcore_launch_write,
    input wire                    ipcore_launch_read,
    input wire                    ipcore_launch_simple_switch,
    input wire [3:0]              ipcore_byte_enable,
    input wire [31:0]             ipcore_address,
    input wire [7:0]              ipcore_burst_size,
    output wire                   ipcore_dma_busy,
    output wire                   ipcore_operation_ended,
    output wire [7:0]             ipcore_block_sizeOUT,
    input wire [7:0]              ipcore_block_sizeIN,


    // Buffer interface
    output wire [8:0]             pp_address,
    output wire [31:0]            pp_dataIn,
    output wire                   pp_writeEnable,
    input wire [31:0]             pp_dataOut,

    // here the bus interface is defined
    input wire [31:0] address_dataIN,
    input wire end_transactionIN, 
    input wire data_validIN, 
    input wire busyIN,
    input wire bus_errorIN,

    output wire [31:0] address_dataOUT,
    output wire [3:0] byte_enableOUT,
    output wire [7:0] burst_sizeOUT,
    output wire read_n_writeOUT,
    output wire begin_transactionOUT,
    output wire end_transactionOUT,
    output wire data_validOUT,
    output wire busyOUT,



    // here the interface with the arbitrer
    output wire        requestTransaction,
    input wire         transactionGranted,


    output wire [7:0]  s_dma_cur_state

    );

    // Reg for sdram control

    reg [31:0] bus_start_address_reg;
    reg [7:0] bus_burst_size_reg;
    reg [3:0] bus_byte_enable_reg;
    reg [31:0] bus_block_size_reg;

    always @(posedge clock) begin
        bus_start_address_reg <= (n_reset == 1'b0) ? 32'h0 : 
                                (ipcore_launch_write == 1'b1 || ipcore_launch_read == 1'b1) ? ipcore_address : bus_start_address_reg;
        bus_burst_size_reg <= (n_reset == 1'b0) ? 8'h0 :
                                (ipcore_launch_write == 1'b1 || ipcore_launch_read == 1'b1) ? ipcore_burst_size : bus_burst_size_reg;
        bus_byte_enable_reg <= (n_reset == 1'b0) ? 4'h0 :
                                (ipcore_launch_write == 1'b1 || ipcore_launch_read == 1'b1) ? ipcore_byte_enable : bus_byte_enable_reg;
        bus_block_size_reg <= (n_reset == 1'b0) ? 32'h0 :
                                (ipcore_launch_write == 1'b1 || ipcore_launch_read == 1'b1 || ipcore_launch_simple_switch == 1'b1) ? ipcore_block_sizeIN : bus_block_size_reg;
    end

    // regs for all bus-in signals
    reg [31:0] address_dataIN_reg;
    reg end_transactionIN_reg;
    reg data_validIN_reg;

    always @(posedge clock) begin
        address_dataIN_reg <= address_dataIN;
        end_transactionIN_reg <= end_transactionIN;
        data_validIN_reg <= data_validIN;
    end



    // DMA state machine
    localparam [4:0] fsm_idle = 4'd0;
    localparam [4:0] fsm_init = 4'd1;
    localparam [4:0] fsm_request_bus = 4'd2;
    localparam [4:0] fsm_set_up_transaction = 4'd3;
    localparam [4:0] fsm_read = 4'd4;
    localparam [4:0] fsm_wait_end = 4'd5;
    localparam [4:0] fsm_write = 4'd6;
    localparam [4:0] fsm_end_transaction_error = 4'd7;
    localparam [4:0] fsm_end_write_transaction = 4'd8;

    reg [4:0] cur_state, nxt_state;
    reg read_n_write_reg;
    // One more bit to indicate when it reaches 0
    reg [8:0] words_written_reg;

    assign ipcore_dma_busy = (cur_state == fsm_idle) ? 1'b0 : 1'b1;
    wire s_dma_done;

    always @* begin
        case (cur_state)
            fsm_idle                  : nxt_state <= (ipcore_launch_write == 1'b1 || ipcore_launch_read == 1'b1) ? fsm_init : fsm_idle;
            fsm_init                  : nxt_state <= fsm_request_bus;
            fsm_request_bus           : nxt_state <= (transactionGranted == 1'b1) ? fsm_set_up_transaction : fsm_request_bus;
            fsm_set_up_transaction    : nxt_state <= (read_n_write_reg == 1'b1) ? fsm_read : fsm_write;
            fsm_read                  : nxt_state <= (bus_errorIN == 1'b1) ? fsm_wait_end :
                                                // End of the transacsion
                                                (end_transactionIN_reg == 1'b1 && s_dma_done == 1'b1) ? fsm_idle :
                                                // End of the burst
                                                (end_transactionIN_reg == 1'b1) ? fsm_request_bus : fsm_read;
                                                    //Wait for the end of the transaction
            fsm_wait_end              : nxt_state <= (end_transactionIN_reg == 1'b1) ? fsm_idle : fsm_wait_end;
            fsm_write                 : nxt_state <= (bus_errorIN == 1'b1) ? fsm_end_transaction_error :
                                                    // End of the burst
                                                    (words_written_reg[8] == 1'b1 && busyIN == 1'b0) ? fsm_end_write_transaction : fsm_write;
                                                    // Either end of the transaction or end of the burst
            fsm_end_write_transaction : nxt_state <= (s_dma_done == 1'b1) ? fsm_idle : fsm_request_bus;
            default                   : nxt_state <= fsm_idle;
        endcase
    end

    always @(posedge clock) begin
        // Update the state machine
        cur_state <= (n_reset == 1'b0) ? fsm_idle : nxt_state;
        // Update if it is a read or a write
        read_n_write_reg <= (cur_state == fsm_idle) ? ipcore_launch_read : read_n_write_reg;
    end

    // All the register that are to be updated during the burst
    reg [31:0] updated_bus_start_address_reg;
    reg [8:0] updated_block_size_reg;
    reg [8:0] pp_address_reg;
    reg operation_launch_reg;
    reg operation_ended_reg;

    // Is the teransaction done?
    assign s_dma_done = (updated_block_size_reg == 9'b0) ? 1'b1 : 
                              // end of transaction at the same time of last valid data
                              (updated_block_size_reg == 9'b1 && end_transactionIN_reg == 1'b1 && data_validIN_reg == 1'b1) ? 1'b1 : 1'b0;
    // Write in buffer iff the data read is valid
    assign pp_writeEnable = (cur_state == fsm_read && data_validIN_reg == 1'b1) ? 1'b1 : 1'b0;
    // Say if we actually wrote data on the bus or it was busy or the burst was over
    wire busWrite = (cur_state == fsm_write ) ? ~busyIN & ~words_written_reg[8] : 1'b0;

    always @(posedge clock) begin
        // Update all the regs : bus start address + 4, block size - 1 and pp address + 1
        updated_bus_start_address_reg <= (n_reset == 1'b0) ? 32'h0 : 
                                        (cur_state == fsm_init) ? bus_start_address_reg : 
                                        (busWrite == 1'b1 || pp_writeEnable == 1'b1) ? updated_bus_start_address_reg + 32'h4 : updated_bus_start_address_reg;
        updated_block_size_reg <= (n_reset == 1'b0) ? 9'h0 :
                                    (cur_state == fsm_init) ? bus_block_size_reg : 
                                    (busWrite == 1'b1 || pp_writeEnable == 1'b1) ? updated_block_size_reg - 9'h1 : updated_block_size_reg;
        pp_address_reg <= (n_reset == 1'b0 || cur_state == fsm_init) ? 9'h0 :
                          (busWrite == 1'b1 || pp_writeEnable == 1'b1) ? pp_address_reg + 8'h1 : pp_address_reg;
        operation_launch_reg <= (n_reset == 1'b0) ? 1'b0 :
                                (operation_ended_reg == 1'b1) ? 1'b0 :
                                (cur_state == fsm_init) ? ~ipcore_launch_simple_switch : operation_launch_reg;
        operation_ended_reg <= (n_reset == 1'b0) ? 1'b0 :
                                (ipcore_launch_read == 1'b1 || ipcore_launch_write == 1'b1 || ipcore_launch_simple_switch == 1'b1) ? 1'b0 :
                                (cur_state == fsm_idle && operation_launch_reg == 1'b1) ? 1'b1 : operation_ended_reg;
    end


    // Bus output signals
    reg data_validOUT_reg;
    reg [3:0] byte_enableOUT_reg;
    reg [7:0] burst_sizeOUT_reg;
    reg [7:0] burst_sizeOUT_shadow;
    reg [31:0] address_dataOUT_reg;
    reg read_n_writeOUT_reg, begin_transactionOUT_reg, end_transactionOUT_reg;

    wire [8:0] maxBurstSize = {2'b0, bus_burst_size_reg[7:0]} + 9'h1;
    wire [8:0] restingBlockSize = updated_block_size_reg - 9'h1;
    wire [7:0] actualBurstSize = (updated_block_size_reg > maxBurstSize) ? bus_burst_size_reg : restingBlockSize[7:0];

    always @(posedge clock) begin
        begin_transactionOUT_reg <= (cur_state == fsm_set_up_transaction) ? 1'b1 : 1'b0;
        read_n_writeOUT_reg <= (cur_state == fsm_set_up_transaction) ? read_n_write_reg : 1'b0;
        byte_enableOUT_reg <= (cur_state == fsm_set_up_transaction) ? bus_byte_enable_reg : 4'h0;
        burst_sizeOUT_reg <= (cur_state == fsm_set_up_transaction) ? actualBurstSize : 8'h0;
        address_dataOUT_reg <= (n_reset == 1'b0) ? 32'h0 :
                                (cur_state == fsm_write && busyIN == 1'b1) ? address_dataOUT_reg :
                                (busWrite == 1'b1) ? pp_dataOut :
                                (cur_state == fsm_set_up_transaction) ? {updated_bus_start_address_reg[31:2], 2'b00} : 32'h0;
        // address_dataOUT_reg <= (cur_state == fsm_set_up_transaction) ? {updated_bus_start_address_reg[31:2], 2'b00} :
        //                         (busWrite == 1'b1) ? pp_dataOut :
        //                         // stall in case of busy in
        //                         (cur_state == fsm_read && busyIN == 1'b1) ? address_dataOUT_reg : 32'h0;
        end_transactionOUT_reg <= (cur_state == fsm_end_transaction_error || cur_state == fsm_end_write_transaction) ? 1'b1 : 1'b0;
        data_validOUT_reg <= (cur_state == fsm_write && busyIN == 1'b1) ? data_validOUT_reg: busWrite;
        words_written_reg <= (cur_state == fsm_set_up_transaction) ? {1'b0, actualBurstSize[7:0]} :
                                (busWrite == 1'b1) ? words_written_reg - 9'h1 : words_written_reg;
    end

    // assign address_dataOUT = (data_validOUT_reg == 1'b1) ? pp_dataOut : address_dataOUT_reg;
    assign address_dataOUT = address_dataOUT_reg;
    assign byte_enableOUT = byte_enableOUT_reg;
    assign burst_sizeOUT = burst_sizeOUT_reg;
    assign read_n_writeOUT = read_n_writeOUT_reg;
    assign begin_transactionOUT = begin_transactionOUT_reg;
    assign end_transactionOUT = end_transactionOUT_reg;
    assign data_validOUT = data_validOUT_reg;
    assign busyOUT = 0; // never busy


    // Bus arbitrer signals
    assign requestTransaction = (cur_state == fsm_request_bus) ? 1'b1 : 1'b0;

    // words written update 

    assign ipcore_block_sizeOUT = bus_block_size_reg;
    assign pp_address = pp_address_reg;
    assign pp_dataIn = address_dataIN_reg;
    assign ipcore_operation_ended = operation_ended_reg;


    always @(posedge clock) begin
        if (n_reset == 1'b0) begin
            burst_sizeOUT_shadow <= 8'h0;
        end else if (begin_transactionOUT_reg == 1'b1) begin
            burst_sizeOUT_shadow <= burst_sizeOUT;
        end
    end
    // assign s_dma_cur_state = {cur_state, busyIN, data_validOUT, words_written_reg[8]};
    assign s_dma_cur_state = {burst_sizeOUT_shadow[7:0]};
    // assign s_dma_cur_state = {bus_block_size_reg[7:0]};
    

endmodule
