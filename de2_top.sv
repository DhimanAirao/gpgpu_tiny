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

    localparam DATA_MEM_ADDR_BITS = 16;        // Number of bits in data memory address (256 rows)
    localparam DATA_MEM_DATA_BITS = 16;        // Number of bits in data memory value (8 bit data)
    localparam PROGRAM_MEM_ADDR_BITS = 16;     // Number of bits in program memory address (256 rows)
    localparam PROGRAM_MEM_DATA_BITS = 32;    // Number of bits in program memory value (16 bit instruction)
    localparam PROG_DATA_SIZE = 13;            // Number of program data words to initialize
    localparam DATA_SIZE = 16;                 // Number of data words to initialize
    localparam NUM_CORES = 2;                  // Number of COMPUTE CORES to use in GPU
    localparam TOTAL_NUM_THREADS = 8;         // Total number of threads to use in GPU (4 threads per compute core at a time. If assigned more cores will rerun.)

    // Map board signals
    logic clk, start, reset;
    assign clk   = CLOCK_50;
    assign start = SW[0];        // user switch 0 starts kernel
    assign reset = ~KEY[0];      // KEY is active-low, invert to produce active-high reset

    // ==================== SDRAM Initialization Data ====================
    // Program memory initialization data (16-bit instructions)
    logic [PROGRAM_MEM_DATA_BITS-1:0] prog_init_data [0:PROG_DATA_SIZE-1];
    
    // Data memory initialization data (8-bit values)
    logic [DATA_MEM_DATA_BITS-1:0] data_init_data [0:DATA_SIZE-1];
    
    // Initialize with sample data
    initial begin
        // Program data: sample 16-bit instruction values
        prog_init_data = '{
            16'b1001000011011110, // MUL R0, %blockIdx, %blockDim
            16'b0111000000001111, // ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx
            16'b0101000100000000, // CONST R1, //0                   ; baseA (matrix A base address)
            16'b0101001000001000, // CONST R2, //8                   ; baseB (matrix B base address)
            16'b0101001100010000, // CONST R3, //16                  ; baseC (matrix C base address)
            16'b0111010000010000, // ADD R4, R1, R0                 ; addr(A[i]) = baseA + i
            16'b0011010001000000, // LDR R4, R4                     ; load A[i] from global memory
            16'b0111010100100000, // ADD R5, R2, R0                 ; addr(B[i]) = baseB + i
            16'b0011010101010000, // LDR R5, R5                     ; load B[i] from global memory
            16'b0111011001000101, // ADD R6, R4, R5                 ; C[i] = A[i] + B[i]
            16'b0111011100110000, // ADD R7, R3, R0                 ; addr(C[i]) = baseC + i
            16'b0100000001110110, // STR R7, R6                     ; store C[i] in global memory
            16'b0001000000000000  // RET                            ; end of kernel
        };

        // Data: sample 8-bit values
        data_init_data = '{
            8'h74, 8'h78, 8'h73, 8'h7b, 8'h82, 8'd00, 8'd00, 8'd00,
            8'h74, 8'h78, 8'h73, 8'h7b, 8'h82, 8'd00, 8'd00, 8'd00
        };
    end

    // Tie device control to safe defaults (not exposed on this wrapper)
    logic device_control_write_enable;
    logic [7:0] device_control_data;

    assign device_control_write_enable = 1'b1;
    assign device_control_data = TOTAL_NUM_THREADS;

    // Status signals
    logic done;
    logic init_complete;

    // Drive LED[0] with the done signal and LED[1] with initialization complete
    assign LED[0] = done;
    assign LED[1] = init_complete;
    assign LED[2] = reset;

    // Instantiate existing GPU
    gpu #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),     
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),   
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),        
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),        
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
