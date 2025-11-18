`timescale 1ps / 1ps
module tb_ipcore;

    // Testbench signals
    reg JTCK;
    reg JTDI;
    reg JRTI1;
    reg JRTI2;
    reg JSHIFT;
    reg JUPDATE;
    reg JRSTN;
    reg JCE1;
    reg JCE2;
    wire JTD1;
    wire JTD2;
    wire [8:0] LEDS;
    wire [3:0] LEDS_colums;

    // Instantiate the ipcore module
    ipcore uut(
        .JTCK(JTCK),
        .JTDI(JTDI),
        .JRTI1(JRTI1),
        .JRTI2(JRTI2),
        .JSHIFT(JSHIFT),
        .JUPDATE(JUPDATE),
        .JRSTN(JRSTN),
        .JCE1(JCE1),
        .JCE2(JCE2),
        .JTD1(JTD1),
        .JTD2(JTD2),
        .LEDS(LEDS),
        .LEDS_colums(LEDS_colums)
    );

    initial begin
        JTCK = 0;
        JTDI = 0;
        JRTI1 = 0;  
        JRTI2 = 0;
        JSHIFT = 0;
        JUPDATE = 0;
        JRSTN = 1;  
        JCE1 = 0;
        JCE2 = 0;
    end

    always begin
        #5 JTCK = ~JTCK;  
    end

    initial begin
        // Reset the shift register
        #10 JRSTN = 0;   // Activate reset
        #10 JRSTN = 1;   // Deactivate reset
        #10;            

        //Run Idle
        JRTI1 = 1;       
        #20;

        // Capture the data
        JRTI1 = 0;
        JCE1 = 1;
        #10; 

        // Shift dataIn 
        JSHIFT = 1;      

        JTDI = 1;        
        #10;             
        
        JTDI = 0;        
        #10;             

        JTDI = 1;        
        #10;             

        // Stop shifting
        JSHIFT = 0;      
        JCE1 = 0;
        #10;             

        // Update
        JUPDATE = 1;     
        #10;             

        $display("LEDS = %b", LEDS);
        $display("LEDS_colums = %b", LEDS_colums);


        //Run Idle
        JUPDATE = 0;
        JRTI2 = 1;
        JRTI1 = 1;
        #20;

        // Capture the data
        JRTI2 = 0;
        JCE2 = 1;
        #10;

        // Shift dataIn
        JSHIFT = 1;
        JTDI = 1;
        #10;

        JTDI = 1;
        #10;

        JTDI = 1;
        #10;

        // Stop shifting
        JSHIFT = 0;
        JCE2 = 0;
        #10;

        // Update
        JUPDATE = 1;
        #10;

        $display("LEDS = %b", LEDS);
        $display("LEDS_colums = %b", LEDS_colums);

        $finish;
    end

    initial begin
        $dumpfile("test_ipcore.vcd");
        $dumpvars(0, tb_ipcore);
    end

endmodule