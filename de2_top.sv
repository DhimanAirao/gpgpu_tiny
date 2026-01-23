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

    localparam PROG_DATA_SIZE = 28;            // Number of program data words to initialize
    localparam DATA_SIZE = 8;                 // Number of data words to initialize
    localparam NUM_CORES = 2;   

    // Map board signals
    logic clk, start, reset;
    assign clk   = CLOCK_50;
    assign start = SW[0];        // user switch 0 starts kernel
    assign reset = ~KEY[0];      // KEY is active-low, invert to produce active-high reset

    // ==================== SDRAM Initialization Data ====================
    // Program memory initialization data (16-bit instructions)
    logic [15:0] prog_init_data [0:PROG_DATA_SIZE-1];
    
    // Data memory initialization data (8-bit values)
    logic [7:0] data_init_data [DATA_SIZE-1:0];
    
    // Initialize with sample data
    initial begin
        // Program data: sample 16-bit instruction values
        prog_init_data = '{
            16'b0101000011011110, // MUL   R0, %blockIdx, %blockDim
            16'b0011000000001111, // ADD   R0, R0, %threadIdx        ; i = blockIdx * blockDim + threadIdx

            16'b1001000100000001, // CONST R1, #1                    ; increment
            16'b1001001000000010, // CONST R2, #2                    ; N (matrix inner dimension)
            16'b1001001100000000, // CONST R3, #0                    ; baseA
            16'b1001010000000100, // CONST R4, #4                    ; baseB
            16'b1001010100001000, // CONST R5, #8                    ; baseC

            16'b0110011000000010, // DIV   R6, R0, R2                ; row = i / N
            16'b0101011101100010, // MUL   R7, R6, R2
            16'b0100011100000111, // SUB   R7, R0, R7                ; col = i % N

            16'b1001100000000000, // CONST R8, #0                    ; acc = 0
            16'b1001100100000000, // CONST R9, #0                    ; k = 0

                                // LOOP:
            16'b0101101001100010, //   MUL R10, R6, R2
            16'b0011101010101001, //   ADD R10, R10, R9
            16'b0011101010100011, //   ADD R10, R10, R3              ; addr A
            16'b0111101010100000, //   LDR R10, R10

            16'b0101101110010010, //   MUL R11, R9, R2
            16'b0011101110110111, //   ADD R11, R11, R7
            16'b0011101110110100, //   ADD R11, R11, R4              ; addr B
            16'b0111101110110000, //   LDR R11, R11

            16'b0101110010101011, //   MUL R12, R10, R11
            16'b0011100010001100, //   ADD R8, R8, R12               ; acc += A * B

            16'b0011100110010001, //   ADD R9, R9, R1                ; k++
            16'b0010000010010010, //   CMP R9, R2
            16'b0001100000001100, //   BRn LOOP                      ; while k < N

            16'b0011100101010000, // ADD R9, R5, R0                  ; addr C
            16'b1000000010011000, // STR R9, R8                      ; store C[i]

            16'b1111000000000000  // RET

        };

        
        // Data: sample 8-bit values
        data_init_data[0]  = 8'd1;
        data_init_data[1]  = 8'd2;
        data_init_data[2]  = 8'd3;
        data_init_data[3]  = 8'd4;
        data_init_data[4]  = 8'd1;
        data_init_data[5]  = 8'd2;
        data_init_data[6]  = 8'd3;
        data_init_data[7]  = 8'd4;
    end

    // Tie device control to safe defaults (not exposed on this wrapper)
    logic device_control_write_enable;
    logic [7:0] device_control_data;

    assign device_control_write_enable = 1'b1;
    assign device_control_data = 8'd4;

    // Status signals
    logic done;
    logic init_complete;

    // Drive LED[0] with the done signal and LED[1] with initialization complete
    assign LED[0] = done;
    assign LED[1] = init_complete;
    assign LED[2] = reset;

    // Instantiate existing GPU
    gpu #(
        .PROG_DATA_SIZE(PROG_DATA_SIZE),
        .DATA_SIZE(DATA_SIZE),
        .NUM_CORES(NUM_CORES)
    ) gpu_inst (
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
