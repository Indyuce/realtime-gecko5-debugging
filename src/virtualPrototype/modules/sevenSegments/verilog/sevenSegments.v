module sevenSegments #( parameter [31:0] initialBaseAddress = 32'h50000080)
                     ( input wire         clock,
                                          reset,
                       
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
                       input wire         oneKhzTick,
                       output wire [2:0]  displaySelect,
                       output wire [7:0]  nSegments
`else
                       output wire [7:0]  display1,
                                          display2,
                                          display3,
                                          display4
`endif
                      );

  /*
   *
   * Here the bus input interface is defined
   *
   */
  reg s_transactionActiveReg, s_readNotWriteReg, s_beginTransactionReg, s_dataInValidReg, s_endTransactionReg;
  reg [3:0]  s_byteEnablesReg;
  reg [7:0]  s_burstSizeReg;
  reg [31:0] s_busAddressReg, s_baseAddressReg, s_dataInReg;
  wire s_isMyTransaction = (s_transactionActiveReg == 1'b1 && s_busAddressReg[31:5] == s_baseAddressReg[31:5]) ? 1'b1 : 1'b0;
  wire s_busErrorOut = (s_isMyTransaction == 1'b1 && (s_byteEnablesReg != 4'hF || s_burstSizeReg != 8'd0)) ? 1'b1 : 1'b0;
  wire s_weBaseAddress = (s_isMyTransaction == 1'b1 && s_busAddressReg[4:2] == 3'd7 && s_readNotWriteReg == 1'b0 && s_busErrorOut == 1'b0) ? s_dataInValidReg : 1'b0;
  wire s_weSegments = (s_isMyTransaction == 1'b1 && s_readNotWriteReg == 1'b0 && s_busErrorOut == 1'b0) ? s_dataInValidReg : 1'b0;
  
  always @(posedge clock)
    begin
      s_transactionActiveReg <= (reset == 1'b1 || s_endTransactionReg == 1'b1) ? 1'b0 : s_transactionActiveReg | beginTransactionIn;
      s_busAddressReg        <= (beginTransactionIn == 1'b1) ? addressDataIn : s_busAddressReg;
      s_baseAddressReg       <= (reset == 1'b1) ? initialBaseAddress : (s_weBaseAddress) ? s_dataInReg : s_baseAddressReg;
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
   * Here we define the registers for the 4 seven segments
   *
   */
  reg [7:0]  s_displ1Reg, s_displ2Reg, s_displ3Reg, s_displ4Reg;
  wire [7:0] s_displ1Next, s_displ2Next, s_displ3Next, s_displ4Next;

`ifndef GECKO5Education
  assign display1 = s_displ1Reg;
  assign display2 = s_displ2Reg;
  assign display3 = s_displ3Reg;
  assign display4 = s_displ4Reg;
`endif

  sevenSegmentUpdate #( .segmentId(0) ) seg1
                      ( .currentValue(s_displ1Reg),
                        .dataIn(s_dataInReg),
                        .functionSelect(s_busAddressReg[4:2]),
                        .newValue(s_displ1Next) );
  
  sevenSegmentUpdate #( .segmentId(1) ) seg2
                      ( .currentValue(s_displ2Reg),
                        .dataIn(s_dataInReg),
                        .functionSelect(s_busAddressReg[4:2]),
                        .newValue(s_displ2Next) );
  
  sevenSegmentUpdate #( .segmentId(2) ) seg3
                      ( .currentValue(s_displ3Reg),
                        .dataIn(s_dataInReg),
                        .functionSelect(s_busAddressReg[4:2]),
                        .newValue(s_displ3Next) );
  
  sevenSegmentUpdate #( .segmentId(3) ) seg4
                      ( .currentValue(s_displ4Reg),
                        .dataIn(s_dataInReg),
                        .functionSelect(s_busAddressReg[4:2]),
                        .newValue(s_displ4Next) );
  
  always @(posedge clock)
    begin
      s_displ1Reg <= (reset == 1'b1) ? 8'd0 : (s_weSegments == 1'b1) ? s_displ1Next : s_displ1Reg;
      s_displ2Reg <= (reset == 1'b1) ? 8'd0 : (s_weSegments == 1'b1) ? s_displ2Next : s_displ2Reg;
      s_displ3Reg <= (reset == 1'b1) ? 8'd0 : (s_weSegments == 1'b1) ? s_displ3Next : s_displ3Reg;
      s_displ4Reg <= (reset == 1'b1) ? 8'd0 : (s_weSegments == 1'b1) ? s_displ4Next : s_displ4Reg;
    end

`ifdef GECKO5Education
  reg [2:0] s_scanReg;
  
  assign displaySelect = s_scanReg;
  
  always @(posedge clock) s_scanReg <= (reset == 1'b1 || (s_scanReg == 3'd0 && oneKhzTick == 1'b1)) ? 3'd4 : (oneKhzTick == 1'b1) ? s_scanReg - 3'd1 : s_scanReg;
  
  reg [7:0] s_selectedSegment;
  
  assign nSegments = ~s_selectedSegment;
  
  always @*
    case (s_scanReg)
      3'd0    : s_selectedSegment <= s_displ4Reg;
      3'd1    : s_selectedSegment <= s_displ3Reg;
      3'd2    : s_selectedSegment <= s_displ2Reg;
      3'd3    : s_selectedSegment <= s_displ1Reg;
      default : s_selectedSegment <= 8'd0;
    endcase
`endif
  
  /*
   *
   * Here the bus output signals are defined
   *
   */
  reg [31:0] s_busDataOutReg, s_busDataOutNext;
  reg s_busDataOutValidReg, s_endTransactionOutReg;
  wire s_isMyRead = s_isMyTransaction & s_readNotWriteReg & s_beginTransactionReg;
  
  assign endTransactionOut = s_endTransactionOutReg;
  assign dataValidOut = s_busDataOutValidReg;
  assign addressDataOut = s_busDataOutReg;

  always @*
    case (s_busAddressReg[4:2])
      3'd7   : s_busDataOutNext <= s_baseAddressReg;
      3'd0,
      3'd4   : s_busDataOutNext <= {24'd0, s_displ1Reg};
      3'd1,
      3'd5   : s_busDataOutNext <= {24'd0, s_displ2Reg};
      3'd2,
      3'd6   : s_busDataOutNext <= {24'd0, s_displ3Reg};
      default: s_busDataOutNext <= {24'd0, s_displ4Reg};
    endcase
   
  always @(posedge clock)
    begin
      s_busDataOutReg        <= (s_isMyRead == 1'b1) ? s_busDataOutNext : (busyIn == 1'b1) ? s_busDataOutReg : 32'h0;
      s_busDataOutValidReg   <= (s_isMyRead == 1'b1) ? 1'b1 : (busyIn == 1'b1) ? s_busDataOutValidReg : 1'b0;
      s_endTransactionOutReg <= (s_busDataOutValidReg == 1'b1 && busyIn == 1'b0) ? 1'b1 : 1'b0;
    end
endmodule
