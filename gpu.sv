`timescale 1ns/1ns

// GPU
// > Built to use an external async memory with multi-channel read/write
// > Assumes that the program is loaded into program memory, data into data memory, and threads into
//   the device control logicister before the start signal is triggered
// > Has memory controllers to interface between external memory and its multiple cores
// > Configurable number of cores and thread capacity per core
module gpu #(
    parameter DATA_MEM_ADDR_BITS = 16,        // Number of bits in data memory address (256 rows)
    parameter DATA_MEM_DATA_BITS = 16,        // Number of bits in data memory value (8 bit data)
    parameter DATA_MEM_NUM_CHANNELS = 4,     // Number of concurrent channels for sending requests to data memory
    parameter PROGRAM_MEM_ADDR_BITS = 16,     // Number of bits in program memory address (256 rows)
    parameter PROGRAM_MEM_DATA_BITS = 32,    // Number of bits in program memory value (16 bit instruction)
    parameter PROGRAM_MEM_NUM_CHANNELS = 1,  // Number of concurrent channels for sending requests to program memory
    parameter NUM_CORES = 2,                 // Number of cores to include in this GPU
    parameter THREADS_PER_BLOCK = 4,         // Number of threads to handle per block (determines the compute resources of each core)
    parameter PROG_DATA_SIZE = 19,            // Number of program data words to initialize
    parameter DATA_SIZE = 3                 // Number of data words to initialize
) (
    input logic clk,
    input logic reset,

    // Kernel Execution
    input logic start,
    output logic done,
    output logic init_complete,

    // Device Control logicister
    input logic device_control_write_enable,
    input logic [7:0] device_control_data,
    
    // Initialization Data (from external source)
    input logic [PROGRAM_MEM_DATA_BITS-1:0] prog_init_data [0:PROG_DATA_SIZE-1],
    input logic [DATA_MEM_DATA_BITS-1:0] data_init_data [0:DATA_SIZE-1]
);
    // Initialization state machine
    localparam INIT_IDLE = 3'b000;
    localparam INIT_PROG = 3'b001;
    localparam INIT_DATA = 3'b010;
    localparam INIT_DONE = 3'b011;
    
    logic [2:0] init_state = INIT_IDLE;
    logic [7:0] init_index = 0;
    assign init_complete = (init_state == INIT_DONE);
    
    // Gate the start signal - only allow GPU to start after initialization
    logic gated_start;
    assign gated_start = start && init_complete;

    // Control
    logic [7:0] thread_count;

    // Program memory internal channels
    logic [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    logic [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    logic [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    logic [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];

    // Data memory internal channels
    logic [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    logic [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
    logic [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    logic [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
    logic [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    logic [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
    logic [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
    logic [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;

    // Compute Core State
    logic [NUM_CORES-1:0] core_start;
    logic [NUM_CORES-1:0] core_reset;
    logic [NUM_CORES-1:0] core_done;
    logic [7:0] core_block_id [NUM_CORES-1:0];
    logic [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];

    // LSU <> Data Memory Controller Channels
    localparam NUM_LSUS = NUM_CORES * THREADS_PER_BLOCK;
    logic [NUM_LSUS-1:0] lsu_read_valid;
    logic [DATA_MEM_ADDR_BITS-1:0] lsu_read_address [NUM_LSUS-1:0];
    logic [NUM_LSUS-1:0] lsu_read_ready;
    logic [DATA_MEM_DATA_BITS-1:0] lsu_read_data [NUM_LSUS-1:0];
    logic [NUM_LSUS-1:0] lsu_write_valid;
    logic [DATA_MEM_ADDR_BITS-1:0] lsu_write_address [NUM_LSUS-1:0];
    logic [DATA_MEM_DATA_BITS-1:0] lsu_write_data [NUM_LSUS-1:0];
    logic [NUM_LSUS-1:0] lsu_write_ready;

    // Fetcher <> Program Memory Controller Channels
    localparam NUM_FETCHERS = NUM_CORES;
    logic [NUM_FETCHERS-1:0] fetcher_read_valid;
    logic [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_read_address [NUM_FETCHERS-1:0];
    logic [NUM_FETCHERS-1:0] fetcher_read_ready;
    logic [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data [NUM_FETCHERS-1:0];


///////////////////////////////////////////////////////////////////////////////////////////////
    // Program Memory (1-port RAM) - Read/Write capable
    logic [PROGRAM_MEM_DATA_BITS-1:0] prog_mem_q;
    
    // Multiplex between initialization writes and normal read/write operations
    logic [PROGRAM_MEM_ADDR_BITS-1:0] prog_mem_addr_mux;
    logic [PROGRAM_MEM_DATA_BITS-1:0] prog_mem_data_mux;
    logic prog_mem_wren_mux;
    logic prog_mem_rden_mux;
    
    // During INIT_PROG phase, write init data; otherwise pass through controller signals
    assign prog_mem_addr_mux = (init_state == INIT_PROG) ? init_index : program_mem_read_address[0];
    assign prog_mem_data_mux = (init_state == INIT_PROG) ? prog_init_data[init_index] : 16'b0;
    assign prog_mem_wren_mux = (init_state == INIT_PROG) ? 1'b1 : 1'b0;  // Currently no writes from controller
    assign prog_mem_rden_mux = (init_state == INIT_DONE) ? program_mem_read_valid[0] : 1'b0;
    
    prog_mem_16A_32D prog_mem_16A_32D_inst (
        .address(prog_mem_addr_mux),
        .clock(clk),
        .data(prog_mem_data_mux),
        .rden(prog_mem_rden_mux),
        .wren(prog_mem_wren_mux),
        .q(prog_mem_q)
    );
    
    // Pipeline delay for program memory read ready signal
    logic program_mem_read_valid_delayed;
    
    always @(posedge clk) begin
        if (reset) begin
            program_mem_read_valid_delayed <= 1'b0;
        end else begin
            program_mem_read_valid_delayed <= program_mem_read_valid[0];
        end
    end
    
    // Program memory output connections
    assign program_mem_read_data[0] = prog_mem_q;
    assign program_mem_read_ready[0] = program_mem_read_valid_delayed;  // One cycle delayed response
    
    // Data Memory (4 separate 1-port RAMs) - one for each data channel
    logic [DATA_MEM_DATA_BITS-1:0] data_mem_q [DATA_MEM_NUM_CHANNELS-1:0];
    
    // Multiplex between initialization and normal operations for each channel
    logic [DATA_MEM_ADDR_BITS-1:0] data_mem_addr_mux [DATA_MEM_NUM_CHANNELS-1:0];
    logic [DATA_MEM_DATA_BITS-1:0] data_mem_data_mux [DATA_MEM_NUM_CHANNELS-1:0];
    logic data_mem_wren_mux [DATA_MEM_NUM_CHANNELS-1:0];
    logic data_mem_rden_mux [DATA_MEM_NUM_CHANNELS-1:0];
    
    integer ch_idx;
    
    // Generate 4 separate data memory instances
    genvar ch;
    generate
        for (ch = 0; ch < DATA_MEM_NUM_CHANNELS; ch = ch + 1) begin : data_mem_channels
            // Multiplex inputs for each channel based on initialization state
            assign data_mem_addr_mux[ch] = (init_state == INIT_DATA) ? init_index : 
                                            (data_mem_write_valid[ch]) ? data_mem_write_address[ch] : 
                                            data_mem_read_address[ch];
            
            assign data_mem_data_mux[ch] = (init_state == INIT_DATA) ? data_init_data[init_index] : data_mem_write_data[ch];
            
            assign data_mem_wren_mux[ch] = (init_state == INIT_DATA) ? 1'b1 : 
                                            (init_state == INIT_DONE && data_mem_write_valid[ch]) ? 1'b1 : 1'b0;
            
            assign data_mem_rden_mux[ch] = (init_state == INIT_DONE && data_mem_read_valid[ch]) ? 1'b1 : 1'b0;
            
            // Data memory instance for this channel
            data_mem_16A_16D data_mem_16A_16D_inst (
                .address(data_mem_addr_mux[ch]),
                .clock(clk),
                .data(data_mem_data_mux[ch]),
                .rden(data_mem_rden_mux[ch]),
                .wren(data_mem_wren_mux[ch]),
                .q(data_mem_q[ch])
            );
            
            // Pipeline delay for read valid signal (one cycle)
            logic data_mem_read_valid_delayed;
            
            always @(posedge clk) begin
                if (reset) begin
                    data_mem_read_valid_delayed <= 1'b0;
                end else begin
                    data_mem_read_valid_delayed <= data_mem_read_valid[ch];
                end
            end
            
            // Data memory output and ready signal
            assign data_mem_read_data[ch] = data_mem_q[ch];
            assign data_mem_read_ready[ch] = data_mem_read_valid_delayed;  // One cycle delayed for read
            assign data_mem_write_ready[ch] = data_mem_write_valid[ch];     // Immediate for write
        end
    endgenerate
    
    // State machine to handle initialization
    always @(posedge clk) begin
        if (reset) begin
            init_state <= INIT_IDLE;
            init_index <= 0;
        end else begin
            case (init_state)
                INIT_IDLE: begin
                    init_index <= 0;
                    init_state <= INIT_PROG;
                end
                INIT_PROG: begin
                    if (init_index < PROG_DATA_SIZE - 1) begin
                        init_index <= init_index + 1;
                    end else begin
                        init_index <= 0;
                        init_state <= INIT_DATA;
                    end
                end
                INIT_DATA: begin
                    if (init_index < DATA_SIZE - 1) begin
                        init_index <= init_index + 1;
                    end else begin
                        init_state <= INIT_DONE;
                    end
                end
                INIT_DONE: begin
                    // Initialization complete
                end
            endcase
        end
    end

///////////////////////////////////////////////////////////////////////////////////////////////

    // Device Control logicister
    dcr dcr_instance (
        .clk(clk),
        .reset(reset),

        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .thread_count(thread_count)
    );

    // Data Memory Controller
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_LSUS),
        .NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
    ) data_memory_controller (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(lsu_read_valid),
        .consumer_read_address(lsu_read_address),
        .consumer_read_ready(lsu_read_ready),
        .consumer_read_data(lsu_read_data),
        .consumer_write_valid(lsu_write_valid),
        .consumer_write_address(lsu_write_address),
        .consumer_write_data(lsu_write_data),
        .consumer_write_ready(lsu_write_ready),

        .mem_read_valid(data_mem_read_valid),
        .mem_read_address(data_mem_read_address),
        .mem_read_ready(data_mem_read_ready),
        .mem_read_data(data_mem_read_data),
        .mem_write_valid(data_mem_write_valid),
        .mem_write_address(data_mem_write_address),
        .mem_write_data(data_mem_write_data),
        .mem_write_ready(data_mem_write_ready)
    );

    // Program Memory Controller (with write support)
    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_FETCHERS),
        .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .WRITE_ENABLE(0)  // Enable write capability for program memory
    ) program_memory_controller (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(fetcher_read_valid),
        .consumer_read_address(fetcher_read_address),
        .consumer_read_ready(fetcher_read_ready),
        .consumer_read_data(fetcher_read_data),

        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data)
    );

    // Dispatcher
    dispatch #(
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dispatch_instance (
        .clk(clk),
        .reset(reset),
        .start(gated_start),
        .thread_count(thread_count),
        .core_done(core_done),
        .core_start(core_start),
        .core_reset(core_reset),
        .core_block_id(core_block_id),
        .core_thread_count(core_thread_count),
        .done(done)
    );

    // Compute Cores
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            // EDA: We create separate signals here to pass to cores because of a requirement
            // by the OpenLane EDA flow (uses Verilog 2005) that prevents slicing the top-level signals
            logic [THREADS_PER_BLOCK-1:0] core_lsu_read_valid;
            logic [DATA_MEM_ADDR_BITS-1:0] core_lsu_read_address [THREADS_PER_BLOCK-1:0];
            logic [THREADS_PER_BLOCK-1:0] core_lsu_read_ready;
            logic [DATA_MEM_DATA_BITS-1:0] core_lsu_read_data [THREADS_PER_BLOCK-1:0];
            logic [THREADS_PER_BLOCK-1:0] core_lsu_write_valid;
            logic [DATA_MEM_ADDR_BITS-1:0] core_lsu_write_address [THREADS_PER_BLOCK-1:0];
            logic [DATA_MEM_DATA_BITS-1:0] core_lsu_write_data [THREADS_PER_BLOCK-1:0];
            logic [THREADS_PER_BLOCK-1:0] core_lsu_write_ready;

            // Pass through signals between LSUs and data memory controller
            genvar j;
            for (j = 0; j < THREADS_PER_BLOCK; j = j + 1) begin : lsu_map
                localparam lsu_index = i * THREADS_PER_BLOCK + j;
                always @(posedge clk) begin 
                    lsu_read_valid[lsu_index] <= core_lsu_read_valid[j];
                    lsu_read_address[lsu_index] <= core_lsu_read_address[j];

                    lsu_write_valid[lsu_index] <= core_lsu_write_valid[j];
                    lsu_write_address[lsu_index] <= core_lsu_write_address[j];
                    lsu_write_data[lsu_index] <= core_lsu_write_data[j];
                    
                    core_lsu_read_ready[j] <= lsu_read_ready[lsu_index];
                    core_lsu_read_data[j] <= lsu_read_data[lsu_index];
                    core_lsu_write_ready[j] <= lsu_write_ready[lsu_index];
                end
            end

            // Compute Core
            core #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
            ) core_instance (
                .clk(clk),
                .reset(core_reset[i]),
                .start(core_start[i]),
                .done(core_done[i]),
                .block_id(core_block_id[i]),
                .thread_count(core_thread_count[i]),
                
                .program_mem_read_valid(fetcher_read_valid[i]),
                .program_mem_read_address(fetcher_read_address[i]),
                .program_mem_read_ready(fetcher_read_ready[i]),
                .program_mem_read_data(fetcher_read_data[i]),

                .data_mem_read_valid(core_lsu_read_valid),
                .data_mem_read_address(core_lsu_read_address),
                .data_mem_read_ready(core_lsu_read_ready),
                .data_mem_read_data(core_lsu_read_data),
                .data_mem_write_valid(core_lsu_write_valid),
                .data_mem_write_address(core_lsu_write_address),
                .data_mem_write_data(core_lsu_write_data),
                .data_mem_write_ready(core_lsu_write_ready)
            );
        end
    endgenerate
endmodule
