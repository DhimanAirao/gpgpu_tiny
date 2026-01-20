`timescale 1ns/1ns

// DE2-115 top-level wrapper
// - `start` is driven by SW[0]
// - `reset` is driven by KEY[0] (inverted because DE2 keys are active-low)
module gpgpu(
    input  logic CLOCK_50,
    input  logic [1:0] KEY,    // push buttons (active low)
    input  logic [4:0] SW,     // switches
	output logic [2:0] LED,
    output logic [2:0] ledr
);

    // Map board signals
    logic clk, start, reset;
    assign clk   = CLOCK_50;
    assign start = SW[0];        // user switch 0 starts kernel
    assign reset = ~KEY[0];      // KEY is active-low, invert to produce active-high reset

    // ==================== SDRAM Initialization Data ====================
    // Program memory initialization data (16-bit instructions)
    logic [15:0] prog_init_data [0:12];
    
    // Data memory initialization data (8-bit values)
    logic [7:0] data_init_data [0:15];
    
    // Initialize with sample data
    initial begin
        // Program data: sample 16-bit instruction values
        prog_init_data[0]  = 16'h50DE;
        prog_init_data[1]  = 16'h300F;
        prog_init_data[2]  = 16'h9100;
        prog_init_data[3]  = 16'h9208;
        prog_init_data[4]  = 16'h9310;
        prog_init_data[5]  = 16'h3410;
        prog_init_data[6]  = 16'h7440;
        prog_init_data[7]  = 16'h3520;
        prog_init_data[8]  = 16'h7550;
        prog_init_data[9]  = 16'h3645;
        prog_init_data[10]  = 16'h3730;
        prog_init_data[11]  = 16'h8076;
        prog_init_data[12]  = 16'hF000;
        
        // Data: sample 8-bit values
        data_init_data[0]  = 8'h0;
        data_init_data[1]  = 8'h1;
        data_init_data[2]  = 8'h2;
        data_init_data[3]  = 8'h3;
        data_init_data[4]  = 8'h4;
        data_init_data[5]  = 8'h5;
        data_init_data[6]  = 8'h6;
        data_init_data[7]  = 8'h7;
        data_init_data[8]  = 8'h0;
        data_init_data[9]  = 8'h1;
        data_init_data[10] = 8'h2;
        data_init_data[11] = 8'h3;
        data_init_data[12] = 8'h4;
        data_init_data[13] = 8'h5;
        data_init_data[14] = 8'h6;
        data_init_data[15] = 8'h7;
    end

    // Tie device control to safe defaults (not exposed on this wrapper)
    logic device_control_write_enable;
    logic [7:0] device_control_data;

    assign device_control_write_enable = 1'b1;
    assign device_control_data = 8'd8;

    // Status signals
    logic done;
    logic init_complete;

    // Drive LED[0] with the done signal and LED[1] with initialization complete
    assign LED[0] = done;
    assign LED[1] = init_complete;
    assign LED[2] = reset;

    // Instantiate existing GPU
    gpu gpu_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .init_complete(init_complete),

        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        
        .prog_init_data(prog_init_data),
        .data_init_data(data_init_data)
    );

endmodule
