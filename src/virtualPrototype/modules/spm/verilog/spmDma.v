module spmDma #(parameter [31:0] slaveBaseAddress = 0,
                parameter [31:0] spmBaseAddress = 32'hC0000000,
                parameter [31:0] spmSizeInBytes = 8*1024)
               (input wire         clock,
                                   reset,
                output wire        irq,
                
                // here the spm interface is defined
                input wire         spmBusy,
                output wire [31:0] spmAddress,
                output wire        spmWe,
                output wire [31:0] spmWeData,
                input wire [31:0]  spmReData,

                // here the bus interface is defined
                output wire        requestTransaction,
                input wire         transactionGranted,
                input wire         beginTransactionIn,
                                   endTransactionIn,
                                   readNotWriteIn,
                                   dataValidIn,
                                   busErrorIn,
                                   busyIn,
                input wire [31:0]  addressDataIn,
                input wire [3:0]   byteEnablesIn,
                input wire [7:0]   burstSizeIn,
                output wire        beginTransactionOut,
                                   endTransactionOut,
                                   dataValidOut,
                                   readNotWriteOut,
                                   busErrorOut,
                                   busyOut,
                output wire [3:0]  byteEnablesOut,
                output wire [7:0]  burstSizeOut,
                output wire [31:0] addressDataOut);

  /*
   *
   * This module implements a DMA-controller that allows to transfer
   * data to/from the SPM-memory. It only allows word (32-bit) transfers.
   * it generates an irq when the transfer is completed.
   * 
   * the memory map for the slave-part is (baseAddress+):
   * 0  source/destination address in memory space
   * 4  source/destination address in spm space
   * 8  Number of words to transfer (should not be more than the size of the spm)
   * C  Set the burst-size in word when bit 8 and bit 9 are both 0.
   *    Start the transfer on write (writing bit8 = 1 and bit9 = 0 to this address will start the DMA-transfer from the SPM to the source/destination Address,
   *    writing a bit8 = 0 and bit9 = 1 to this address will start the DMA-transfer from the source/destination Address to the SPM)
   *    Read the status register
   *
   * The status register contains:
   * bit 0 -> The dma-controller is busy and will not react on the slave part, any writes to the slave-part is blocked and will
   *          result in a bus-error.
   * bit 1 -> An error is present in the number of words to be transferred (for example it is bigger as the spm-size) and a start
   *          of the DMA will not be performed.
   * bit 2 -> An error occured during the DMA-transfer, and it is not guaranteed that the DMA-transfer was successfull.
   * bit 3 -> Memory address alignment error, in this case the DMA will not start.
   * bit 4 -> Spm address alignment error, in this case the DMA will not start.
   * bit 5 -> Spm address out of range error, in this case the DMA will not start.
   *
   */

  function integer clog2;
    input [31:0] value;
    begin
      for (clog2 = 0; value > 32'd0 ; clog2= clog2 + 1)
        value = value >> 1;
      end
  endfunction

  localparam [31:0] maxSize      = {2'd0,spmSizeInBytes[31:2]};
  localparam maxBit = clog2(spmSizeInBytes);
  
  localparam [3:0] IDLE = 4'd0, DECIDE = 4'd1, GEN_IRQ = 4'd2, REQUEST_TRANS = 4'd3, WAIT_TRANS_ACK = 4'd4, INIT_TRANSACTION = 4'd5, WAIT_READ_DATA = 4'd6, ERROR = 4'd7, 
                   DO_WRITE_DATA = 4'd8, ERROR_STOP = 4'd9, END_TRANSACTION = 4'd10, BUSY_WAIT = 4'd11;
  
  reg [3:0] s_dmaStateReg, s_dmaStateNext;

  /*
   *
   * Here the slave part of the DMA-controller is defined
   *
   */
  
  reg [31:0]           s_sourceDestinationAddressReg;
  reg [31:0]           s_spmAddressReg;
  reg                  s_transferToSpmReg; // this is 1 when transfering data from external to the spm
  reg                  s_dmaBusyReg, s_transferSizeErrorReg, s_dmaTransferErrorReg, s_slaveDataOutValidReg, s_slaveEndTransactionReg;
  reg [31:0]           s_transferSizeInWordsReg, s_slaveDataOutReg, s_slaveDataOutNext;
  reg [3:0]            s_byteEnablesReg;
  reg                  s_beginTransactionReg, s_readNotWriteReg, s_dataInValidReg, s_transferActiveReg, s_endTransactionReg, s_startDmaReg;
  reg [7:0]            s_burstSizeInReg;
  reg [31:0]           s_addressReg;
  reg [31:0]           s_dataInReg;
  reg [7:0]            s_burstSizeReg;
  
  wire       s_isMyTransaction = (s_transferActiveReg == 1'b1 && s_addressReg[31:4] == slaveBaseAddress[31:4]) ? 1'b1 : 1'b0;
  wire       s_busyBlock       = s_isMyTransaction & s_dmaBusyReg & ~s_readNotWriteReg;
  wire       s_burstSizeError  = (s_isMyTransaction == 1'b1 && (s_burstSizeInReg != 8'd0 || s_byteEnablesReg != 4'hF)) ? 1'b1 : 1'b0;
  wire       s_slaveError      = s_busyBlock | s_burstSizeError;
  wire       s_memAlignError   = (s_sourceDestinationAddressReg[1:0] == 2'd0) ? 1'b0 : 1'b1;
  wire       s_spmAlignError   = (s_spmAddressReg[1:0] == 2'd0) ? 1'b0 : 1'b1;
  wire       s_spmAddressError = (s_spmAddressReg[31:maxBit] == spmBaseAddress[31:maxBit]) ? 1'b0 : 1'b1;
  wire       s_startDma        = (s_isMyTransaction == 1'b1 && s_slaveError == 1'b0 && s_dataInValidReg == 1'b1 && 
                                  (s_dataInReg[9:8] == 2'b01 || s_dataInReg[9:8] == 2'b10) && s_addressReg[3:2] == 2'b11 && 
                                  s_readNotWriteReg == 1'b0 && s_memAlignError == 1'b0 && s_spmAlignError == 1'b0 &&
                                  s_spmAddressError == 1'b0) ? ~s_transferSizeErrorReg : 1'b0;
  wire       s_weSourceDest    = (s_isMyTransaction == 1'b1 && s_slaveError == 1'b0 && s_dataInValidReg == 1'b1 && 
                                  s_addressReg[3:2] == 2'b00 && s_readNotWriteReg == 1'b0) ? 1'b1 : 1'b0;
  wire       s_weSpmAddr       = (s_isMyTransaction == 1'b1 && s_slaveError == 1'b0 && s_dataInValidReg == 1'b1 && 
                                  s_addressReg[3:2] == 2'b01 && s_readNotWriteReg == 1'b0) ? 1'b1 : 1'b0;
  wire       s_weTransSize     = (s_isMyTransaction == 1'b1 && s_slaveError == 1'b0 && s_dataInValidReg == 1'b1 && 
                                  s_addressReg[3:2] == 2'b10 && s_readNotWriteReg == 1'b0) ? 1'b1 : 1'b0;
  wire       s_writeSlaveData  = (s_isMyTransaction == 1'b1 && s_burstSizeError == 1'b0 && s_beginTransactionReg == 1'b1 && s_readNotWriteReg == 1'b1) ? 1'b1 : 1'b0;
  wire       s_writeBurstSize  = (s_isMyTransaction == 1'b1 && s_slaveError == 1'b0 && s_dataInValidReg == 1'b1 && 
                                  s_addressReg[3:2] == 2'b11 && s_readNotWriteReg == 1'b0 && s_dataInReg[9:8] == 2'b00) ? 1'b1 : 1'b0;
  wire [9:0] s_realBurstSize   = {1'b0,s_burstSizeReg} + 9'd1;

  always @*
    case (s_addressReg[3:2])
      2'd0    : s_slaveDataOutNext <= s_sourceDestinationAddressReg;
      2'd1    : s_slaveDataOutNext <= s_spmAddressReg;
      2'd2    : s_slaveDataOutNext <= s_transferSizeInWordsReg;
      default : s_slaveDataOutNext <= {26'd0, s_spmAddressError, s_spmAlignError, s_memAlignError, s_dmaTransferErrorReg, s_transferSizeErrorReg, s_dmaBusyReg};
    endcase

  always @(posedge clock)
    begin
      s_beginTransactionReg         <= beginTransactionIn;
      s_endTransactionReg           <= endTransactionIn;
      s_byteEnablesReg              <= (beginTransactionIn == 1'b1) ? byteEnablesIn : s_byteEnablesReg;
      s_transferActiveReg           <= (beginTransactionIn == 1'b1) ? 1'b1 : (reset == 1'b1 || s_endTransactionReg == 1'b1) ? 1'b0 : s_transferActiveReg;
      s_readNotWriteReg             <= (beginTransactionIn == 1'b1) ? readNotWriteIn : s_readNotWriteReg;
      s_dataInValidReg              <= dataValidIn;
      s_burstSizeInReg              <= (beginTransactionIn == 1'b1) ? burstSizeIn : s_burstSizeInReg;
      s_addressReg                  <= (beginTransactionIn == 1'b1) ? addressDataIn : s_addressReg;
      s_dataInReg                   <= (dataValidIn == 1'b1) ? addressDataIn : s_dataInReg;
      s_dmaBusyReg                  <= (reset == 1'b1 || s_dmaStateReg == GEN_IRQ) ? 1'b0 : (s_startDmaReg == 1'b1) ? endTransactionIn : s_dmaBusyReg;
      s_sourceDestinationAddressReg <= (reset == 1'b1) ? 32'd0 : (s_weSourceDest == 1'b1) ? s_dataInReg : s_sourceDestinationAddressReg;
      s_spmAddressReg               <= (reset == 1'b1) ? {spmBaseAddress[31:maxBit], {maxBit{1'b0}}} : (s_weSpmAddr == 1'b1) ? s_dataInReg : s_spmAddressReg;
      s_transferToSpmReg            <= (s_startDma == 1'b1) ? s_dataInReg[9] : s_transferToSpmReg;
      s_transferSizeInWordsReg      <= (reset == 1'b1) ? 32'd0 : (s_weTransSize == 1'b1) ? s_dataInReg : s_transferSizeInWordsReg;
      s_transferSizeErrorReg        <= (s_transferSizeInWordsReg > maxSize) ? 1'b1 : 1'b0;
      s_slaveDataOutValidReg        <= (s_writeSlaveData == 1'b1) ? 1'b1 : (s_isMyTransaction == 1'b1 && busyIn == 1'b1) ? s_slaveDataOutValidReg : 1'b0;
      s_slaveEndTransactionReg      <= (s_slaveDataOutValidReg == 1'b1 && busyIn == 1'b0) ? 1'b1 : 1'b0;
      s_slaveDataOutReg             <= (s_writeSlaveData == 1'b1) ? s_slaveDataOutNext : (s_isMyTransaction == 1'b1 && busyIn == 1'b1) ? s_slaveDataOutReg : 32'd0;
      s_startDmaReg                 <= (reset == 1'b1 || endTransactionIn == 1'b1) ? 1'b0 : s_startDma | s_startDmaReg;
      s_burstSizeReg                <= (reset == 1'b1) ? 8'h7 : (s_writeBurstSize == 1'b1) ? s_dataInReg[7:0] : s_burstSizeReg;
    end
  
  /*
   *
   * Here the master interface is defined
   *
   */
  reg [31:0]  s_currentAddressReg;
  reg [31:0]  s_currentSpmAddressReg;
  reg [31:0]  s_busAddressReg, s_dmaDataOutReg;
  reg [29:0]  s_remainingTransSizeReg;
  reg         s_beginTransactionOutReg, s_readNotWriteOutReg, s_dmaDataOutValidReg;
  reg [3:0]   s_byteEnablesOutReg;
  reg [7:0]   s_burstSizeOutReg;
  reg [8:0]   s_receivedWordsReg;
  wire        s_spmWe = (s_dmaStateReg == WAIT_READ_DATA) ? s_dataInValidReg & ~spmBusy : 1'b0;
  wire        s_doWrite = (s_dmaStateReg == DO_WRITE_DATA && s_receivedWordsReg[8] == 1'b0) ? ~busyIn : 1'd0;
  wire [7:0]  s_currentTransSize = (s_remainingTransSizeReg > {21'd0, s_realBurstSize}) ? s_burstSizeReg : s_remainingTransSizeReg[7:0] - 8'd1;
  wire [29:0] s_remainingTransSizeNext = (s_startDma == 1'd1) ? s_transferSizeInWordsReg[29:0] :
                                         (s_dmaStateReg == INIT_TRANSACTION) ? s_remainingTransSizeReg - {22'd0,s_currentTransSize} - 30'd1 : s_remainingTransSizeReg;
  wire [31:0] s_currentAddressNext = (s_startDma == 1'd1) ? s_sourceDestinationAddressReg :
                                     (s_dmaStateReg == INIT_TRANSACTION) ? s_currentAddressReg + {22'd0,s_currentTransSize,2'd0} + 30'd4 : s_currentAddressReg;
  wire [31:0] s_currentSpmAddressNext = (s_startDma == 1'd1) ? s_spmAddressReg : 
                                        (s_spmWe == 1'b1 || s_doWrite == 1'b1) ? s_currentSpmAddressReg + 32'd4 : s_currentSpmAddressReg;
  
  assign spmAddress = s_currentSpmAddressReg;
  assign spmWe      = s_spmWe;
  assign spmWeData  = s_dataInReg;
  
  always @*
    case (s_dmaStateReg)
      IDLE             : s_dmaStateNext <= (s_startDma == 1'd1) ? DECIDE : IDLE;
      DECIDE           : s_dmaStateNext <= (s_remainingTransSizeReg == 30'd0) ? GEN_IRQ : REQUEST_TRANS;
      REQUEST_TRANS    : s_dmaStateNext <= (transactionGranted == 1'b1) ? INIT_TRANSACTION : WAIT_TRANS_ACK;
      WAIT_TRANS_ACK   : s_dmaStateNext <= (transactionGranted == 1'b1) ? INIT_TRANSACTION : WAIT_TRANS_ACK;
      INIT_TRANSACTION : s_dmaStateNext <= (s_transferToSpmReg == 1'b1) ? WAIT_READ_DATA : DO_WRITE_DATA;
      WAIT_READ_DATA   : s_dmaStateNext <= (busErrorIn == 1'b1) ? ERROR : (s_endTransactionReg == 1'b1 && s_receivedWordsReg[8] == 1'b1) ? DECIDE : 
                         (s_endTransactionReg == 1'b1) ? ERROR : WAIT_READ_DATA;
      DO_WRITE_DATA    : s_dmaStateNext <= (busErrorIn == 1'b1) ? ERROR_STOP : (s_receivedWordsReg[8] == 1'b1 && busyIn == 1'b1) ? BUSY_WAIT :
                         (s_receivedWordsReg[8] == 1'b1) ? END_TRANSACTION : DO_WRITE_DATA;
      BUSY_WAIT        : s_dmaStateNext <= (busyIn == 1'b0) ? END_TRANSACTION : BUSY_WAIT;
      ERROR            : s_dmaStateNext <= (s_transferActiveReg == 1'b1) ? ERROR : GEN_IRQ;
      ERROR_STOP       : s_dmaStateNext <= END_TRANSACTION;
      END_TRANSACTION  : s_dmaStateNext <= (s_dmaTransferErrorReg == 1'b1) ? GEN_IRQ : DECIDE;
      default          : s_dmaStateNext <= IDLE;
    endcase
  
  always @(posedge clock)
    begin
      s_dmaStateReg            <= (reset == 1'b1) ? IDLE : s_dmaStateNext;
      s_remainingTransSizeReg  <= s_remainingTransSizeNext;
      s_currentAddressReg      <= s_currentAddressNext;
      s_currentSpmAddressReg   <= (reset == 1'b1) ? 32'd0 : s_currentSpmAddressNext;
      s_busAddressReg          <= (s_dmaStateReg == INIT_TRANSACTION) ? s_currentAddressReg : 32'd0;
      s_beginTransactionOutReg <= (s_dmaStateReg == INIT_TRANSACTION) ? 1'b1 : 1'b0;
      s_readNotWriteOutReg     <= (s_dmaStateReg == INIT_TRANSACTION) ? s_transferToSpmReg : 1'b0;
      s_byteEnablesOutReg      <= (s_dmaStateReg == INIT_TRANSACTION) ? 4'hF : 4'd0;
      s_burstSizeOutReg        <= (s_dmaStateReg == INIT_TRANSACTION) ? s_currentTransSize : 8'd0;
      s_receivedWordsReg       <= (s_dmaStateReg == INIT_TRANSACTION) ? {1'b0,s_currentTransSize} : (s_spmWe == 1'b1 || s_doWrite == 1'b1) ? s_receivedWordsReg - 8'd1 : s_receivedWordsReg;
      s_dmaTransferErrorReg    <= (reset == 1'b1 || s_dmaStateReg == DECIDE) ? 1'b0 : (s_dmaStateReg == ERROR || s_dmaStateReg == ERROR_STOP) ? 1'b1 : s_dmaTransferErrorReg;
      s_dmaDataOutValidReg     <= ((s_dmaStateReg != DO_WRITE_DATA || s_receivedWordsReg[8] == 1'b1) && busyIn == 1'b0) ? 1'b0 : s_doWrite | s_dmaDataOutValidReg;
      s_dmaDataOutReg          <= ((s_dmaStateReg != DO_WRITE_DATA || s_receivedWordsReg[8] == 1'b1) && busyIn == 1'b0) ? 32'd0 : (s_doWrite == 1'b1) ? spmReData : s_dmaDataOutReg;
    end
  
  /*
   *
   * here the bus output signals are defined
   *
   */
  assign irq                 = (s_dmaStateReg == GEN_IRQ) ? 1'b1 : 1'b0;
  assign requestTransaction  = (s_dmaStateReg == REQUEST_TRANS || s_dmaStateReg == WAIT_TRANS_ACK) ? 1'b1 : 1'b0;
  assign busErrorOut         = s_slaveError & ~s_endTransactionReg;
  assign endTransactionOut   = (s_dmaStateReg == END_TRANSACTION) ? 1'b1 : s_slaveEndTransactionReg;
  assign dataValidOut        = s_slaveDataOutValidReg | s_dmaDataOutValidReg;
  assign addressDataOut      = s_slaveDataOutReg | s_busAddressReg | s_dmaDataOutReg;
  assign beginTransactionOut = s_beginTransactionOutReg;
  assign readNotWriteOut     = s_readNotWriteOutReg;
  assign byteEnablesOut      = s_byteEnablesOutReg;
  assign burstSizeOut        = s_burstSizeOutReg;
  assign busyOut             = (s_dmaStateReg == WAIT_READ_DATA) ? dataValidIn & spmBusy : 1'b0;

endmodule
