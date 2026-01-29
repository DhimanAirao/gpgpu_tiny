`timescale 1ns/1ns
`include "opcode_defs.svh"

// INSTRUCTION DECODER
// > Decodes an instruction into the control signals necessary to execute it
// > Each core has it's own decoder
module decoder #(
    parameter DATA_MEM_ADDR_BITS = 16,        // Number of bits in data memory address (256 rows)
    parameter DATA_MEM_DATA_BITS = 16,        // Number of bits in data memory value (8 bit data)
    parameter PROGRAM_MEM_ADDR_BITS = 16,     // Number of bits in program memory address (256 rows)
    parameter PROGRAM_MEM_DATA_BITS = 32    // Number of bits in program memory value (16 bit instruction)
) (
    input logic clk,
    input logic reset,

    input logic [2:0] core_state,
    input logic [PROGRAM_MEM_DATA_BITS-1:0] instruction,
    
    // Instruction Signals
    output logic [3:0] decoded_rd_address,
    output logic [3:0] decoded_rs_address,
    output logic [3:0] decoded_rt_address,
    output logic [2:0] decoded_nzp,
    output logic [7:0] decoded_immediate,
    
    // Control Signals
    output logic decoded_reg_write_enable,           // Enable writing to a register
    output logic decoded_mem_read_enable,            // Enable reading from memory
    output logic decoded_mem_write_enable,           // Enable writing to memory
    output logic decoded_nzp_write_enable,           // Enable writing to NZP register
    output logic [1:0] decoded_reg_input_mux,        // Select input to register
    output logic [2:0] decoded_alu_arithmetic_mux,   // Select arithmetic operation
    output logic decoded_fp_enable,
    output logic decoded_imm_enable,
    output logic decoded_alu_output_mux,             // Select operation in ALU
    output logic decoded_pc_mux,                     // Select source of next PC

    // Return (finished executing thread)
    output logic decoded_ret
);

    always @(posedge clk) begin 
        if (reset) begin 
            decoded_rd_address <= 0;
            decoded_rs_address <= 0;
            decoded_rt_address <= 0;
            decoded_immediate <= 0;
            decoded_nzp <= 0;
            decoded_reg_write_enable <= 0;
            decoded_mem_read_enable <= 0;
            decoded_mem_write_enable <= 0;
            decoded_nzp_write_enable <= 0;
            decoded_reg_input_mux <= 0;
            decoded_alu_arithmetic_mux <= 0;
            decoded_alu_output_mux <= 0;
            decoded_fp_enable <= 0;
            decoded_imm_enable <= 0;
            decoded_pc_mux <= 0;
            decoded_ret <= 0;
        end else begin 
            // Decode when core_state = DECODE
            if (core_state == 3'b010) begin 
                // Get instruction signals from instruction every time
                decoded_rd_address <= instruction[11:8];
                decoded_rs_address <= instruction[7:4];
                decoded_rt_address <= instruction[3:0];
                decoded_immediate <= instruction[7:0];
                decoded_nzp <= instruction[11:9];

                // Control signals reset on every decode and set conditionally by instruction
                decoded_reg_write_enable <= 0;
                decoded_mem_read_enable <= 0;
                decoded_mem_write_enable <= 0;
                decoded_nzp_write_enable <= 0;
                decoded_reg_input_mux <= 0;
                decoded_alu_arithmetic_mux <= 0;
                decoded_alu_output_mux <= 0;
                decoded_fp_enable <= 0;
                decoded_imm_enable <= 0;
                decoded_pc_mux <= 0;
                decoded_ret <= 0;

                // Set the control signals for each instruction
                case (instruction[19:12])
                    NOP: begin 
                        // no-op
                    end
                    BRnzp: begin 
                        decoded_pc_mux <= 1;
                    end
                    CMP: begin 
                        decoded_alu_output_mux <= 1;
                        decoded_nzp_write_enable <= 1;
                    end
                    ADD: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 3'b000;
                    end
                    SUB: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 3'b001;
                    end
                    MUL: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 3'b010;
                    end
                    DIV: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 3'b011;
                    end
                    LDR: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b01;
                        decoded_mem_read_enable <= 1;
                    end
                    STR: begin 
                        decoded_mem_write_enable <= 1;
                    end
                    CONST: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b10;
                    end
                    RET: begin 
                        decoded_ret <= 1;
                    end
                    ADDFP: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 3'b000;
                        decoded_fp_enable <= 1;
                    end
                    MULFP: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 3'b010;
                        decoded_fp_enable <= 1;
                    end
                endcase
            end
        end
    end
endmodule
