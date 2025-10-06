module profilingModule ( input wire        reset,
                                           clock,
                                           stall,
                                           weSpsr,
                                           profilingActive,
                         input wire [15:0] spsrWriteIndex,
                         input wire [31:0] dataFromCore,
                         input wire        profilingInstructionFetch,
                                           profilingICacheMiss,
                                           profilingICacheMissActive,
                                           profilingICacheFlushActive,
                                           profilingICacheInsertedNop,
                                           profilingDCacheUncachedWrite,
                                           profilingDCacheUncachedRead,
                                           profilingDCacheCachedWrite,
                                           profilingDCacheCachedRead,
                                           profilingDCacheSwap,
                                           profilingDCacheCas,
                                           profilingDCacheMiss,
                                           profilingDCacheWriteBack,
                                           profilingDCacheDataStall,
                                           profilingDCacheWriteStall,
                                           profilingDCacheProcessorStall,
                                           profilingDCacheStall,
                                           profilingDCacheWriteThrough,
                                           profilingDCacheInvalidate,
                                           profilingBranchPenalty,
                                           profilingComittedInstruction,
                                           profilingStall,
                                           busIdle,
                                           snoopableBurst,
                         input wire [15:0] spsrReadIndex,
                         output wire [31:0] dataToCore );

        wire [31:0] s_cpuEvents;
        assign s_cpuEvents[31:30] = 2'd0;
        assign s_cpuEvents[29]  = profilingDCacheInvalidate;
        assign s_cpuEvents[28]  = 1'b0;
        assign s_cpuEvents[27]  = profilingDCacheStall;
        assign s_cpuEvents[26]  = profilingDCacheProcessorStall;
        assign s_cpuEvents[25]  = profilingDCacheWriteStall;
        assign s_cpuEvents[24]  = profilingDCacheDataStall;
        assign s_cpuEvents[23]  = profilingDCacheWriteBack;
        assign s_cpuEvents[22]  = profilingDCacheMiss;
        assign s_cpuEvents[21]  = profilingDCacheCas;
        assign s_cpuEvents[20]  = profilingDCacheSwap;
        assign s_cpuEvents[19]  = profilingDCacheCachedRead;
        assign s_cpuEvents[18]  = profilingDCacheCachedWrite;
        assign s_cpuEvents[17]  = profilingDCacheUncachedRead;
        assign s_cpuEvents[16]  = profilingDCacheUncachedWrite;
        assign s_cpuEvents[15]  = 1'b0;
        assign s_cpuEvents[14]  = 1'b0;
        assign s_cpuEvents[13]  = snoopableBurst;
        assign s_cpuEvents[12]  = busIdle;
        assign s_cpuEvents[11]  = profilingStall;
        assign s_cpuEvents[10]  = profilingComittedInstruction;
        assign s_cpuEvents[9]   = profilingBranchPenalty;
        assign s_cpuEvents[8:5] = 4'b0; 
        assign s_cpuEvents[4]   = profilingICacheInsertedNop;
        assign s_cpuEvents[3]   = profilingICacheFlushActive;
        assign s_cpuEvents[2]   = profilingICacheMissActive;
        assign s_cpuEvents[1]   = profilingICacheMiss;
        assign s_cpuEvents[0]   = profilingInstructionFetch;

        reg s_profileRequestReg, s_profileEnableReg, s_profilePauseReg, s_resetCountersReg;
        wire s_weControlWord = spsrWriteIndex == 16'hF800 ? weSpsr & ~ stall : 1'b0;

        /*
         * Here we define the general control signals of the profiling module
         *
         */
        always @(posedge clock)
          if (reset == 1'b1)
            begin
              s_profileRequestReg <= 1'b0;
              s_profileEnableReg  <= 1'b0;
              s_profilePauseReg   <= 1'b0;
              s_resetCountersReg  <= 1'b1;
            end
          else
            begin
              s_profileRequestReg <= profilingActive;
              s_resetCountersReg  <= s_weControlWord & ~s_profileEnableReg & dataFromCore[9];
              if (s_weControlWord == 1'b1)
                begin
                  s_profileEnableReg <= dataFromCore[9];
                  s_profilePauseReg  <= dataFromCore[10];
                end
            end

        /*
         * Here we define the mask registers and the counters
         *
         */
        reg [31:0] s_countMaskRegs [7:0];
        wire [63:0] s_profileCounterReg [7:0];
        wire s_weCountMaskReg [7:0];
        genvar n;

        assign s_weCountMaskReg[0] = spsrWriteIndex == 16'hF801 ? ~s_profileEnableReg & ~stall & weSpsr : 1'b0;
        assign s_weCountMaskReg[1] = spsrWriteIndex == 16'hF802 ? ~s_profileEnableReg & ~stall & weSpsr : 1'b0;
        assign s_weCountMaskReg[2] = spsrWriteIndex == 16'hF803 ? ~s_profileEnableReg & ~stall & weSpsr : 1'b0;
        assign s_weCountMaskReg[3] = spsrWriteIndex == 16'hF804 ? ~s_profileEnableReg & ~stall & weSpsr : 1'b0;
        assign s_weCountMaskReg[4] = spsrWriteIndex == 16'hF805 ? ~s_profileEnableReg & ~stall & weSpsr : 1'b0;
        assign s_weCountMaskReg[5] = spsrWriteIndex == 16'hF806 ? ~s_profileEnableReg & ~stall & weSpsr : 1'b0;
        assign s_weCountMaskReg[6] = spsrWriteIndex == 16'hF807 ? ~s_profileEnableReg & ~stall & weSpsr : 1'b0;
        assign s_weCountMaskReg[7] = spsrWriteIndex == 16'hF808 ? ~s_profileEnableReg & ~stall & weSpsr : 1'b0;
		  generate
        for (n = 0 ; n < 8; n = n + 1)
          begin:counter
            always @(posedge clock)
              if (reset == 1'b1) s_countMaskRegs[n] <= {32{1'b0}};
              else if (s_weCountMaskReg[n] == 1'b1) s_countMaskRegs[n] <= dataFromCore;
        
            profileCounter counter ( .clock(clock),
                                     .resetCounter(s_resetCountersReg),
                                     .counterEnabled(s_profileEnableReg),
                                     .counterPaused(s_profilePauseReg),
                                     .counterMask(s_countMaskRegs[n]),
                                     .cpuEvents(s_cpuEvents),
                                     .counterValue(s_profileCounterReg[n]) );
          end
		  endgenerate

        wire [63:0] s_cycleCounterReg, s_profileCountReg;
          profileCounter cycleCounter ( .clock(clock),
                                        .resetCounter(s_resetCountersReg),
                                        .counterEnabled(s_profileEnableReg),
                                        .counterPaused(s_profilePauseReg),
                                        .counterMask({32{1'b1}}),
                                        .cpuEvents({32{1'b1}}),
                                        .counterValue(s_cycleCounterReg) );
          profileCounter profCounter ( .clock(clock),
                                       .resetCounter(s_resetCountersReg),
                                       .counterEnabled(s_profileEnableReg),
                                       .counterPaused(1'b0),
                                       .counterMask({32{1'b1}}),
                                       .cpuEvents({32{1'b1}}),
                                       .counterValue(s_profileCountReg) );

        /*
         *
         * Here we define the values send to the core
         *
         */
        wire [31:0] s_profileStatusWord;
        reg [31:0] s_dataToCore;
        assign s_profileStatusWord[31:17] = 0;
        assign s_profileStatusWord[16] = s_profileRequestReg;
        assign s_profileStatusWord[15:11] = 0;
        assign s_profileStatusWord[10] = s_profilePauseReg;
        assign s_profileStatusWord[9] = s_profileEnableReg;
        assign s_profileStatusWord[8:0] = {9{1'b1}};
        assign dataToCore = s_dataToCore;

        always @*
          case (spsrReadIndex[4:0])
            5'b00000 : s_dataToCore <= s_profileStatusWord;
            5'b00001 : s_dataToCore <= s_countMaskRegs[0];
            5'b00010 : s_dataToCore <= s_countMaskRegs[1];
            5'b00011 : s_dataToCore <= s_countMaskRegs[2];
            5'b00100 : s_dataToCore <= s_countMaskRegs[3];
            5'b00101 : s_dataToCore <= s_countMaskRegs[4];
            5'b00110 : s_dataToCore <= s_countMaskRegs[5];
            5'b00111 : s_dataToCore <= s_countMaskRegs[6];
            5'b01000 : s_dataToCore <= s_countMaskRegs[7];
            5'b01001 : s_dataToCore <= s_cycleCounterReg[31:0];
            5'b01010 : s_dataToCore <= s_cycleCounterReg[63:32];
            5'b01011 : s_dataToCore <= s_profileCounterReg[0][31:0];
            5'b01100 : s_dataToCore <= s_profileCounterReg[0][63:32];
            5'b01101 : s_dataToCore <= s_profileCounterReg[1][31:0];
            5'b01110 : s_dataToCore <= s_profileCounterReg[1][63:32];
            5'b01111 : s_dataToCore <= s_profileCounterReg[2][31:0];
            5'b10000 : s_dataToCore <= s_profileCounterReg[2][63:32];
            5'b10001 : s_dataToCore <= s_profileCounterReg[3][31:0];
            5'b10010 : s_dataToCore <= s_profileCounterReg[3][63:32];
            5'b10011 : s_dataToCore <= s_profileCounterReg[4][31:0];
            5'b10100 : s_dataToCore <= s_profileCounterReg[4][63:32];
            5'b10101 : s_dataToCore <= s_profileCounterReg[5][31:0];
            5'b10110 : s_dataToCore <= s_profileCounterReg[5][63:32];
            5'b10111 : s_dataToCore <= s_profileCounterReg[6][31:0];
            5'b11000 : s_dataToCore <= s_profileCounterReg[6][63:32];
            5'b11001 : s_dataToCore <= s_profileCounterReg[7][31:0];
            5'b11010 : s_dataToCore <= s_profileCounterReg[7][63:32];
            5'b11011 : s_dataToCore <= s_profileCountReg[31:0];
            5'b11100 : s_dataToCore <= s_profileCountReg[63:32];
            default  : s_dataToCore <= {32{1'b0}};
          endcase
endmodule
