module pingpongbuffer (
        input wire clockA,
        input wire clockB, 
        input wire [8:0] addressA,
        input wire [8:0] addressB,
        input wire writeEnableA, writeEnableB,
        input wire [31:0] dataInA, dataInB,
        output wire [31:0] dataOutA, dataOutB,
        input wire switch,
        input wire reset
        );

    // Internal signals
    wire [8:0] s_addressA, s_addressB;
    reg switch_reg;

    fullyDualPortSSRAM ssram (
        .clockA(clockA),
        .clockB(clockB),
        .addressA(s_addressA),
        .addressB(s_addressB),
        .writeEnableA(writeEnableA),
        .writeEnableB(writeEnableB),
        .dataInA(dataInA),
        .dataInB(dataInB),
        .dataOutA(dataOutA),
        .dataOutB(dataOutB)
    );

    always @(posedge clockA or negedge reset) begin
        if (~reset) begin
            switch_reg <= 1'b0; // Initialize to 0 during reset
        end else if (switch) begin
            switch_reg <= ~switch_reg; // Toggle on switch
        end
    end


    assign s_addressA = {switch_reg, addressA[7:0]};
    assign s_addressB = {~switch_reg, addressB[7:0]};

endmodule



