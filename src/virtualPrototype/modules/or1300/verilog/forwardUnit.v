module forwardUnit ( input wire         clock,
                                        stall,
                                        flush,
                                        
                     output wire [31:0] exeForwardOperantA,
                                        exeForwardOperantB,
                                        exeForwardStoreData,
                     output wire        exeUseForwardedOpA,
                                        exeUseForwardedOpB,
                                        exeUseForwardedStoreData,

                     output wire [31:0] rfForwardedOperantA,
                                        rfForwardedOperantB,
                                        rfForwardedStoreData,
                     output wire        rfUseForwardedOpA,
                                        rfUseForwardedOpB,
                                        rfUseForwardedStoreData,

                     input wire [4:0]   idOperantAAddr,
                                        idOperantBAddr,
                     input wire         idUseImmediate,
                                        idIsJump,
                     input wire [2:0]   idStore,
                     input wire [4:0]   writeAddress,
                     input wire         writeEnable,
                     input wire [4:0]   rfDestination,
                     input wire         rfWeDestination,
                     input wire [31:0]  writeData,
                     input wire [8:0]   dcacheRegisterAddress,
                     input wire         dcacheRegisterWe,
                     input wire [31:0]  dcacheRegisterData,
                     input wire [3:0]   cid,
                     input wire [4:0]   rfOperantAAddr,
                                        rfOperantBAddr,
                                        rfStoreAddr );

  /*
   *
   * here we define the forward signals for the register file
   *
   */
  wire s_dcacheForwardA = (dcacheRegisterWe == 1'b1 &&
                           dcacheRegisterAddress[8:5] == cid &&
                           dcacheRegisterAddress[4:0] == idOperantAAddr &&
                           idIsJump == 1'b0) ? 1'b1 : 1'b0;
  wire s_dcacheForwardB = (dcacheRegisterWe == 1'b1 &&
                           dcacheRegisterAddress[8:5] == cid &&
                           dcacheRegisterAddress[4:0] == idOperantBAddr &&
                           idIsJump == 1'b0) ? 1'b1 : 1'b0;
  wire s_dcacheForwardS = (dcacheRegisterWe == 1'b1 &&
                           dcacheRegisterAddress[8:5] == cid &&
                           dcacheRegisterAddress[4:0] == idOperantBAddr &&
                           idStore != 2'b00) ? 1'b1 : 1'b0;
  
  assign rfForwardedOperantA     = (s_dcacheForwardA == 1'b1) ? dcacheRegisterData : writeData;
  assign rfForwardedOperantB     = (s_dcacheForwardB == 1'b1) ? dcacheRegisterData : writeData;
  assign rfForwardedStoreData    = (s_dcacheForwardS == 1'b1) ? dcacheRegisterData : writeData;
  assign rfUseForwardedOpA       = ((writeEnable == 1'b1 &&
                                  //   idIsJump == 1'b0 &&
                                     idOperantAAddr != {5{1'b0}} &&
                                     idOperantAAddr == writeAddress) ||
                                    s_dcacheForwardA == 1'b1) ? 1'b1 : 1'b0;
  assign rfUseForwardedOpB       = ((writeEnable == 1'b1 &&
                                     idUseImmediate == 1'b0 &&
                                     idOperantBAddr != {5{1'b0}} &&
                                     idOperantBAddr == writeAddress) ||
                                    s_dcacheForwardB == 1'b1) ? 1'b1 : 1'b0;
  assign rfUseForwardedStoreData = ((writeEnable == 1'b1 &&
                                     idStore != 2'b00 &&
                                     idOperantBAddr != {5{1'b0}} &&
                                     idOperantBAddr == writeAddress) ||
                                    s_dcacheForwardS == 1'b1) ? 1'b1 : 1'b0;

  /*
   *
   * here we define the forward signals for the execution Unit
   *
   */
  reg s_forwardAReg, s_forwardBReg, s_forwardSReg;
  wire s_forwardANext = (stall == 1'b1) ? s_forwardAReg : (flush == 1'b1) ? 1'b0 :
                        (rfWeDestination == 1'b1 &&
                         idIsJump == 1'b0 &&
                         idOperantAAddr != {5{1'b0}} &&
                         idOperantAAddr == rfDestination) ? 1'b1 : 1'b0;
  wire s_forwardBNext = (stall == 1'b1) ? s_forwardBReg : (flush == 1'b1) ? 1'b0 :
                        (rfWeDestination == 1'b1 &&
                         idUseImmediate == 1'b0 &&
                         idOperantBAddr != {5{1'b0}} &&
                         idOperantBAddr == rfDestination) ? 1'b1 : 1'b0;
  wire s_forwardSNext = (stall == 1'b1) ? s_forwardSReg : (flush == 1'b1) ? 1'b0 :
                        (rfWeDestination == 1'b1 &&
                         idStore != 2'b00 &&
                         idOperantBAddr != {5{1'b0}} &&
                         idOperantBAddr == rfDestination) ? 1'b1 : 1'b0;

  assign exeForwardOperantA       = writeData;
  assign exeForwardOperantB       = writeData;
  assign exeForwardStoreData      = writeData;
  assign exeUseForwardedOpA       = s_forwardAReg;
  assign exeUseForwardedOpB       = s_forwardBReg;
  assign exeUseForwardedStoreData = s_forwardSReg;
    
  always @ (posedge clock)
    begin
      s_forwardAReg <= s_forwardANext;
      s_forwardBReg <= s_forwardBNext;
      s_forwardSReg <= s_forwardSNext;
    end
  
endmodule
