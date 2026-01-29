`timescale 1ns/1ns

module alu #(
    parameter DATA_MEM_ADDR_BITS = 16,        // Number of bits in data memory address (256 rows)
    parameter DATA_MEM_DATA_BITS = 16         // Number of bits in data memory value (8 bit data)
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,

    input  logic [2:0]  core_state,

    input  logic [2:0]  decoded_alu_arithmetic_mux,
    input  logic        decoded_alu_output_mux,
    input  logic        decoded_fp_enable,   // 1 = minifloat, 0 = integer
    input  logic        decoded_imm_enable,

    input  logic [DATA_MEM_DATA_BITS-1:0]  rs,
    input  logic [DATA_MEM_DATA_BITS-1:0]  rt,
    output logic [DATA_MEM_DATA_BITS-1:0]  alu_out
);

    localparam ADD = 3'b000,
               SUB = 3'b001,
               MUL = 3'b010,
               DIV = 3'b011;

    localparam FP_BIAS = 7;

    logic [DATA_MEM_DATA_BITS-1:0] alu_out_logic;
    assign alu_out = alu_out_logic;


    // -----------------------------
    // Minifloat helpers (E4M4)
    // -----------------------------

    function automatic logic [4:0] mf_mantissa(input logic [7:0] f);
        mf_mantissa = {1'b1, f[3:0]}; // implicit 1 + 4 fraction bits
    endfunction

    function automatic logic [3:0] mf_exponent(input logic [7:0] f);
        mf_exponent = f[7:4];
    endfunction

    // -----------------------------
    // Minifloat ADD
    // -----------------------------
    function automatic logic [7:0] minifloat_add(
        input logic [7:0] a,
        input logic [7:0] b
    );
        logic [3:0] ea, eb, er;
        logic [4:0] ma, mb;
        logic [5:0] mr;
        int shift;

        ea = mf_exponent(a);
        eb = mf_exponent(b);

        ma = mf_mantissa(a);
        mb = mf_mantissa(b);

        // Align exponents
        if (ea > eb) begin
            shift = ea - eb;
            mb = mb >> shift;
            er = ea;
        end else begin
            shift = eb - ea;
            ma = ma >> shift;
            er = eb;
        end

        // Add mantissas
        mr = ma + mb;

        // Normalize
        if (mr >= 32) begin
            mr = mr >> 1;
            er = er + 1;
        end

        minifloat_add = {er, mr[3:0]};
    endfunction

    // -----------------------------
    // Minifloat MUL
    // -----------------------------
    function automatic logic [7:0] minifloat_mul(
        input logic [7:0] a,
        input logic [7:0] b
    );
        logic [3:0] ea, eb, er;
        logic [4:0] ma, mb;
        logic [9:0] prod;

        ea = mf_exponent(a);
        eb = mf_exponent(b);

        ma = mf_mantissa(a);
        mb = mf_mantissa(b);

        prod = ma * mb; // up to 10 bits

        er = ea + eb - FP_BIAS;

        // Normalize
        if (prod[9]) begin
            prod = prod >> 1;
            er   = er + 1;
        end else begin
            prod = prod >> 4;
        end

        minifloat_mul = {er, prod[3:0]};
    endfunction

    // -----------------------------
    // ALU sequential logic
    // -----------------------------
    always @(posedge clk) begin
        if (reset) begin
            alu_out_logic <= 8'b0;
        end else if (enable && core_state == 3'b101) begin

            if (decoded_alu_output_mux) begin
                alu_out_logic <= {5'b0,
                                  (rs > rt),
                                  (rs == rt),
                                  (rs < rt)};
            end else begin
                case (decoded_alu_arithmetic_mux)

                    ADD: alu_out_logic <= decoded_fp_enable
                        ? minifloat_add(rs, rt)
                        : rs + rt;

                    SUB: alu_out_logic <= decoded_fp_enable
                        ? 8'b0        // FP SUB not implemented
                        : rs - rt;

                    MUL: alu_out_logic <= decoded_fp_enable
                        ? minifloat_mul(rs, rt)
                        : rs * rt;

                    DIV: alu_out_logic <= decoded_fp_enable
                        ? 8'b0        // FP DIV intentionally omitted
                        : rs / rt;

                endcase
            end
        end
    end

endmodule
