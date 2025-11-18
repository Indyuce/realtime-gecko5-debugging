module chain2(
    input wire JTCK,
    input wire JTDI,
    input wire JRTI2,
    input wire JSHIFT,
    input wire JUPDATE,
    input wire JRSTN,
    input wire JCE2,
    output wire JTD2,
    output reg [3:0] rgbRow
);


reg [3:0] shift_reg_2;
reg [3:0] data_reg_2;
assign JTD2 = shift_reg_2[0];

always @(posedge JTCK or negedge JRSTN) begin
    if (JRSTN == 0) begin
        shift_reg_2 <= 4'b0;
        data_reg_2 <= 4'b0;
    end
    else  begin
        if (JCE2) begin
        // Shifting data in
            if (JSHIFT) begin
                shift_reg_2 <= {JTDI, shift_reg_2[3:1]};
            end
            // Capture mode
            else begin
                shift_reg_2 <= data_reg_2;
            end 
        end
        // Update data register
        if (JUPDATE) begin
            data_reg_2 <= shift_reg_2;

        end
    end
end

always @(data_reg_2) begin
    rgbRow = data_reg_2;
end

endmodule
