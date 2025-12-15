//////////////////////////////////////////////////////////////////////
////                                                              ////
////  adbg_wb_biu.v                                               ////
////                                                              ////
////                                                              ////
////  This file is part of the SoC Debug Interface.               ////
////                                                              ////
////  Author(s):                                                  ////
////       Nathan Yawn (nathan.yawn@opencores.org)                ////
////                                                              ////
////                                                              ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2008-2010        Authors                       ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
// CVS Revision History
//
// $Log: adbg_wb_biu.v,v $
// Revision 1.5  2010-03-21 01:05:10  Nathan
// Use all 32 address bits - WishBone slaves may use the 2 least-significant address bits instead of the four wb_sel lines, or in addition to them.
//
// Revision 1.4  2010-01-10 22:54:11  Nathan
// Update copyright dates
//
// Revision 1.3  2009/05/17 20:54:57  Nathan
// Changed email address to opencores.org
//
// Revision 1.2  2009/05/04 00:50:10  Nathan
// Changed the WB BIU to use big-endian byte ordering, to match the OR1000.  Kept little-endian ordering as a compile-time option in case this is ever used with a little-endian CPU.
//
// Revision 1.1  2008/07/22 20:28:32  Nathan
// Changed names of all files and modules (prefixed an a, for advanced).  Cleanup, indenting.  No functional changes.
//
// Revision 1.4  2008/07/08 19:04:04  Nathan
// Many small changes to eliminate compiler warnings, no functional changes.  
// System will now pass SRAM and CPU self-tests on Altera FPGA using 
// altera_virtual_jtag TAP.
//

`include "adbg_wb_defines.v"

// Top module
module adbg_wb_biu
  (
   // Debug interface signals
   tck_i,
   rst_i,
   data_i,
   data_o,
   addr_i,
   strobe_i,
   rd_wrn_i,           // If 0, then write op
   rdy_o,
   err_o,
   word_size_i,  // 1,2, or 4

   // System bus signals
  sb_clock_i,
  sb_request_o,
  sb_grant_i,
  sb_address_data_o,
  sb_byte_enables_o,
  sb_burst_size_o,
  sb_read_n_write_o,
  sb_begin_transaction_o,
  sb_end_transaction_o,
  sb_data_valid_o,
  sb_address_data_i,
  sb_end_transaction_i,
  sb_data_valid_i,
  sb_busy_i,
  sb_error_i

   // Wishbone signals
   /*
   wb_clk_i,
   wb_adr_o,
   wb_dat_o,
   wb_dat_i,
   wb_cyc_o,
   wb_stb_o,
   wb_sel_o,
   wb_we_o,
   wb_ack_i,
   wb_cab_o,
   wb_err_i,
   wb_cti_o,
   wb_bte_o
   */
   );

   // Debug interface signals
   input tck_i;
   input rst_i;
   input [31:0] data_i;  // Assume short words are in UPPER order bits!
   output [31:0] data_o;
   input [31:0]  addr_i;
   input 	 strobe_i;
   input 	 rd_wrn_i;
   output 	 rdy_o;
   output 	 err_o;
   input [2:0] 	 word_size_i;

  // System bus signals
  input 	       sb_clock_i;
  input          sb_grant_i;
  output         sb_request_o;
	output  [31:0] sb_address_data_o;
	output  [3:0]  sb_byte_enables_o;
	output  [7:0]  sb_burst_size_o;
	output         sb_read_n_write_o;
	output         sb_begin_transaction_o;
	output         sb_end_transaction_o;
	output         sb_data_valid_o;
	input  [31:0]  sb_address_data_i;
	input          sb_end_transaction_i;
	input          sb_data_valid_i;
	input          sb_busy_i;
	input          sb_error_i;

   // Wishbone signals
   /*
   input 	 wb_clk_i;
   output [31:0] wb_adr_o;
   output [31:0] wb_dat_o;
   input [31:0]  wb_dat_i;
   output 	 wb_cyc_o;
   output 	 wb_stb_o;
   output [3:0]  wb_sel_o;
   output 	 wb_we_o;
   input 	 wb_ack_i;
   output 	 wb_cab_o;
   input 	 wb_err_i;
   output [2:0]  wb_cti_o;
   output [1:0]  wb_bte_o;
   */

   wire [31:0] 	 data_o;
   reg 		 rdy_o;
   wire 	 err_o;

  reg [31:0] sb_address_data_o; 
  reg [3:0]  sb_byte_enables_o;
  reg        sb_begin_transaction_o;
  reg        sb_end_transaction_o;
  reg        sb_data_valid_o; 
  reg        sb_read_n_write_o;

  /*
   wire [31:0] 	 wb_adr_o;
   reg 		 wb_cyc_o;
   reg 		 wb_stb_o;
   wire [31:0] 	 wb_dat_o;
   wire [3:0] 	 wb_sel_o;
   wire 	 wb_we_o;
   wire 	 wb_cab_o;
   wire [2:0] 	 wb_cti_o;
   wire [1:0] 	 wb_bte_o;
   */

   // Registers
   reg [3:0] 	 sel_reg;
   reg [31:0] 	 addr_reg;  // Don't really need the two LSB, this info is in the SEL bits
   reg [31:0] 	 data_in_reg;  // dbg->WB
   reg [31:0] 	 data_out_reg;  // WB->dbg
   reg 		 wr_reg;
   reg 		 str_sync;  // This is 'active-toggle' rather than -high or -low.
   reg 		 rdy_sync;  // ditto, active-toggle
   reg 		 err_reg;

   // Sync registers.  TFF indicates TCK domain, WBFF indicates wb_clk domain
   reg 		 rdy_sync_tff1;
   reg 		 rdy_sync_tff2;
   reg 		 rdy_sync_tff2q;  // used to detect toggles
   reg 		 str_sync_wbff1;
   reg 		 str_sync_wbff2;
   reg 		 str_sync_wbff2q;  // used to detect toggles


   // Control Signals
   reg 		 data_o_en;    // latch wb_data_i
   reg 		 rdy_sync_en;  // toggle the rdy_sync signal, indicate ready to TCK domain
   reg 		 err_en;       // latch the wb_err_i signal

   // Internal signals
   reg [3:0] 	 be_dec;  // word_size and low-order address bits decoded to SEL bits
   wire 	     start_toggle;  // WB domain, indicates a toggle on the start strobe
   reg [31:0]  swapped_data_i;
   reg [31:0]  swapped_data_out;
   reg         reg_bus_req; // request sent to arbiter for bus access

   //////////////////////////////////////////////////////
   // TCK clock domain
   // There is no FSM here, just signal latching and clock
   // domain synchronization

   // Create byte enable signals from word_size and address (combinatorial)
 `ifdef DBG_WB_LITTLE_ENDIAN
   // This uses LITTLE ENDIAN byte ordering...lowest-addressed bytes is the
   // least-significant byte of the 32-bit WB bus.
   always @ (word_size_i or addr_i)
     begin
	case (word_size_i)
	  3'h1:
            begin
               if(addr_i[1:0] == 2'b00) be_dec <= 4'b0001;
               else if(addr_i[1:0] == 2'b01) be_dec <= 4'b0010;
               else if(addr_i[1:0] == 2'b10) be_dec <= 4'b0100;
               else be_dec <= 4'b1000;
            end
	  3'h2:
            begin
               if(addr_i[1]) be_dec <= 4'b1100;
               else          be_dec <= 4'b0011;
            end
	  3'h4: be_dec <= 4'b1111;
	  default: be_dec <= 4'b1111;  // default to 32-bit access
	endcase 
     end
 `else
   // This is for a BIG ENDIAN CPU...lowest-addressed byte is 
   // the 8 most significant bits of the 32-bit WB bus.
   always @ (word_size_i or addr_i)
     begin
	case (word_size_i)
	  3'h1:
            begin
               if(addr_i[1:0] == 2'b00) be_dec <= 4'b1000;
               else if(addr_i[1:0] == 2'b01) be_dec <= 4'b0100;
               else if(addr_i[1:0] == 2'b10) be_dec <= 4'b0010;
               else be_dec <= 4'b0001;
            end
	  3'h2:
            begin
               if(addr_i[1] == 1'b1) be_dec <= 4'b0011;
               else                  be_dec <= 4'b1100;
            end
	  3'h4: be_dec <= 4'b1111;
	  default: be_dec <= 4'b1111;  // default to 32-bit access
	endcase
     end
 `endif


   // Byte- or word-swap data as necessary.  Use the non-latched be_dec signal,
   // since it and the swapped data will be latched at the same time.
   // Remember that since the data is shifted in LSB-first, shorter words
   // will be in the high-order bits. (combinatorial)
   always @ (be_dec or data_i)
     begin
	case (be_dec)
	  4'b1111: swapped_data_i <= data_i;
	  4'b0011: swapped_data_i <= {16'h0,data_i[31:16]};
	  4'b1100: swapped_data_i <= data_i;
	  4'b0001: swapped_data_i <= {24'h0, data_i[31:24]};
	  4'b0010: swapped_data_i <= {16'h0, data_i[31:24], 8'h0};
	  4'b0100: swapped_data_i <= {8'h0, data_i[31:24], 16'h0};
	  4'b1000: swapped_data_i <= {data_i[31:24], 24'h0};
	  default: swapped_data_i <= data_i;  // Shouldn't be possible
	endcase
     end

   // Latch input data on 'start' strobe, if ready.
   always @ (posedge tck_i or posedge rst_i)
     begin
	if(rst_i) begin
	   sel_reg <= 4'h0;
	   addr_reg <= 32'h0;
	   data_in_reg <= 32'h0;
	   wr_reg <= 1'b0;
	end
	else
	  if(strobe_i && rdy_o) begin
	     sel_reg <= be_dec;
	     addr_reg <= addr_i;
	     if(!rd_wrn_i) data_in_reg <= swapped_data_i;
	     wr_reg <= ~rd_wrn_i;
	  end 
     end

   // Create toggle-active strobe signal for clock sync.  This will start a transaction
   // on the WB once the toggle propagates to the FSM in the WB domain.
   always @ (posedge tck_i or posedge rst_i)
     begin
	if(rst_i) str_sync <= 1'b0;
	else if(strobe_i && rdy_o) str_sync <= ~str_sync;
     end 

   // Create rdy_o output.  Set on reset, clear on strobe (if set), set on input toggle
   always @ (posedge tck_i or posedge rst_i)
    begin
	    if(rst_i) begin
        rdy_sync_tff1 <= 1'b0;
        rdy_sync_tff2 <= 1'b0;
        rdy_sync_tff2q <= 1'b0;
        rdy_o <= 1'b1; 
      end
      else begin  
        rdy_sync_tff1 <= rdy_sync;       // Synchronize the ready signal across clock domains
        rdy_sync_tff2 <= rdy_sync_tff1;
        rdy_sync_tff2q <= rdy_sync_tff2;  // used to detect toggles

        if(strobe_i && rdy_o) rdy_o <= 1'b0;
        else if(rdy_sync_tff2 != rdy_sync_tff2q) rdy_o <= 1'b1;
      end

    end 

   //////////////////////////////////////////////////////////
   // Direct assignments, unsynchronized

/*
   assign wb_dat_o = data_in_reg;
   assign wb_we_o = wr_reg;
   assign wb_adr_o = addr_reg;
   assign wb_sel_o = sel_reg;

   assign data_o = data_out_reg;
   assign err_o = err_reg;

   assign wb_cti_o = 3'h0;
   assign wb_bte_o = 2'h0;
   assign wb_cab_o = 1'b0;
*/

  assign data_o               = data_out_reg;
  assign sb_request_o         = reg_bus_req;
  assign sb_burst_size_o      = 0; // Always single word rw's so burst size is always zero

   ///////////////////////////////////////////////////////
   // Wishbone clock domain

    // synchronize the start strobe
    always @ (posedge sb_clock_i or posedge rst_i)
	  begin
	     if(rst_i) begin
		str_sync_wbff1 <= 1'b0;
		str_sync_wbff2 <= 1'b0;
		str_sync_wbff2q <= 1'b0;
	     end
	     else begin
		str_sync_wbff1 <= str_sync;
		str_sync_wbff2 <= str_sync_wbff1;
		str_sync_wbff2q <= str_sync_wbff2;  // used to detect toggles
	     end
	  end

   assign start_toggle = (str_sync_wbff2 != str_sync_wbff2q);

   // Error indicator register
   always @ (posedge sb_clock_i or posedge rst_i)
     begin
	if(rst_i) err_reg <= 1'b0;
	else if(err_en) err_reg <= sb_error_i; 
     end

   // Byte- or word-swap the WB->dbg data, as necessary (combinatorial)
   // We assume bits not required by SEL are don't care.  We reuse assignments
   // where possible to keep the MUX smaller.  (combinatorial)
   always @ (sel_reg or sb_address_data_i)
     begin
	case (sel_reg)
	  4'b1111: swapped_data_out <= sb_address_data_i;
	  4'b0011: swapped_data_out <= sb_address_data_i;
	  4'b1100: swapped_data_out <= {16'h0, sb_address_data_i[31:16]};
	  4'b0001: swapped_data_out <= sb_address_data_i;
	  4'b0010: swapped_data_out <= {24'h0, sb_address_data_i[15:8]};
	  4'b0100: swapped_data_out <= {16'h0, sb_address_data_i[31:16]};
	  4'b1000: swapped_data_out <= {24'h0, sb_address_data_i[31:24]};
	  default: swapped_data_out <= sb_address_data_i;  // Shouldn't be possible
	endcase
     end

   // WB->dbg data register
   always @ (posedge sb_clock_i or posedge rst_i)
     begin
	if(rst_i) data_out_reg <= 32'h0;
	else if(data_o_en) data_out_reg <= swapped_data_out;
     end

   // Create a toggle-active ready signal to send to the TCK domain
   always @ (posedge sb_clock_i or posedge rst_i)
     begin
	if(rst_i) rdy_sync <= 1'b0;
	else if(rdy_sync_en) rdy_sync <= ~rdy_sync;
     end 

   /////////////////////////////////////////////////////
   // Small state machine to create WB accesses
   // Not much more that an 'in_progress' bit, but easier
   // to read.  Deals with single-cycle and multi-cycle
   // accesses.

   reg [1:0] wb_fsm_state;
   reg [1:0] next_fsm_state;

  `define STATE_IDLE     2'd0 // Ready
  `define STATE_REQUEST  2'd1 // Waiting for bus access
  `define STATE_TRANSFER 2'd2 // Performing transfer

  // Sequential bit
   always @ (posedge sb_clock_i or posedge rst_i)
     begin
    if(rst_i) wb_fsm_state <= `STATE_IDLE;
    else wb_fsm_state <= next_fsm_state; 
  end

  // Determination of next state (combinatorial)
  always @ (*)
  begin
    case (wb_fsm_state)

      // In idle state, go to request state on start toggle
      `STATE_IDLE:
      begin
        //if(start_toggle && !(wb_ack_i || sb_error_i)) next_fsm_state <= `STATE_TRANSFER;  // Don't go to next state for 1-cycle transfer
        //else next_fsm_state <= `STATE_IDLE;
        if(start_toggle) next_fsm_state <= `STATE_REQUEST;
        else next_fsm_state <= `STATE_IDLE;
      end

      // In request state, go to transfer state when granted access
      // by bus arbiter
      `STATE_REQUEST:
      begin
        if(sb_grant_i) next_fsm_state <= `STATE_TRANSFER;
        else next_fsm_state <= `STATE_REQUEST;
      end

      // In transfer state, go to idle state on ack or error
      // `STATE_TRANSFER
      default: 
      begin
        if ((sb_data_valid_i && !sb_busy_i) || sb_error_i) next_fsm_state <= `STATE_IDLE;
        else next_fsm_state <= `STATE_TRANSFER;
      end
    endcase
  end

  // Outputs of state machine (combinatorial)
  always @ (*)
  begin
    case (wb_fsm_state)

    // Wait for WB module to start talking to us
    `STATE_IDLE:
      begin
        rdy_sync_en <= 1'b0;
        err_en <= 1'b0;
        data_o_en <= 1'b0;

        reg_bus_req <= 1'b0;

        sb_address_data_o      <= 32'h0;
        sb_begin_transaction_o <= 1'b0;
        sb_end_transaction_o   <= 1'b0;
        sb_byte_enables_o      <= 4'b0000;
        sb_read_n_write_o      <= 1'b0;
        sb_data_valid_o        <= 1'b0;
      end

    // Wait for grant. On grant, begin transaction and write important signals
    `STATE_REQUEST:
      begin
        rdy_sync_en <= 1'b0;
        err_en <= 1'b0;
        data_o_en <= 1'b0;

        reg_bus_req <= 1'b1; // Request bus access

        sb_address_data_o      <= sb_grant_i ? addr_reg : 32'h0;
        sb_begin_transaction_o <= sb_grant_i ? 1'b1 : 1'b0;
        sb_end_transaction_o   <= 1'b0;
        sb_byte_enables_o      <= sb_grant_i ? 4'b1111 : 4'b0000; // always 4 bytes
        sb_read_n_write_o      <= sb_grant_i ? ~wr_reg : 1'b0; // read_not_write == ~wr_reg
        sb_data_valid_o        <= 1'b0;
      end

    // In case of read, keep trying to write until busy is unasserted.
    // In case of write, wait patiently for ack (payload sent on state transition REQUEST->TRANSFER)
    // `STATE_TRANSFER
    default:
      begin
        rdy_sync_en <= (sb_error_i || (sb_data_valid_i && !sb_busy_i)) ? 1'b1 : 1'b0;
        err_en      <= sb_error_i ? 1'b1 : 1'b0;
        data_o_en   <= ~wr_reg && sb_data_valid_i ? 1'b1 : 1'b0;

        reg_bus_req <= 1'b0;

        sb_address_data_o      <= wr_reg ? data_in_reg : 32'h0;
        sb_begin_transaction_o <= 1'b0;
        sb_end_transaction_o   <= sb_error_i || (wr_reg && !sb_busy_i) ? 1'b1 : 1'b0; // end transaction if error. TODO writes
        sb_byte_enables_o      <= 4'b0000;
        sb_read_n_write_o      <= 1'b0;
        sb_data_valid_o        <= wr_reg ? 1'b1 : 1'b0; // assert data_valid for writes
      end
    endcase
  end

endmodule

