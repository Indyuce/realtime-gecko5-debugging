module memoryStage ( input wire         clock,
                                        reset,
                                        flushCache,
                                        pipelineStall,
                     // Here the bus interface is defined
                     output wire        requestBus,
                     input wire         busAccessGranted,
                                        busErrorIn,
                     output wire        beginTransactionOut,
                     input wire         beginTransactionIn,
                     output wire [31:0] addressDataOut,
                     input wire  [31:0] addressDataIn,
                     output wire        endTransactionOut,
                     input wire         endTransactionIn,
                     output wire [3:0]  byteEnablesOut,
                     output wire        readNotWriteOut,
                     input wire         readNotWriteIn,
                     output wire        dataValidOut,
                     input wire         dataValidIn,
                     input wire         busyIn,
                     output wire [7:0]  burstSizeOut,
                     input wire [7:0]   burstSizeIn,
                  
                     // Here the interface to the scratchpad memory is defined
                     output wire [31:0] dataToSpm,
                     input wire [31:0]  dataFromSpm,
                     output wire [17:0] spmAddress,
                     output wire [3:0]  spmByteEnables,
                     output wire        spmChipSelect,
                     output wire        spmWriteEnable,
                  
                     // Here the profiling signals are defined
                     output reg         cachedWrite,
                                        cachedRead,
                                        uncachedWrite,
                                        uncachedRead,
                                        swapInstruction,
                                        casInstruction,
                                        cacheMiss,
                                        cacheWriteBack,
                                        dataStall,
                                        writeStall,
                                        processorStall,
                                        cacheStall,
                                        writeThrough,
                                        invalidate,
                  
                     // Here the interface to the cpu is defined
                     output wire        stallCpu,
                     input wire         enableCache,
                     input wire         memorySync,
                     input wire [1:0]   replacementPolicy,
                                        numberOfWays,
                                        cacheSize,
                     input wire         writeBackPolicy,
                                        coherenceEnabled,
                                        mesiEnabled,
                                        snarfingEnabled,
                     input wire [29:0]  instructionAddress,
                     input wire [31:0]  dataFromCore,
                                        memoryAddress,
                     input wire [2:0]   memoryStore,
                                        memoryLoad,
                     input wire [7:0]   memoryCompareValue,
                     input wire [8:0]   loadTarget,
                     input wire         wbWriteEnable,
                     input wire [4:0]   wbRegisterAddress,
                     input wire [4:0]   rfOperantAAddress,
                                        rfOperantBAddress,
                                        rfStoreAddress,
                     input wire         rfWriteDestination,
                     input wire [8:0]   rfDestination,
                     input wire [3:0]   cid,
                     output wire        resetExeLoad,
                                        dataAbort,
                     output wire [31:0] abortAddress,
                                        abortMemoryAddress,
                     output reg [31:0]  dataToCore,
                     output wire [8:0]  registerAddress,
                     output wire        registerWe );

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
  localparam [2:0] COMPARE_AND_SWAP             = 3'b100; // not supported in this implementation
  localparam [2:0] SWAP                         = 3'b101; // not supported in this implementation

  /*
   *
   * The memory address comes directly from the adder, so we have to register it
   *
   */
  reg [31:0] s_memoryAddressReg;
  wire [31:0] s_memoryAddress = (pipelineStall == 1'b0) ? memoryAddress : s_memoryAddressReg;
  always @(posedge clock) s_memoryAddressReg <= (reset == 1'b1) ? 32'd0 : s_memoryAddress;

  /*
   *
   * here we determine the access type
   *
   */
  wire s_spmAddressed        = (s_memoryAddressReg[31:20] == 12'hC00) ? 1'b1 : 1'b0;
  wire s_spmReadAccess       = (memoryLoad == NO_LOAD) ? 1'b0 : s_spmAddressed;
  wire s_spmWriteAccess      = (memoryStore == NO_STORE|| memoryStore == COMPARE_AND_SWAP || memoryStore == SWAP) ? 1'b0 : s_spmAddressed;
  wire s_uncachedReadAccess  = (memoryLoad == NO_LOAD || s_spmAddressed == 1'b1) ? 1'b0 : 
                               (s_memoryAddressReg[30] == 1'b1 || enableCache == 1'b0) ? 1'b1 : 1'b0;
  wire s_uncachedWriteAccess = (memoryStore == NO_STORE || memoryStore [2] = 1'b1 || s_spmAddressed == 1'b1) ? 1'b0 :
                               (s_memoryAddressReg[30] == 1'b1 || enableCache == 1'b0) ? 1'b1 : 1'b0;
  wire s_cachedReadAccess    = (memoryLoad == NO_LOAD || s_spmAddressed == 1'b1) ? 1'b0 : 
                               (s_memoryAddressReg[30] == 1'b0) ? enableCache : 1'b0;
  wire s_cachedWriteAccess   = (memoryStore == NO_STORE || memoryStore [2] = 1'b1 || s_spmAddressed == 1'b1) ? 1'b0 :
                               (s_memoryAddressReg[30] == 1'b0) ? enableCache : 1'b0;
  
  /*
   *
   * Here we define the output signals
   *
   */
  reg [8:0] s_registerAddressReg;
  reg       s_registerWeReg;
  
  always @(posedge clock)
    begin
      s_registerAddressReg <= (s_spmReadAccess == 1'b1) ? loadTarget : 9'd0;
      s_registerWeReg      <= s_spmReadAccess;
    end

  /*
   *
   * Here some control signals are defined
   *
   */
  wire s_dataDependencyStall = (memoryLoad == NO_LOAD && loadTarget[8:5] == cid && (loadTarget[4:0] == rfOperantAAddress || loadTarget[4:0] == rfOperantBAddress) ? 1'b1 : 1'b0;
  
  
endmodule
