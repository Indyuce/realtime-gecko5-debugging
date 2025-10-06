  localparam [1:0] DIRECT_MAPPED            = 2'b00;
  localparam [1:0] TWO_WAY_SET_ASSOCIATIVE  = 2'b01;
  localparam [1:0] FOUR_WAY_SET_ASSOCIATIVE = 2'b10;
  
  localparam [3:0] DIRECT_MAPPED_1K            = 4'b0000;
  localparam [3:0] DIRECT_MAPPED_2K            = 4'b0001;
  localparam [3:0] DIRECT_MAPPED_4K            = 4'b0010;
  localparam [3:0] DIRECT_MAPPED_8K            = 4'b0011;
  localparam [3:0] TWO_WAY_SET_ASSOCIATIVE_1K  = 4'b0100;
  localparam [3:0] TWO_WAY_SET_ASSOCIATIVE_2K  = 4'b0101;
  localparam [3:0] TWO_WAY_SET_ASSOCIATIVE_4K  = 4'b0110;
  localparam [3:0] TWO_WAY_SET_ASSOCIATIVE_8K  = 4'b0111;
  localparam [3:0] FOUR_WAY_SET_ASSOCIATIVE_1K = 4'b1000;
  localparam [3:0] FOUR_WAY_SET_ASSOCIATIVE_2K = 4'b1001;
  localparam [3:0] FOUR_WAY_SET_ASSOCIATIVE_4K = 4'b1010;
  localparam [3:0] FOUR_WAY_SET_ASSOCIATIVE_8K = 4'b1011;
  
  localparam [1:0] SIZE_1K = 2'b00;
  localparam [1:0] SIZE_2K = 2'b01;
  localparam [1:0] SIZE_4K = 2'b10;
  localparam [1:0] SIZE_8K = 2'b11;

  localparam [1:0] FIFO_REPLACEMENT         = 2'b00;
  localparam [1:0] PLRU_REPLACEMENT         = 2'b01;
  localparam [1:0] LRU_REPLACEMENT          = 2'b10;

  localparam [3:0] IDLE             = 4'd0;
  localparam [3:0] REQUEST_THE_BUS  = 4'd1;
  localparam [3:0] INIT_TRANSACTION = 4'd2;
  localparam [3:0] WAIT_READ_BURST  = 4'd3;
  localparam [3:0] NOP              = 4'd4;
  localparam [3:0] UPDATE_TAGS      = 4'd5;
  localparam [3:0] RELEASE          = 4'd6;
  localparam [3:0] FLUSH_INIT       = 4'd7;
  localparam [3:0] DO_FLUSH         = 4'd8;
  localparam [3:0] FLUSH_DONE       = 4'd9;

