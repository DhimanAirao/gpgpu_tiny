`default_nettype none
`timescale 1ns/1ns

// DE2-115 top-level wrapper
// - `start` is driven by SW[0]
// - `reset` is driven by KEY[0] (inverted because DE2 keys are active-low)
module gpgpu(
    input  wire CLOCK_50,
    input  wire [1:0] KEY,    // push buttons (active low)
    input  wire [4:0] SW,     // switches
	 output wire [1:0] LED,

    // SDRAM physical pins (pass-through to gpgpu)
    output wire [1:0]  sdram_ba_pad_o,
    output wire [12:0] sdram_a_pad_o,
    output wire        sdram_cs_n_pad_o,
    output wire        sdram_ras_pad_o,
    output wire        sdram_cas_pad_o,
    output wire        sdram_we_pad_o,
    inout  wire [15:0] sdram_dq_pad_io,
    output wire [1:0]  sdram_dqm_pad_o,
    output wire        sdram_cke_pad_o,
    output wire        sdram_clk_pad_o
);

    // Map board signals
    wire clk   = CLOCK_50;
    wire start = SW[0];        // user switch 0 starts kernel
    wire reset = ~KEY[0];      // KEY is active-low, invert to produce active-high reset

    // Tie device control to safe defaults (not exposed on this wrapper)
    wire device_control_write_enable = 1'b0;
    wire [7:0] device_control_data = 8'b0;

    // Status signals
    wire done;

    // Drive LED[0] with the done signal
    assign LED[0] = done;

    // Instantiate existing GPU
    gpu gpu_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),

        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),

        .data_mem_read_valid(),
        .data_mem_read_address(),
        .data_mem_write_valid(),
        .data_mem_write_address(),
        .data_mem_write_data(),

        .sdram_ba_pad_o(sdram_ba_pad_o),
        .sdram_a_pad_o(sdram_a_pad_o),
        .sdram_cs_n_pad_o(sdram_cs_n_pad_o),
        .sdram_ras_pad_o(sdram_ras_pad_o),
        .sdram_cas_pad_o(sdram_cas_pad_o),
        .sdram_we_pad_o(sdram_we_pad_o),
        .sdram_dq_pad_io(sdram_dq_pad_io),
        .sdram_dqm_pad_o(sdram_dqm_pad_o),
        .sdram_cke_pad_o(sdram_cke_pad_o),
        .sdram_clk_pad_o(sdram_clk_pad_o)
    );

endmodule
