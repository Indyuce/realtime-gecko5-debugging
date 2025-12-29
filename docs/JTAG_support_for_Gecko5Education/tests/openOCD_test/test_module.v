module test_module(
    output wire [3:0] RGB_Column,
    output reg [2:0] row1,
    output reg [2:0] row2,
    output reg [2:0] row3);

    wire jtdi, jtck, jshift, jupdate, jce1, jce2, jrstn, jrti1, jrti2;
	JTAGG jtag(
		.JTDI(jtdi),
		.JTCK(jtck),
		.JRTI2(jrti1), 
		.JTDO2(s_JTDO2),
        .JTDO1(s_JTDO1),
		.JRTI1(jrti2),
		.JSHIFT(jshift), 
		.JUPDATE(jupdate), 
		.JRSTN(jrstn),
		.JCE2(jce2),  
		.JCE1(jce1)
	);

	assign row1 = (jce1 && jshift) ? {jtdi, jtdi, jtdi} : 3'b000;
	reg [3:0] r_RGB_Column;
	always @(posedge jtck or negedge jrstn) begin
		if (!jrstn) begin
			RGB_Column <= 4'b0000;
		end else begin
			if (jshift) begin 
				r_RGB_Column <= {r_RGB_Column[2:0], jtdi};
			end
			if (jupdate) begin
				RGB_Column <= r_RGB_Column;
			end
		end
	end
endmodule