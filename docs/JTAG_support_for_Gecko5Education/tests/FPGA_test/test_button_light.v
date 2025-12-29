module button_led (
    input wire [2:0] buttons,
    input wire [3:0] switches,
    input wire [1:0] RGB_row,
    output reg [2:0] row1,
    output reg [2:0] row2,
    output reg [2:0] row3,
    output wire [3:0] RGB_Column
);
    always @(*) begin
        row1 = 3'b111;
        row2 = 3'b111;
        row3 = 3'b111;
        case (RGB_row)
            3'b00: row1 = buttons;
            3'b01: row2 = buttons;
            3'b10: row3 = buttons;
            3'b11: begin
                row1 = buttons;
                row2 = buttons;
                row3 = buttons;
            end
            default: begin
                row1 = 3'b111;
                row2 = 3'b111;
                row3 = 3'b111;
            end
        endcase
    end
    assign RGB_Column = switches;
endmodule