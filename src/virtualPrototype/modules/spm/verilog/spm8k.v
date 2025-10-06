module spm8k #(parameter [31:0] slaveBaseAddress = 0,
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

  reg         s_CsReg;
  reg [31:0]  s_dataFromSpmReg;
  wire [31:0] s_dmaAddress, s_dmaDataOut, s_dmaDataIn, s_lookupData;
  wire        s_dmaWe;
  wire s_weData = spmCs & spmWe;
  wire s_weMem1 = s_weData & spmByteEnables[0];
  wire s_weMem2 = s_weData & spmByteEnables[1];
  wire s_weMem3 = s_weData & spmByteEnables[2];
  wire s_weMem4 = s_weData & spmByteEnables[3];
  
  assign dataFromSpm = s_dataFromSpmReg;

  sram2048X8Dp mem1 ( .clockA(clock),
                      .writeEnableA(s_weMem1),
                      .addressA(spmAddress[10:0]),
                      .dataInA(dataToSpm[ 7:0 ]),
                      .dataOutA(s_lookupData[ 7:0 ]),
                      .clockB(~clock),
                      .writeEnableB(s_dmaWe),
                      .addressB(s_dmaAddress[12:2]),
                      .dataInB(s_dmaDataOut[ 7:0 ]),
                      .dataOutB(s_dmaDataIn[ 7:0 ]));

  sram2048X8Dp mem2 ( .clockA(clock),
                      .writeEnableA(s_weMem2),
                      .addressA(spmAddress[10:0]),
                      .dataInA(dataToSpm[15:8 ]),
                      .dataOutA(s_lookupData[15:8 ]),
                      .clockB(~clock),
                      .writeEnableB(s_dmaWe),
                      .addressB(s_dmaAddress[12:2]),
                      .dataInB(s_dmaDataOut[15:8 ]),
                      .dataOutB(s_dmaDataIn[15:8 ]));

  sram2048X8Dp mem3 ( .clockA(clock),
                      .writeEnableA(s_weMem3),
                      .addressA(spmAddress[10:0]),
                      .dataInA(dataToSpm[23:16]),
                      .dataOutA(s_lookupData[23:16]),
                      .clockB(~clock),
                      .writeEnableB(s_dmaWe),
                      .addressB(s_dmaAddress[12:2]),
                      .dataInB(s_dmaDataOut[23:16]),
                      .dataOutB(s_dmaDataIn[23:16]));

  sram2048X8Dp mem4 ( .clockA(clock),
                      .writeEnableA(s_weMem4),
                      .addressA(spmAddress[10:0]),
                      .dataInA(dataToSpm[31:24]),
                      .dataOutA(s_lookupData[31:24]),
                      .clockB(~clock),
                      .writeEnableB(s_dmaWe),
                      .addressB(s_dmaAddress[12:2]),
                      .dataInB(s_dmaDataOut[31:24]),
                      .dataOutB(s_dmaDataIn[31:24]));

  always @(posedge clock)
    begin
      s_CsReg          <= (reset == 1'b1) ? 1'b0 : spmCs;
      s_dataFromSpmReg <= (reset == 1'b1) ? 32'd0 : (s_CsReg == 1'b1) ? s_lookupData : s_dataFromSpmReg;
    end
   

  spmDma #(.slaveBaseAddress(slaveBaseAddress),
           .spmBaseAddress(spmBaseAddress),
           .spmSizeInBytes(8*1024)) dma
          (.clock(clock),
           .reset(reset),
           .irq(irq),
           .spmBusy(1'b0),
           .spmAddress(s_dmaAddress),
           .spmWe(s_dmaWe),
           .spmWeData(s_dmaDataOut),
           .spmReData(s_dmaDataIn),
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
