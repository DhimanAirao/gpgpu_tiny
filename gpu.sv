`default_nettype none
`timescale 1ns/1ns

// GPU
// > Built to use an external async memory with multi-channel read/write
// > Assumes that the program is loaded into program memory, data into data memory, and threads into
//   the device control register before the start signal is triggered
// > Has memory controllers to interface between external memory and its multiple cores
// > Configurable number of cores and thread capacity per core
module gpgpu #(
    parameter DATA_MEM_ADDR_BITS = 8,        // Number of bits in data memory address (256 rows)
    parameter DATA_MEM_DATA_BITS = 8,        // Number of bits in data memory value (8 bit data)
    parameter DATA_MEM_NUM_CHANNELS = 4,     // Number of concurrent channels for sending requests to data memory
    parameter PROGRAM_MEM_ADDR_BITS = 8,     // Number of bits in program memory address (256 rows)
    parameter PROGRAM_MEM_DATA_BITS = 16,    // Number of bits in program memory value (16 bit instruction)
    parameter PROGRAM_MEM_NUM_CHANNELS = 1,  // Number of concurrent channels for sending requests to program memory
    parameter NUM_CORES = 2,                 // Number of cores to include in this GPU
    parameter THREADS_PER_BLOCK = 4          // Number of threads to handle per block (determines the compute resources of each core)
) (
    input wire clk,
    input wire reset,

    // Kernel Execution
    input wire start,
    output wire done,

    // Device Control Register
    input wire device_control_write_enable,
    input wire [7:0] device_control_data,

    // Program Memory (internal: served from SDRAM)

    // Data Memory
    // Data Memory (internal: connected to SDRAM controller below)
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0],

    // SDRAM physical pins
    output [1:0]  sdram_ba_pad_o,
    output [12:0] sdram_a_pad_o,
    output        sdram_cs_n_pad_o,
    output        sdram_ras_pad_o,
    output        sdram_cas_pad_o,
    output        sdram_we_pad_o,
    inout  [15:0] sdram_dq_pad_io,
    output [1:0]  sdram_dqm_pad_o,
    output        sdram_cke_pad_o,
    output        sdram_clk_pad_o
);
    // Control
    wire [7:0] thread_count;

    // Program memory internal channels (served from SDRAM)
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];

    // Internal connection from SDRAM adapter back into the memory controller
    // These are driven by the SDRAM glue logic below (reg/wire types chosen to be driven)
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;

    // Compute Core State
    reg [NUM_CORES-1:0] core_start;
    reg [NUM_CORES-1:0] core_reset;
    reg [NUM_CORES-1:0] core_done;
    reg [7:0] core_block_id [NUM_CORES-1:0];
    reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];

    // LSU <> Data Memory Controller Channels
    localparam NUM_LSUS = NUM_CORES * THREADS_PER_BLOCK;
    reg [NUM_LSUS-1:0] lsu_read_valid;
    reg [DATA_MEM_ADDR_BITS-1:0] lsu_read_address [NUM_LSUS-1:0];
    reg [NUM_LSUS-1:0] lsu_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] lsu_read_data [NUM_LSUS-1:0];
    reg [NUM_LSUS-1:0] lsu_write_valid;
    reg [DATA_MEM_ADDR_BITS-1:0] lsu_write_address [NUM_LSUS-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] lsu_write_data [NUM_LSUS-1:0];
    reg [NUM_LSUS-1:0] lsu_write_ready;

    // Fetcher <> Program Memory Controller Channels
    localparam NUM_FETCHERS = NUM_CORES;
    reg [NUM_FETCHERS-1:0] fetcher_read_valid;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_read_address [NUM_FETCHERS-1:0];
    reg [NUM_FETCHERS-1:0] fetcher_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data [NUM_FETCHERS-1:0];


///////////////////////////////////////////////////////////////////////////////////////////////
    // SDRAM controller instance (single host port). We'll implement a small
    // arbiter below to service multiple memory channels from the GPU memory
    // controller and present a single host interface to this SDRAM controller.
    // Host signals for sdram_controller
    reg [31:0] sd_wr_addr; // wide enough to hold SDRAM HADDR_WIDTH
    reg [15:0] sd_wr_data;
    reg sd_wr_enable;
    reg [31:0] sd_rd_addr;
    wire [15:0] sd_rd_data;
    reg sd_rd_enable;
    wire sd_rd_ready;
    wire sd_busy;

    sdram_controller sdram_controlleri (
        .wr_addr       (sd_wr_addr),
        .wr_data       (sd_wr_data),
        .wr_enable     (sd_wr_enable),

        .rd_addr       (sd_rd_addr),
        .rd_data       (sd_rd_data),
        .rd_ready      (sd_rd_ready),
        .rd_enable     (sd_rd_enable),

        .busy          (sd_busy),
        .rst_n         (reset),
        .clk           (clk),

        .addr          (sdram_a_pad_o),
        .bank_addr     (sdram_ba_pad_o),
        .data          (sdram_dq_pad_io),
        .clock_enable  (sdram_cke_pad_o),
        .cs_n          (sdram_cs_n_pad_o),
        .ras_n         (sdram_ras_pad_o),
        .cas_n         (sdram_cas_pad_o),
        .we_n          (sdram_we_pad_o),
        .data_mask_low (sdram_dqm_pad_o[0]),
        .data_mask_high(sdram_dqm_pad_o[1])
    );

    // Simple single-ported arbiter: service first pending write, otherwise first pending read.
    // It presents a single host request to the SDRAM controller and returns ready/data
    // back to the appropriate memory channel when the SDRAM reports completion.
    integer ch_idx;
    reg active_req;
    reg active_is_write;
    reg active_is_program;
    integer active_channel;

    // Ensure outputs/ready/data default to zero when idle
    always @(posedge clk) begin
        if (reset) begin
            sd_wr_enable <= 0;
            sd_rd_enable <= 0;
            sd_wr_addr <= 0;
            sd_wr_data <= 0;
            sd_rd_addr <= 0;
            active_req <= 0;
            data_mem_read_ready <= {DATA_MEM_NUM_CHANNELS{1'b0}};
            data_mem_write_ready <= {DATA_MEM_NUM_CHANNELS{1'b0}};
            program_mem_read_ready <= {PROGRAM_MEM_NUM_CHANNELS{1'b0}};
            for (ch_idx = 0; ch_idx < DATA_MEM_NUM_CHANNELS; ch_idx = ch_idx + 1) begin
                data_mem_read_data[ch_idx] <= {DATA_MEM_DATA_BITS{1'b0}};
            end
            for (ch_idx = 0; ch_idx < PROGRAM_MEM_NUM_CHANNELS; ch_idx = ch_idx + 1) begin
                program_mem_read_data[ch_idx] <= {PROGRAM_MEM_DATA_BITS{1'b0}};
            end
        end else begin
            // default: clear ready flags (they are pulsed when operation completes)
            data_mem_read_ready <= {DATA_MEM_NUM_CHANNELS{1'b0}};
            data_mem_write_ready <= {DATA_MEM_NUM_CHANNELS{1'b0}};

            if (!active_req) begin
                // pick a write first (give writes priority), otherwise pick program read, then data read
                active_req <= 0;
                active_is_write <= 0;
                active_is_program <= 0;
                // check data writes first
                begin : check_writes
                    for (ch_idx = 0; ch_idx < DATA_MEM_NUM_CHANNELS; ch_idx = ch_idx + 1) begin
                        if (data_mem_write_valid[ch_idx]) begin
                            active_req <= 1;
                            active_is_write <= 1;
                            active_is_program <= 0;
                            active_channel = ch_idx;
                            // build SDRAM host signals (zero-extend address, expand data)
                            sd_wr_addr <= {24'b0, data_mem_write_address[ch_idx]};
                            sd_wr_data <= { {(16-DATA_MEM_DATA_BITS){1'b0}}, data_mem_write_data[ch_idx] };
                            sd_wr_enable <= 1;
                            disable check_writes;
                        end
                    end
                end
                // if no write picked, check program reads
                if (!active_req) begin : check_prog_reads
                    for (ch_idx = 0; ch_idx < PROGRAM_MEM_NUM_CHANNELS; ch_idx = ch_idx + 1) begin
                        if (program_mem_read_valid[ch_idx]) begin
                            active_req <= 1;
                            active_is_write <= 0;
                            active_is_program <= 1;
                            active_channel = ch_idx;
                            sd_rd_addr <= {24'b0, program_mem_read_address[ch_idx]};
                            sd_rd_enable <= 1;
                            disable check_prog_reads;
                        end
                    end
                end
                // if still no active req, check data reads
                if (!active_req) begin : check_data_reads
                    for (ch_idx = 0; ch_idx < DATA_MEM_NUM_CHANNELS; ch_idx = ch_idx + 1) begin
                        if (data_mem_read_valid[ch_idx]) begin
                            active_req <= 1;
                            active_is_write <= 0;
                            active_is_program <= 0;
                            active_channel = ch_idx;
                            sd_rd_addr <= {24'b0, data_mem_read_address[ch_idx]};
                            sd_rd_enable <= 1;
                            disable check_data_reads;
                        end
                    end
                end
            end else begin
                // We have an active request in flight
                if (active_is_write) begin
                    // For writes, signal ready back to controller when SDRAM is not busy
                    if (!sd_busy) begin
                        data_mem_write_ready[active_channel] <= 1;
                        sd_wr_enable <= 0;
                        active_req <= 0;
                    end
                end else begin
                    // For reads, wait for sd_rd_ready and then provide data
                    if (sd_rd_ready) begin
                        if (active_is_program) begin
                            program_mem_read_data[active_channel] <= sd_rd_data[PROGRAM_MEM_DATA_BITS-1:0];
                            program_mem_read_ready[active_channel] <= 1;
                        end else begin
                            data_mem_read_data[active_channel] <= sd_rd_data[DATA_MEM_DATA_BITS-1:0];
                            data_mem_read_ready[active_channel] <= 1;
                        end
                        sd_rd_enable <= 0;
                        active_req <= 0;
                    end
                end
            end
        end
    end

///////////////////////////////////////////////////////////////////////////////////////////////

    // Device Control Register
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

    // Program Memory Controller
    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_FETCHERS),
        .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .WRITE_ENABLE(0)
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
        .start(start),
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
            reg [THREADS_PER_BLOCK-1:0] core_lsu_read_valid;
            reg [DATA_MEM_ADDR_BITS-1:0] core_lsu_read_address [THREADS_PER_BLOCK-1:0];
            reg [THREADS_PER_BLOCK-1:0] core_lsu_read_ready;
            reg [DATA_MEM_DATA_BITS-1:0] core_lsu_read_data [THREADS_PER_BLOCK-1:0];
            reg [THREADS_PER_BLOCK-1:0] core_lsu_write_valid;
            reg [DATA_MEM_ADDR_BITS-1:0] core_lsu_write_address [THREADS_PER_BLOCK-1:0];
            reg [DATA_MEM_DATA_BITS-1:0] core_lsu_write_data [THREADS_PER_BLOCK-1:0];
            reg [THREADS_PER_BLOCK-1:0] core_lsu_write_ready;

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
