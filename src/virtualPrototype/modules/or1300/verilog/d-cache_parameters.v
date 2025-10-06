  localparam [3:0] STATE_INVALID            = 4'h0;
  localparam [3:0] STATE_VALID              = 4'h1;
  localparam [3:0] STATE_DIRTY              = 4'h5;
  localparam [3:0] STATE_SHARED             = 4'h3;
  localparam [3:0] STATE_EXCLUSIVE          = 4'h1;
  localparam [3:0] STATE_MODIFIED           = 4'h9;
  localparam [3:0] VALID_MASK               = 4'h1;
  localparam [3:0] SHARED_MASK              = 4'h2;
  localparam [3:0] DIRTY_MASK               = 4'h4;
  localparam [3:0] MODIFIED_MASK            = 4'h8;
  
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

  localparam [2:0] NO_LOAD                      = 3'b000;
  localparam [2:0] LOAD_BYTE_ZERO_EXTENDED      = 3'b001;
  localparam [2:0] LOAD_BYTE_SIGN_EXTENDED      = 3'b101;
  localparam [2:0] LOAD_HALF_WORD_ZERO_EXTENDED = 3'b010;
  localparam [2:0] LOAD_HALF_WORD_SIGN_EXTENDED = 3'b110;
  localparam [2:0] LOAD_WORD_ZERO_EXTENDED      = 3'b011;
  localparam [2:0] LOAD_WORD_SIGN_EXTENDED      = 3'b111;

  localparam [2:0] NO_STORE                     = 3'b000;
  localparam [2:0] STORE_BYTE                   = 3'b001;
  localparam [2:0] STORE_HALF_WORD              = 3'b010;
  localparam [2:0] STORE_WORD                   = 3'b011;
  localparam [2:0] COMPARE_AND_SWAP             = 3'b100;
  localparam [2:0] SWAP                         = 3'b101;

  localparam [5:0] IDLE             = 6'd0;
  localparam [5:0] REQUEST_THE_BUS  = 6'd1;
  localparam [5:0] INIT_TRANSACTION = 6'd2;
  localparam [5:0] DET_TRANSACTION  = 6'd3;
  localparam [5:0] WAIT_N_BUSY      = 6'd4;
  localparam [5:0] DO_WRITE         = 6'd5;
  localparam [5:0] END_TRANSACTION  = 6'd6;
  localparam [5:0] UPDATE_TAGS      = 6'd7;
  localparam [5:0] RELEASE          = 6'd8;
  localparam [5:0] WAIT_READ_BURST  = 6'd9;
  localparam [5:0] NOP              = 6'd10;
  localparam [5:0] ATOMIC_REQUEST   = 6'd11;
  localparam [5:0] ATOMIC_INIT      = 6'd12;
  localparam [5:0] ATOMIC_WAIT      = 6'd13;
  localparam [5:0] BACKOFF          = 6'd14;
  localparam [5:0] LOOKUP_TAGS      = 6'd15;
  localparam [5:0] STORE_TAGS       = 6'd16;
  localparam [5:0] MARK_SHARED      = 6'd17;
  localparam [5:0] FLUSH_INIT       = 6'd18;
  localparam [5:0] FLUSH_LOOKUP     = 6'd19;
  localparam [5:0] FLUSH_INVALIDATE = 6'd20;
  localparam [5:0] FLUSH_DONE       = 6'd21;

  localparam [4:0] UNCACHEABLE_WRITE     = 5'd0;
  localparam [4:0] UNCACHEABLE_READ      = 5'd1;
  localparam [4:0] ATOMIC_SWAP           = 5'd2;
  localparam [4:0] ATOMIC_CAS            = 5'd3;
  localparam [4:0] CACHE_LINE_WRITE_BACK = 5'd4;
  localparam [4:0] CACHE_LINE_LOAD       = 5'd5;
  localparam [4:0] NOOP                  = 5'd6;
  localparam [4:0] WRITE_THROUGH         = 5'd7;
  localparam [4:0] SNOOPY_WRITE_BACK     = 5'd8;
  localparam [4:0] FLUSH_WRITE_BACK      = 5'd9;

