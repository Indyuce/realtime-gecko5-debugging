module ssram_8k #( parameter [31:0] baseAddress = 32'h50000000)
                 ( input wire          clock,
                                       reset,
                       
                   // Here the bus interface is defined
                   input wire          beginTransactionIn,
                                       endTransactionIn,
                                       readNotWriteIn,
                                       dataValidIn,
                                       busyIn,
                                       busErrorIn,
                   input wire [31:0]   addressDataIn,
                   input wire [3:0]    byteEnablesIn,
                   input wire [7:0]    burstSizeIn,
                   output wire         endTransactionOut,
                   output wire         dataValidOut,
                   output wire [31:0]  addressDataOut
                 );

   /* here we define the bus registers */
   reg        s_beginTransactionInReg, s_dataValidReg, s_transactionActiveReg, s_readNotWriteReg;
   reg [31:0] s_addressDataInReg;
   reg [3:0]  s_byteEnablesReg;
   reg [8:0]  s_burstSizeReg;
   wire       s_isMyTransaction = (s_addressDataInReg[31:13] == baseAddress[31:13]) ? 
                                    s_beginTransactionInReg : 1'b0;
   wire       s_doRead;
   
   always @(posedge clock)
     begin
       s_transactionActiveReg  <= (reset == 1'b1 || endTransactionIn == 1'b1) ? 1'b0 :
                                    (beginTransactionIn == 1'b1) ? 1'b1 : s_transactionActiveReg;
       s_beginTransactionInReg <= beginTransactionIn;
       s_dataValidReg          <= dataValidIn;
       s_readNotWriteReg       <= (beginTransactionIn == 1'b1) ? readNotWriteIn : s_readNotWriteReg;
       s_addressDataInReg      <= addressDataIn;
       s_byteEnablesReg        <= (beginTransactionIn == 1'b1) ? byteEnablesIn : s_byteEnablesReg;
       s_burstSizeReg          <= (beginTransactionIn == 1'b1) ? {1'b0,burstSizeIn} : 
                                  (s_doRead == 1'b1) ? s_burstSizeReg - 9'd1 : s_burstSizeReg;
     end

   /* Here the state machine is defined */
   localparam [1:0] IDLE  = 2'd0;
   localparam [1:0] WRITE = 2'd1;
   localparam [1:0] READ  = 2'd2;
   localparam [1:0] ENDTRANS = 2'd3;
   
   reg [1:0] s_currentStateReg, s_nextState;
   
   assign endTransactionOut = (s_currentStateReg == ENDTRANS) ? 1'b1 : 1'b0;
   assign s_doRead = (s_currentStateReg == READ) ? ~busyIn && ~s_burstSizeReg[8] : 1'b0;
   
   always @*
     case (s_currentStateReg)
        IDLE      : s_nextState <= (s_isMyTransaction == 1'b1 && s_readNotWriteReg == 1'b0) ? WRITE :
                                   (s_isMyTransaction == 1'b1 && s_readNotWriteReg == 1'b1) ? READ :
                                   IDLE;
        WRITE     : s_nextState <= (busErrorIn == 1'b1 || s_transactionActiveReg == 1'b0) ? IDLE :
                                   WRITE;
        READ      : s_nextState <= (busErrorIn == 1'b1 || 
                                     (s_burstSizeReg[8] == 1'b1 && busyIn == 1'b0)) ? ENDTRANS :
                                   READ;
        default   : s_nextState <= IDLE;
     endcase
   
   always @(posedge clock)
     s_currentStateReg <= (reset == 1'b1) ? IDLE : s_nextState;
   
   /* here the memory is defined */
   reg [7:0] s_mem1 [2047:0];
   reg [7:0] s_mem2 [2047:0];
   reg [7:0] s_mem3 [2047:0];
   reg [7:0] s_mem4 [2047:0];
   reg [10:0] s_ramAddressReg;
   reg [31:0] s_readDataReg, s_dataOutReg;
   reg        s_dataValidOutReg;
   wire [10:0] s_ramAddressNext = (reset == 1'b1) ? 11'd0 :
                                  (s_isMyTransaction == 1'b1) ? s_addressDataInReg[12:2] :
                                  ((s_currentStateReg == WRITE && s_dataValidReg == 1'b1) ||
                                   (s_currentStateReg == READ && s_doRead == 1'b1)) ?
                                  s_ramAddressReg + 11'd1 : s_ramAddressReg;
   wire s_we1 = (s_currentStateReg == WRITE && s_dataValidReg == 1'b1) ? s_byteEnablesReg[0] : 1'b0;
   wire s_we2 = (s_currentStateReg == WRITE && s_dataValidReg == 1'b1) ? s_byteEnablesReg[1] : 1'b0;
   wire s_we3 = (s_currentStateReg == WRITE && s_dataValidReg == 1'b1) ? s_byteEnablesReg[2] : 1'b0;
   wire s_we4 = (s_currentStateReg == WRITE && s_dataValidReg == 1'b1) ? s_byteEnablesReg[3] : 1'b0;
   
   assign dataValidOut = s_dataValidOutReg;
   assign addressDataOut = s_dataOutReg;
   
   always @(posedge clock)
     begin
       s_ramAddressReg <= s_ramAddressNext;
       if (s_we1 == 1'b1) s_mem1[s_ramAddressReg] <= s_addressDataInReg[7:0];
       if (s_we2 == 1'b1) s_mem2[s_ramAddressReg] <= s_addressDataInReg[15:8];
       if (s_we3 == 1'b1) s_mem3[s_ramAddressReg] <= s_addressDataInReg[23:16];
       if (s_we4 == 1'b1) s_mem4[s_ramAddressReg] <= s_addressDataInReg[31:24];
       s_dataValidOutReg <= (s_doRead == 1'b1) ? 1'b1 :
                            (busyIn == 1'b1) ? s_dataValidOutReg : 1'b0;
       s_dataOutReg      <= (s_doRead == 1'b1) ? s_readDataReg :
                            (busyIn == 1'b1) ? s_dataOutReg : 32'd0;
     end
   
   always @(negedge clock)
     begin
       s_readDataReg[7:0]   <= s_mem1[s_ramAddressReg];
       s_readDataReg[15:8]  <= s_mem2[s_ramAddressReg];
       s_readDataReg[23:16] <= s_mem3[s_ramAddressReg];
       s_readDataReg[31:24] <= s_mem4[s_ramAddressReg];
     end
endmodule
