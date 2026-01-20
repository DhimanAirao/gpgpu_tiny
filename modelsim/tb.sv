`timescale 1ns/1ns

module gpgpu_tb;

    // Testbench signals
    logic CLOCK_50;
    logic [1:0] KEY;
    logic [4:0] SW;

    wire [2:0] LED;
    wire [2:0] ledr;

    // Instantiate the DUT (Device Under Test)
    gpgpu dut (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .SW(SW),
        .LED(LED),
        .ledr(ledr)
    );

    // Clock generation: 50 MHz (period = 20 ns)
    initial begin
        CLOCK_50 = 0;
        forever #10 CLOCK_50 = ~CLOCK_50;
    end

    // Test sequence
    initial begin
        $display("Starting GPGPU Testbench...");

        // Initialize inputs
        KEY = 2'b11;   // not pressed (active-low)
        SW  = 5'b00000;

        // Apply reset
        $display("Applying Reset...");
        #50;
        KEY[0] = 1'b0;   // press reset button (active low)
        #100;
        KEY[0] = 1'b1;   // release reset
        $display("Reset Released");
        #10;

        // Trigger start signal using SW[0]
        $display("Triggering START...");
        SW[0] = 1'b1;

        // Wait for initialization complete
        wait (LED[1] == 1'b1);
        $display("Initialization Complete detected at time %t", $time);

        // Wait for done signal
        wait (LED[0] == 1'b1);
        $display("Execution DONE detected at time %t", $time);

        // Finish simulation
        #200;
        $display("Simulation Finished.");
        $stop;
    end

    // Monitor important signals
    initial begin
        $monitor("Time=%0t | reset=%b | start=%b | init_complete=%b | done=%b | ledr=%b",
                 $time, ~KEY[0], SW[0], LED[1], LED[0], ledr);
    end

endmodule
