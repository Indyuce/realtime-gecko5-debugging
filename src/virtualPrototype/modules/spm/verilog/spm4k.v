module spm4k #(parameter [31:0] slaveBaseAddress = 0,
               parameter [31:0] spmBaseAddress = 32'hC0000000)
             ( input wire         clock,
                                  reset,
               input wire [31:0]  dataToSpm,
               output wire [31:0] dataFromSpm,
               input wire [17:0]  spmAddress,
               input wire [3:0]   spmByteEnables,
               input wire         spmCs,
               input wire         spmWe,
               output wire        irq,

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

  reg [31:0] s_lookupDataReg;
  wire [31:0] s_dmaAddress, s_dmaDataOut;
  wire        s_dmaWe;
  reg s_CsReg;
  wire [31:0] s_lookupData, s_dataToCore, s_writeData;
  reg [31:0] s_dataFromSpmReg;
  wire s_weData = spmCs & spmWe;
  wire [9:0] s_lookupAddress = (spmCs == 1'b1) ? spmAddress[9:0] : s_dmaAddress[11:2];
  wire s_clockNot = ~clock;
  
  assign dataFromSpm = s_dataFromSpmReg;
  assign s_writeData[7:0]   = (spmByteEnables[0] == 1'b1) ? dataToSpm[7:0] : s_lookupData[7:0];
  assign s_writeData[15:8]  = (spmByteEnables[1] == 1'b1) ? dataToSpm[15:8] : s_lookupData[15:8];
  assign s_writeData[23:16] = (spmByteEnables[2] == 1'b1) ? dataToSpm[23:16] : s_lookupData[23:16];
  assign s_writeData[31:24] = (spmByteEnables[3] == 1'b1) ? dataToSpm[31:24] : s_lookupData[31:24];

  sram1024X16Dp ramA ( .clockA(s_clockNot),
                       .writeEnableA(s_dmaWe),
                       .addressA(s_lookupAddress),
                       .dataInA(s_dmaDataOut[15:0]),
                       .dataOutA(s_lookupData[15:0]),
                       .clockB(clock),
                       .writeEnableB(s_weData),
                       .addressB(spmAddress[9:0]),
                       .dataInB(s_writeData[15:0]),
                       .dataOutB(s_dataToCore[15:0]));
  sram1024X16Dp ramB ( .clockA(s_clockNot),
                       .writeEnableA(s_dmaWe),
                       .addressA(s_lookupAddress),
                       .dataInA(s_dmaDataOut[31:16]),
                       .dataOutA(s_lookupData[31:16]),
                       .clockB(clock),
                       .writeEnableB(s_weData),
                       .addressB(spmAddress[9:0]),
                       .dataInB(s_writeData[31:16]),
                       .dataOutB(s_dataToCore[31:16]));

  always @(posedge clock)
    begin
      s_CsReg          <= (reset == 1'b1) ? 1'b0 : spmCs;
      s_dataFromSpmReg <= (reset == 1'b1) ? 32'd0 : (s_CsReg == 1'b1) ? s_dataToCore : s_dataFromSpmReg;
    end
  
  always @(posedge clock) s_lookupDataReg  <= (spmCs == 1'b0) ? s_lookupData : s_lookupDataReg;

  wire [31:0] s_dmaLookupData = (spmCs == 1'b1) ? s_lookupDataReg : s_lookupData;
   

  spmDma #(.slaveBaseAddress(slaveBaseAddress),
           .spmBaseAddress(spmBaseAddress),
           .spmSizeInBytes(4*1024)) dma
          (.clock(clock),
           .reset(reset),
           .irq(irq),
           .spmBusy(spmCs),
           .spmAddress(s_dmaAddress),
           .spmWe(s_dmaWe),
           .spmWeData(s_dmaDataOut),
           .spmReData(s_dmaLookupData),
           .requestTransaction(requestTransaction),
           .transactionGranted(transactionGranted),
           .beginTransactionIn(beginTransactionIn),
           .endTransactionIn(endTransactionIn),
           .readNotWriteIn(readNotWriteIn),
           .dataValidIn(dataValidIn),
           .busErrorIn(busErrorIn),
           .busyIn(busyIn),
           .addressDataIn(addressDataIn),
           .byteEnablesIn(byteEnablesIn),
           .burstSizeIn(burstSizeIn),
           .beginTransactionOut(beginTransactionOut),
           .endTransactionOut(endTransactionOut),
           .dataValidOut(dataValidOut),
           .readNotWriteOut(readNotWriteOut),
           .busErrorOut(busErrorOut),
           .busyOut(busyOut),
           .byteEnablesOut(byteEnablesOut),
           .burstSizeOut(burstSizeOut),
           .addressDataOut(addressDataOut));
endmodule
