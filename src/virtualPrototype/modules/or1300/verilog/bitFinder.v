/*
 * control  flag function
 *  x0       0   result <= operantB
 *  x0       1   result <= operantA
 *  01       x   result <= ff1(operantA)
 *  11       x   result <= fl1(operantA)
 *
 * NOTE: control(0) = ir(0); control(1) = ir(8)
 *
 */
module bitFinder ( input wire [1:0]  control,
                   input wire        flag,
                   input wire [31:0] operantA,
                                     operantB,
                   output reg [31:0] result );

  wire [1:0] s_selector;
  wire [31:0] s_resultFb;
  assign s_selector[1] = control[0];
  assign s_selector[0] = (flag & ~control[0]) | (control[0] & control[1]);
  
  always @*
    case (s_selector)
      2'b00   : result <= operantB;
      2'b01   : result <= operantA;
      default : result <= s_resultFb;
    endcase
  
  wire [3:0] s_orLsb,s_orMsb;
  assign s_orLsb[0] = operantA[0] | operantA[1] | operantA[2];
  assign s_orLsb[1] = operantA[3] | operantA[4] | operantA[5] | operantA[6];
  assign s_orLsb[2] = operantA[7] | operantA[8] | operantA[9] | operantA[10];
  assign s_orLsb[3] = operantA[11] | operantA[12] | operantA[13] | operantA[14];
  assign s_orMsb[0] = operantA[16] | operantA[17] | operantA[18];
  assign s_orMsb[1] = operantA[19] | operantA[20] | operantA[21] | operantA[22];
  assign s_orMsb[2] = operantA[23] | operantA[24] | operantA[25] | operantA[26];
  assign s_orMsb[3] = operantA[27] | operantA[28] | operantA[29] | operantA[30];
  wire s_orLo = s_orLsb[0] | s_orLsb[1] | s_orLsb[2] | s_orLsb[3];
  wire s_orHi = s_orMsb[0] | s_orMsb[1] | s_orMsb[2] | s_orMsb[3];
  
  function [1:0] selection (input [2:0] bits,
                            input       control);
    begin
      selection[0] = (~control & (bits[0] | (bits[2] & ~bits[1]))) |
                     ( control & (bits[2] | (bits[0] & ~bits[1])));
      selection[1] = (~control & (~bits[0] &(bits[2] | bits[1]))) |
                     ( control & (bits[2] | bits[1]));
    end
  endfunction
  
  wire [1:0] s_goupLsb [3:0];
  wire [1:0] s_goupMsb [3:0];
  assign s_goupLsb[0] = selection(operantA[2:0],control[1]);
  assign s_goupLsb[1] = selection(operantA[6:4],control[1]);
  assign s_goupLsb[2] = selection(operantA[10:8],control[1]);
  assign s_goupLsb[3] = selection(operantA[14:12],control[1]);
  assign s_goupMsb[0] = selection(operantA[18:16],control[1]);
  assign s_goupMsb[1] = selection(operantA[22:20],control[1]);
  assign s_goupMsb[2] = selection(operantA[26:24],control[1]);
  assign s_goupMsb[3] = selection(operantA[30:28],control[1]);
  
  wire [1:0] s_selectLsb, s_selectMsb;
  assign s_selectLsb[0] = (~control[1] & (~s_orLsb[0] & (s_orLsb[1] | (s_orLsb[3] & ~s_orLsb[2])))) |
                          ( control[1] & (s_orLsb[3] | (~s_orLsb[2] & s_orLsb[1])));
  assign s_selectLsb[1] = (~control[1] & (~s_orLsb[0] & ~s_orLsb[1] & (s_orLsb[2] | s_orLsb[3]))) |
                          ( control[1] & (s_orLsb[2] | s_orLsb[3]));
  assign s_selectMsb[0] = (~control[1] & (~s_orMsb[0] & (s_orMsb[1] | (s_orMsb[3] & ~s_orMsb[2])))) |
                          ( control[1] & (s_orMsb[3] | (~s_orMsb[2] & s_orMsb[1])));
  assign s_selectMsb[1] = (~control[1] & (~s_orMsb[0] & ~s_orMsb[1] & (s_orMsb[2] | s_orMsb[3]))) |
                          ( control[1] & (s_orMsb[2] | s_orMsb[3]));
  
  reg [3:0] s_resultLsb, s_resultMsb;
  
  always @*
    begin
      s_resultLsb[3:2] <= s_selectLsb;
      case (s_selectLsb)
        2'b00   : s_resultLsb[1:0] <= s_goupLsb[0];
        2'b01   : s_resultLsb[1:0] <= s_goupLsb[1];
        2'b10   : s_resultLsb[1:0] <= s_goupLsb[2];
        default : s_resultLsb[1:0] <= s_goupLsb[3];
      endcase
    end

  always @*
    begin
      s_resultMsb[3:2] <= s_selectMsb;
      case (s_selectMsb)
        2'b00   : s_resultMsb[1:0] <= s_goupMsb[0];
        2'b01   : s_resultMsb[1:0] <= s_goupMsb[1];
        2'b10   : s_resultMsb[1:0] <= s_goupMsb[2];
        default : s_resultMsb[1:0] <= s_goupMsb[3];
      endcase
    end
  
  assign s_resultFb[31:6] = 0;
  assign s_resultFb[5]    = (~control[1] & (operantA[31] & ~s_orLo & ~s_orHi & ~operantA[15])) |
                            ( control[1] & operantA[31]);
  assign s_resultFb[4]    = (~control[1] & (~s_orLo & (s_orHi | operantA[15]))) |
                            ( control[1] &(~operantA[31] & (s_orHi | operantA[15])));
  assign s_resultFb[3:0]  = (control[1] == 1'b1 && operantA[31] == 1'b1) ? 4'd0 :
                            (control[1] == 1'b0 && (s_orLo == 1'b1 || operantA[15] == 1'b1)) ||
                            (control[1] == 1'b1 && s_orHi == 1'b0 && operantA[15] == 1'b0) ? s_resultLsb : s_resultMsb;
endmodule
