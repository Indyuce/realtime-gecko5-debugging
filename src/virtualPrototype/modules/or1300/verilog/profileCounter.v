module profileCounter ( input wire         clock,
                                           resetCounter,
                                           counterEnabled,
                                           counterPaused,
                        input wire [31:0]  counterMask,
                                           cpuEvents,
                        output wire [63:0] counterValue );

wire [31:0] s_enableVector = counterMask & cpuEvents;
wire s_counterTick = s_enableVector == {32{1'b0}} ? 1'b0 : counterEnabled & ~counterPaused;
reg s_counterTickReg;

always @(posedge clock)
  if (resetCounter == 1'b1) s_counterTickReg <= 1'b0;
  else s_counterTickReg <= s_counterTick;

reg [31:0] s_counterLoReg;
wire [32:0] s_counterLoNext = {1'b0,s_counterLoReg} + 1;

always @(posedge clock)
  if (resetCounter == 1'b1) s_counterLoReg <= {32{1'b0}};
  else if (s_counterTickReg == 1'b1) s_counterLoReg <= s_counterLoNext[31:0];

reg s_counterHiTickReg;

always @(posedge clock)
  if (resetCounter == 1'b1) s_counterHiTickReg <= 1'b0;
  else s_counterHiTickReg <= s_counterLoNext[32] & s_counterTickReg;

reg [31:0] s_counterHiReg;

always @(posedge clock)
  if (resetCounter == 1'b1) s_counterHiReg <= {32{1'b0}};
  else if (s_counterHiTickReg) s_counterHiReg <= s_counterHiReg + 1;

assign counterValue = {s_counterHiReg , s_counterLoReg};

endmodule
