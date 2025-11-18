module chain1(
    // JTAG signals
    input wire JTCK,
    input wire JTDI,
    input wire JRTI1,
    input wire JSHIFT,
    input wire JUPDATE,
    input wire JRSTN,
    input wire JCE1,
    output wire JTD1,

    // Connection to the ping-pong buffer
    output wire [8:0] pp_address,
    output wire pp_writeEnable,
    output wire [31:0] pp_dataIn,
    input wire [31:0] pp_dataOut,
    output wire pp_switch,

    // Connection with the DMA
    input wire system_clk,
    output wire [31:0] DMA_address,
    output wire DMA_launch_write,
    output wire DMA_launch_read,
    output wire DMA_launch_simple_switch,
    output wire [3:0] DMA_byte_enable,
    output wire [7:0] DMA_burst_size_OUT,
    output wire [7:0] DMA_block_size_OUT,
    input wire DMA_busy,
    input wire DMA_operation_done,
    input wire [7:0] DMA_block_size_IN,

    // Visual Clues 
    output wire [5:0] status_reg_out
);


/*
*
* Signals definition
*
*/

assign n_reset = JRSTN;

reg [31:0] address_reg;
reg [3:0] byte_enable_reg;
reg [7:0] busrt_size_reg;

reg [35:0] shadow_reg;
reg [35:0] shift_reg;
reg [35:0] updated_data_reg;

reg update_reg;

reg [3:0] status_next;
reg [3:0] status_reg;

reg [31:0] data_reg;
reg [7:0] block_size_reg;
reg [7:0] block_size_reg_shadow;

reg write_to_buffer;
reg write_operation_in_progress;

reg [7:0] buffer_read_reg;
reg read_buffer;
reg read_operation_in_progress;

reg launch_write;
reg launch_read;
reg only_switch;

reg [2:0] chain1_cur_state;
reg [2:0] chain1_nxt_state;

// Internal signals
assign launch_dma = launch_write | launch_read | only_switch;

assign JTD1 = shift_reg[0];

assign operation_in_progress = write_operation_in_progress | read_operation_in_progress;
assign ready_to_launch = (block_size_reg != 8'b0) ? 1'b1 : only_switch;

assign buffer_full = (block_size_reg == 8'b11111111) ? 1'b1 : 1'b0;
assign read_complete = (buffer_read_reg == block_size_reg) ? 1'b1 : 1'b0;

// Debugging purpose
// assign status_reg_out = {status_reg};
assign status_reg_out = 6'b0;

// State machine states
localparam IDLE =                      0;
localparam ASK_FOR_BUFFER =            1;
localparam READ_BUFFER =               2; 
localparam WAIT_FOR_DMA =              3;
localparam SWITCH_BUFFER =             4;
localparam LAUNCH_DMA =                5;
localparam END_INSTRUCTION =           6;




always @(posedge JTCK) begin
    if (n_reset == 0) begin
        shift_reg <= 36'b0;
    end

    else begin
        // handle the JTAG signals
        if (JCE1) begin

            // Shifting data in
            if (JSHIFT) begin
                shift_reg <= {JTDI, shift_reg[35:1]};
            end

            // capture the shadow register
            else begin
                shift_reg <= shadow_reg;
            end
        end 

    end
    // Stores the value shifted in case of JUPDATE high 
    update_reg <= (n_reset == 1'b0) ? 0 : JUPDATE;
    updated_data_reg <= (n_reset == 1'b0) ? 0 : (JUPDATE == 1'b1) ? shift_reg : updated_data_reg;

    // Precompute the status register for sooner feedback
    if (JUPDATE == 1'b1) begin
        case (shift_reg[3:0])
            4'b0001: status_next = status_reg | 4'b0001;
            4'b0010: status_next = status_reg | 4'b0010;
            4'b0011: status_next = status_reg | 4'b0100;
            default: status_next = status_reg;
        endcase
    end
end

/* 
*
* Update the registers based on the JTAG instructions
*
*/

always @(posedge JTCK) begin
    if (n_reset == 0 || updated_data_reg[3:0] == 4'b1111) begin
        shadow_reg <= 36'b0;
        address_reg <= 32'b0;
        byte_enable_reg <= 4'b1111;
        busrt_size_reg <= 8'b0;
        status_reg <= 4'b0;
        block_size_reg <= 8'b0;
        data_reg <= 32'b0;
        write_to_buffer <= 1'b0;
        write_operation_in_progress <= 1'b0;
        read_operation_in_progress <= 1'b0;
        buffer_read_reg <= 8'b0;
        read_buffer <= 1'b0;
        data_reg <= 32'b0;
        launch_read <= 1'b0;
        launch_write <= 1'b0;
        only_switch <= 1'b0;
        block_size_reg_shadow <= 8'b0;
    end
    else if (update_reg == 1'b1) begin

        status_reg <= status_next;
                        
        shadow_reg <=   (updated_data_reg[3:0] == 4'b0100) ? address_reg :
                        (updated_data_reg[3:0] == 4'b0101) ? byte_enable_reg :
                        (updated_data_reg[3:0] == 4'b0110) ? busrt_size_reg :
                        (updated_data_reg[3:0] == 4'b1110) ? {18'b0, DMA_operation_done, {3'b0,DMA_busy}, 8'h0, status_next} :
                        {18'b0, DMA_operation_done,  {3'b0,DMA_busy}, block_size_reg, status_next}; 

        address_reg <= (updated_data_reg[3:0] == 4'b0001) ? updated_data_reg[35:4] : address_reg;

        byte_enable_reg <= (updated_data_reg[3:0] == 4'b0010) ? updated_data_reg[7:4] : byte_enable_reg;

        busrt_size_reg <= (updated_data_reg[3:0] == 4'b0011) ? updated_data_reg[11:4] : busrt_size_reg;

        block_size_reg <= (updated_data_reg[3:0] == 4'b1000 && buffer_full == 1'b0) ? block_size_reg + 1 :
                          (updated_data_reg[3:0] == 4'b1110) ? 8'b0 :
                          (updated_data_reg[3:0] == 4'b1011) ? updated_data_reg[11:4] : block_size_reg;

        block_size_reg_shadow <= (updated_data_reg[3:0] == 4'b1011) ? updated_data_reg[11:4] : block_size_reg;

        write_to_buffer <= (updated_data_reg[3:0] == 4'b1000 && buffer_full == 1'b0) ? 1'b1 : 1'b0;

        data_reg <= (updated_data_reg[3:0] == 4'b1000 && buffer_full == 1'b0) ? updated_data_reg[35:4] : data_reg;

        write_operation_in_progress <= (updated_data_reg[3:0] == 4'b1000 && buffer_full == 1'b0) ? 1'b1 : write_operation_in_progress;

        read_operation_in_progress <= (updated_data_reg[3:0] == 4'b1001) ? 1'b1 : read_operation_in_progress;

        buffer_read_reg <= (updated_data_reg[3:0] == 4'b1001 && read_complete == 1'b0) ? buffer_read_reg + 1 :
                           (updated_data_reg[3:0] == 4'b1110) ? 8'b0 : buffer_read_reg;

        read_buffer <= (updated_data_reg[3:0] == 4'b1001 && read_complete == 1'b0) ? 1'b1 : 1'b0;

        launch_read <= (updated_data_reg[3:0] == 4'b1011) ? 1'b1 : 1'b0;

        launch_write <= (updated_data_reg[3:0] == 4'b1010) ? 1'b1 : 1'b0;

        only_switch <= (updated_data_reg[3:0] == 4'b1100) ? 1'b1 : 1'b0;

    end

    // Udate some register depending on the current state of the chain
    else begin
        shadow_reg <= (chain1_cur_state == READ_BUFFER) ? data_reg :
                      (updated_data_reg[3:0] == 4'b1000) ?  {18'b0, DMA_operation_done, {3'b0, DMA_busy}, block_size_reg, shadow_reg[3:0]} : 
                      (chain1_cur_state == SWITCH_BUFFER) ?  {18'b0, DMA_operation_done, {3'b0,DMA_busy}, DMA_block_size_IN, shadow_reg[3:0]} : shadow_reg;

        data_reg <= (chain1_cur_state == READ_BUFFER) ? pp_dataOut : data_reg;

        read_buffer <= (chain1_cur_state == READ_BUFFER) ? 1'b0 : read_buffer;

        launch_read <= (chain1_cur_state == END_INSTRUCTION) ? 1'b0 : launch_read;

        launch_write <= (chain1_cur_state == END_INSTRUCTION) ? 1'b0 : launch_write;
        only_switch <= (chain1_cur_state == END_INSTRUCTION) ? 1'b0 : only_switch;

        block_size_reg <= (chain1_cur_state == SWITCH_BUFFER) ? DMA_block_size_IN : block_size_reg;

        buffer_read_reg <= (chain1_cur_state == SWITCH_BUFFER) ? 8'b0 : buffer_read_reg;
    end
end

/*
*
* State machine for the chain1
*
*/
always @(posedge JTCK) begin
    if (n_reset == 0) begin
        chain1_cur_state <= IDLE;
    end
    else begin
        chain1_cur_state <= chain1_nxt_state;
    end
end

always @(*) begin
    case (chain1_cur_state)
        IDLE: begin
            chain1_nxt_state <= (read_buffer == 1'b1) ? ASK_FOR_BUFFER :
                                (launch_dma == 1'b1 && ready_to_launch == 1'b1) ? WAIT_FOR_DMA :
                                IDLE;
        end

        // Read to buffer operaation
        ASK_FOR_BUFFER: begin
            chain1_nxt_state <= READ_BUFFER;
        end
        READ_BUFFER: begin
            chain1_nxt_state <= (JUPDATE == 1'b1) ? IDLE : READ_BUFFER;
        end

        // Send instruction to DMA
        WAIT_FOR_DMA: begin
            chain1_nxt_state <= (DMA_busy == 1'b0) ? SWITCH_BUFFER : WAIT_FOR_DMA;
        end
        SWITCH_BUFFER: begin
            chain1_nxt_state <= LAUNCH_DMA;
        end
        LAUNCH_DMA: begin
            chain1_nxt_state <= END_INSTRUCTION;
        end
        END_INSTRUCTION: begin
            chain1_nxt_state <= IDLE;
        end
        default: begin 
            chain1_nxt_state <= IDLE;
        end
    endcase
end

// Assign the outputs to the ping-pong buffer and DMA

assign pp_address = (write_to_buffer == 1'b1) ? {1'b0, block_size_reg - 1'b1} : 
                    (chain1_cur_state != IDLE) ? {1'b0, buffer_read_reg - 1'b1} : 9'b0;
assign pp_writeEnable = (write_to_buffer == 1'b1) ? 1'b1 : 1'b0;
assign pp_dataIn = (write_to_buffer == 1'b1) ? data_reg : 32'b0;
assign pp_switch = (chain1_cur_state == SWITCH_BUFFER) ? 1'b1 : 1'b0;

assign DMA_address = address_reg;
assign DMA_burst_size_OUT = busrt_size_reg;
assign DMA_byte_enable = byte_enable_reg;
assign s_launch_write = (chain1_cur_state == LAUNCH_DMA) ? launch_write: 1'b0;
assign s_launch_read = (chain1_cur_state == LAUNCH_DMA) ? launch_read : 1'b0;
assign s_launch_simple_switch = (chain1_cur_state == LAUNCH_DMA) ? only_switch : 1'b0;
assign DMA_block_size_OUT = block_size_reg_shadow;


/*
*
* Synchronize the launch signals to the system clock
*
*/

synchroFlop synchroFlop1(
    .clockIn(JTCK),
    .clockOut(system_clk),
    .reset(~JRSTN),
    .D(s_launch_write),
    .Q(DMA_launch_write)
);

synchroFlop synchroFlop2 (
    .clockIn(JTCK),
    .clockOut(system_clk),
    .reset(~JRSTN),
    .D(s_launch_read),
    .Q(DMA_launch_read)
);

synchroFlop synchroFlop3 (
    .clockIn(JTCK),
    .clockOut(system_clk),
    .reset(~JRSTN),
    .D(s_launch_simple_switch),
    .Q(DMA_launch_simple_switch)
);

endmodule
