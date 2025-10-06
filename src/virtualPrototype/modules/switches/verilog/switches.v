module switches #( parameter        cpuFrequencyInHz = 4285800,
                   parameter [31:0] baseAddress = 32'h50000000)
                ( input wire         clock,
                                     reset,
                  output reg         oneKHzTick,
                  output wire        irqDip,
                  output wire        irqJoy,

                  // Here the bus interface is defined
                  input wire         beginTransactionIn,
                                     endTransactionIn,
                                     readNotWriteIn,
                                     dataValidIn,
                                     busyIn,
                  input wire [31:0]  addressDataIn,
                  input wire [3:0]   byteEnablesIn,
                  input wire [7:0]   burstSizeIn,
                  output wire        endTransactionOut,
                                     dataValidOut,
                  output reg         busErrorOut,
                  output wire [31:0] addressDataOut,
`ifdef GECKO5Education
                  input wire [4:0]   nButtons, 
                  input wire [7:0]   nDipSwitch,
                  input wire [4:0]   nJoystick
`else
                  input wire [6:1]   nButtons, // nButtons[0] is dedicated for reset
                  input wire [7:0]   nDipSwitch1,
                  input wire [7:0]   nDipSwitch2
`endif
                );

  reg s_busDataOutValidReg;
  /*
   *
   * Here the bus input interface is defined
   *
   */
  reg s_transactionActiveReg, s_readNotWriteReg, s_beginTransactionReg, s_dataInValidReg, s_endTransactionReg;
  reg [3:0]  s_byteEnablesReg;
  reg [7:0]  s_burstSizeReg;
  reg [31:0] s_busAddressReg, s_dataInReg;
  wire s_isMyTransaction = (s_transactionActiveReg == 1'b1 && s_busAddressReg[31:5] == baseAddress[31:5]) ? 1'b1 : 1'b0;
  wire s_busErrorOut = (s_isMyTransaction == 1'b1 && (s_byteEnablesReg != 4'hF || s_burstSizeReg != 8'd0)) ? 1'b1 : 1'b0;
  
  always @(posedge clock)
    begin
      s_transactionActiveReg <= (reset == 1'b1 || s_endTransactionReg == 1'b1) ? 1'b0 : s_transactionActiveReg | beginTransactionIn;
      s_busAddressReg        <= (beginTransactionIn == 1'b1) ? addressDataIn : s_busAddressReg;
      s_readNotWriteReg      <= (beginTransactionIn == 1'b1) ? readNotWriteIn : s_readNotWriteReg;
      s_byteEnablesReg       <= (beginTransactionIn == 1'b1) ? byteEnablesIn : s_byteEnablesReg;
      s_burstSizeReg         <= (beginTransactionIn == 1'b1) ? burstSizeIn : s_burstSizeReg;
      s_beginTransactionReg  <= beginTransactionIn;
      s_dataInReg            <= (dataValidIn == 1'b1) ? addressDataIn : s_dataInReg;
      s_dataInValidReg       <= dataValidIn;
      s_endTransactionReg    <= endTransactionIn;
      busErrorOut            <= (reset == 1'b1 || endTransactionIn == 1'b1 || s_endTransactionReg == 1'b1) ? 1'b0 : s_busErrorOut;
    end

  /*
   *
   * Here we define the one kHz tick timer
   *
   */  
  function integer clog2;
    input integer value;
    begin
      for (clog2 = 0; value > 0 ; clog2= clog2 + 1)
      value = value >> 1;
    end
  endfunction

  localparam scanDivideValue = cpuFrequencyInHz/1000;
  localparam nrOfBits = clog2(scanDivideValue);
  
  reg [nrOfBits:0] s_tickCounterReg;
  wire s_tick = (s_tickCounterReg == 0) ? 1'b1 : 1'b0;
  
  always @(posedge clock) 
    begin
      s_tickCounterReg <= (reset == 1'b1 || s_tick == 1'b1) ? scanDivideValue - 1 : s_tickCounterReg - 1;
      oneKHzTick       <= s_tick;
    end

  /*
   *
   * Here we define the IRQ enable masks
   *
   */
  reg [15:0]  s_dipSwitchPressedIrqMaskReg, s_dipSwitchReleasedIrqMaskReg;
  reg [9:0]   s_joystickPressedIrqMaskReg, s_joystickReleasedIrqMaskReg;
  reg [1:0]   s_irqDipReg, s_irqJoyReg;
  wire [15:0] s_dipswitchPressedIrqs, s_dipSwitchReleasedIrqs;
  wire [9:0]  s_joystickPressedIrqs, s_joystickReleasedIrqs;
  wire s_clearAllIrqMasks = (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b1 && s_busAddressReg[4:2] == 3'd7) ? ~s_busErrorOut : 1'b0;
  wire s_weDipSwitchPressedIrqMask = (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b0 && s_busAddressReg[4:2] == 3'd1) ? ~s_busErrorOut : 1'b0;
  wire s_weDipSwitchReleasedIrqMask = (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b0 && s_busAddressReg[4:2] == 3'd2) ? ~s_busErrorOut : 1'b0;
  wire s_clearDipSwitchPressedIrqs = ((s_isMyTransaction == 1'b1 && s_busDataOutValidReg == 1'b1 && s_readNotWriteReg == 1'b1 && s_busAddressReg[4:2] == 3'd1) ||
                                      (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b0 && s_busAddressReg[4:2] == 3'd7)) ? ~s_busErrorOut : 1'b0;
  wire s_clearDipSwitchReleasedIrqMask = ((s_isMyTransaction == 1'b1 && s_busDataOutValidReg == 1'b1 && s_readNotWriteReg == 1'b1 && s_busAddressReg[4:2] == 3'd2) ||
                                          (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b0 && s_busAddressReg[4:2] == 3'd7)) ? ~s_busErrorOut : 1'b0;
  wire s_weJoystickPressedIrqMask = (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b0 && s_busAddressReg[4:2] == 3'd4) ? ~s_busErrorOut : 1'b0;
  wire s_weJoystickReleasedIrqMask = (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b0 && s_busAddressReg[4:2] == 3'd5) ? ~s_busErrorOut : 1'b0;
  wire s_clearJoystickPressedIrqs = ((s_isMyTransaction == 1'b1 && s_busDataOutValidReg == 1'b1 && s_readNotWriteReg == 1'b1 && s_busAddressReg[4:2] == 3'd4) ||
                                     (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b0 && s_busAddressReg[4:2] == 3'd7)) ? ~s_busErrorOut : 1'b0;
  wire s_clearJoystickReleasedIrqMask = ((s_isMyTransaction == 1'b1 && s_busDataOutValidReg == 1'b1 && s_readNotWriteReg == 1'b1 && s_busAddressReg[4:2] == 3'd5) ||
                                         (s_isMyTransaction == 1'b1 && s_dataInValidReg == 1'b1 && s_readNotWriteReg == 1'b0 && s_busAddressReg[4:2] == 3'd7)) ? ~s_busErrorOut : 1'b0;
  
  assign irqDip = s_irqDipReg[0];
  assign irqJoy = s_irqJoyReg[0];
  
  always @(posedge clock)
    begin
      s_dipSwitchPressedIrqMaskReg  <= (reset == 1'b1 || s_clearAllIrqMasks == 1'b1) ? 16'd0 : (s_weDipSwitchPressedIrqMask == 1'b1) ? s_dataInReg[15:0] : s_dipSwitchPressedIrqMaskReg;
      s_dipSwitchReleasedIrqMaskReg <= (reset == 1'b1 || s_clearAllIrqMasks == 1'b1) ? 16'd0 : (s_weDipSwitchReleasedIrqMask == 1'b1) ? s_dataInReg[15:0] : s_dipSwitchReleasedIrqMaskReg;
      s_joystickPressedIrqMaskReg   <= (reset == 1'b1 || s_clearAllIrqMasks == 1'b1) ? 10'd0 : (s_weJoystickPressedIrqMask == 1'b1) ? s_dataInReg[9:0] : s_joystickPressedIrqMaskReg;
      s_joystickReleasedIrqMaskReg  <= (reset == 1'b1 || s_clearAllIrqMasks == 1'b1) ? 10'd0 : (s_weJoystickReleasedIrqMask == 1'b1) ? s_dataInReg[9:0] : s_joystickReleasedIrqMaskReg;
      s_irqDipReg[0]                <= (s_dipswitchPressedIrqs != 16'd0 || s_dipSwitchReleasedIrqs != 16'd0) ? 1'b1 : 1'b0;
      s_irqDipReg[1]                <= (reset == 1'b1) ? 1'b0 : s_irqDipReg[0];
      s_irqJoyReg[0]                <= (s_joystickPressedIrqs != 10'd0 || s_joystickReleasedIrqs != 10'd0) ? 1'b1 : 1'b0;
      s_irqJoyReg[1]                <= (reset == 1'b1) ? 1'b0 : s_irqJoyReg[0];
    end
  
  /*
   *
   * Here we define the irq responce delay counter
   *
   */
  reg s_countActiveReg;
  reg [31:0] s_delayCounterReg;
  wire s_startCount = (s_irqDipReg[0] & ~s_irqDipReg[1]) | (s_irqJoyReg[0] & ~s_irqJoyReg[1]);
  wire s_stopCount = (s_irqDipReg[1] & ~s_irqDipReg[0]) | (s_irqJoyReg[1] & ~s_irqJoyReg[0]);
  
  always @(posedge clock)
    begin
      s_countActiveReg  <= (reset == 1'b1 || s_stopCount == 1'b1) ? 1'b0 : s_countActiveReg | s_startCount;
      s_delayCounterReg <= (reset == 1'b1 || s_startCount == 1'b1) ? 32'd0 : (s_countActiveReg == 1'b1 && s_delayCounterReg[31] == 1'b0) ? s_delayCounterReg + 32'd1 : s_delayCounterReg;
    end

  /*
   *
   * here we insert the anti-dender modules
   *
   *
   */
  genvar n;
  wire [15:0] s_dipswitchState;
  wire [9:0]  s_joystickState;
`ifdef GECKO5Education
  assign s_dipswitchPressedIrqs[15:8] = 8'd0;
  assign s_dipSwitchReleasedIrqs[15:8] = 8'd0;
  assign s_dipswitchState[15:8] = 8'd0;
  
  generate
     for (n = 0; n < 8 ; n = n + 1)
       begin : dipsw
         debouncerWithIrq debounce ( .clock(clock),
                                     .reset(reset),
                                     .nButtonIn(nDipSwitch[n]),
                                     .scanTick(s_tick),
                                     .enablePressIrq(s_dipSwitchPressedIrqMaskReg[n]),
                                     .enableReleaseIrq(s_dipSwitchReleasedIrqMaskReg[n]),
                                     .resetPressIrq(s_clearDipSwitchPressedIrqs),
                                     .resetReleaseIrq(s_clearDipSwitchReleasedIrqMask),
                                     .pressIrq(s_dipswitchPressedIrqs[n]),
                                     .releasIrq(s_dipSwitchReleasedIrqs[n]),
                                     .currentState(s_dipswitchState[n]) );
       end
     for (n = 0; n < 5 ; n = n + 1)
       begin : joy
         debouncerWithIrq debounce ( .clock(clock),
                                     .reset(reset),
                                     .nButtonIn(nJoystick[n]),
                                     .scanTick(s_tick),
                                     .enablePressIrq(s_joystickPressedIrqMaskReg[n]),
                                     .enableReleaseIrq(s_joystickReleasedIrqMaskReg[n]),
                                     .resetPressIrq(s_clearJoystickPressedIrqs),
                                     .resetReleaseIrq(s_clearJoystickReleasedIrqMask),
                                     .pressIrq(s_joystickPressedIrqs[n]),
                                     .releasIrq(s_joystickReleasedIrqs[n]),
                                     .currentState(s_joystickState[n]) );
       end
     for (n = 0; n < 5 ; n = n + 1)
       begin : but
         debouncerWithIrq debounce ( .clock(clock),
                                     .reset(reset),
                                     .nButtonIn(nButtons[n]),
                                     .scanTick(s_tick),
                                     .enablePressIrq(s_joystickPressedIrqMaskReg[n+5]),
                                     .enableReleaseIrq(s_joystickReleasedIrqMaskReg[n+5]),
                                     .resetPressIrq(s_clearJoystickPressedIrqs),
                                     .resetReleaseIrq(s_clearJoystickReleasedIrqMask),
                                     .pressIrq(s_joystickPressedIrqs[n+5]),
                                     .releasIrq(s_joystickReleasedIrqs[n+5]),
                                     .currentState(s_joystickState[n+5]) );
       end
  endgenerate
`else
  assign s_joystickPressedIrqs[9:6] = 4'd0;
  assign s_joystickReleasedIrqs[9:6] = 4'd0;
  assign s_joystickState[9:6] = 4'd0;
  generate
     for (n = 0; n < 8 ; n = n + 1)
       begin : dipsw
         debouncerWithIrq debounce1 ( .clock(clock),
                                     .reset(reset),
                                     .nButtonIn(nDipSwitch1[n]),
                                     .scanTick(s_tick),
                                     .enablePressIrq(s_dipSwitchPressedIrqMaskReg[n]),
                                     .enableReleaseIrq(s_dipSwitchReleasedIrqMaskReg[n]),
                                     .resetPressIrq(s_clearDipSwitchPressedIrqs),
                                     .resetReleaseIrq(s_clearDipSwitchReleasedIrqMask),
                                     .pressIrq(s_dipswitchPressedIrqs[n]),
                                     .releasIrq(s_dipSwitchReleasedIrqs[n]),
                                     .currentState(s_dipswitchState[n]) );
         debouncerWithIrq debounce2 ( .clock(clock),
                                     .reset(reset),
                                     .nButtonIn(nDipSwitch2[n]),
                                     .scanTick(s_tick),
                                     .enablePressIrq(s_dipSwitchPressedIrqMaskReg[n+8]),
                                     .enableReleaseIrq(s_dipSwitchReleasedIrqMaskReg[n+8]),
                                     .resetPressIrq(s_clearDipSwitchPressedIrqs),
                                     .resetReleaseIrq(s_clearDipSwitchReleasedIrqMask),
                                     .pressIrq(s_dipswitchPressedIrqs[n+8]),
                                     .releasIrq(s_dipSwitchReleasedIrqs[n+8]),
                                     .currentState(s_dipswitchState[n+8]) );
       end
     for (n = 1; n < 7 ; n = n + 1)
       begin : but
         debouncerWithIrq debounce ( .clock(clock),
                                     .reset(reset),
                                     .nButtonIn(nButtons[n]),
                                     .scanTick(s_tick),
                                     .enablePressIrq(s_joystickPressedIrqMaskReg[n-1]),
                                     .enableReleaseIrq(s_joystickReleasedIrqMaskReg[n-1]),
                                     .resetPressIrq(s_clearJoystickPressedIrqs),
                                     .resetReleaseIrq(s_clearJoystickReleasedIrqMask),
                                     .pressIrq(s_joystickPressedIrqs[n-1]),
                                     .releasIrq(s_joystickReleasedIrqs[n-1]),
                                     .currentState(s_joystickState[n-1]) );
       end
  endgenerate
`endif
  
  /*
   *
   * Here the bus output signals are defined
   *
   */
  reg [31:0] s_busDataOutReg, s_busDataOutNext;
  reg s_endTransactionOutReg;
  wire s_isMyRead = s_isMyTransaction & s_readNotWriteReg & s_beginTransactionReg;
  
  assign endTransactionOut = s_endTransactionOutReg;
  assign dataValidOut = s_busDataOutValidReg;
  assign addressDataOut = s_busDataOutReg;

  always @*
    case (s_busAddressReg[4:2])
      3'd0    : s_busDataOutNext <= {16'd0, s_dipswitchState};
      3'd1    : s_busDataOutNext <= {16'd0, s_dipswitchPressedIrqs};
      3'd2    : s_busDataOutNext <= {16'd0, s_dipSwitchReleasedIrqs};
      3'd3    : s_busDataOutNext <= {22'd0, s_joystickState};
      3'd4    : s_busDataOutNext <= {22'd0, s_joystickPressedIrqs};
      3'd5    : s_busDataOutNext <= {22'd0, s_joystickReleasedIrqs};
      3'd6    : s_busDataOutNext <= s_delayCounterReg;
      default : s_busDataOutNext <= 32'd0;
    endcase
   
  always @(posedge clock)
    begin
      s_busDataOutReg        <= (s_isMyRead == 1'b1) ? s_busDataOutNext : (busyIn == 1'b1) ? s_busDataOutReg : 32'h0;
      s_busDataOutValidReg   <= (s_isMyRead == 1'b1) ? 1'b1 : (busyIn == 1'b1) ? s_busDataOutValidReg : 1'b0;
      s_endTransactionOutReg <= (s_busDataOutValidReg == 1'b1 && busyIn == 1'b0) ? 1'b1 : 1'b0;
    end
endmodule
