`timescale 1ns/1ns

module alu #(
    parameter DATA_MEM_ADDR_BITS = 16,        // Number of bits in data memory address (256 rows)
    parameter DATA_MEM_DATA_BITS = 16         // Number of bits in data memory value (8 bit data)
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,

    input  logic [2:0]  core_state,

    input  logic [3:0]  decoded_alu_arithmetic_mux,
    input  logic        decoded_alu_output_mux,
    input  logic        decoded_fp_enable,   // 1 = minifloat, 0 = integer
    input  logic        decoded_imm_enable,

    input  logic [DATA_MEM_DATA_BITS-1:0]  rs,
    input  logic [DATA_MEM_DATA_BITS-1:0]  rt,
    output logic [DATA_MEM_DATA_BITS-1:0]  alu_out
);

    localparam ADD = 4'h0,
               SUB = 4'h1,
               MUL = 4'h2,
               DIV = 4'h3,
               REM = 4'h4,
               NOT = 4'h5,
               AND = 4'h6,
               OR  = 4'h7,
               XOR = 4'h8,
               SLL = 4'h9,
               SRL = 4'hA,
               NOTL = 4'hB,
               ANDL = 4'hC,
               ORL  = 4'hD;


    localparam int FP16_BIAS = 15;

    logic [DATA_MEM_DATA_BITS-1:0] alu_out_logic;
    assign alu_out = alu_out_logic;

    // -----------------------------
    // FP16 helpers (1S5E10)
    // -----------------------------

    function automatic logic mf16_sign(input logic [15:0] f);
        return f[15];
    endfunction

    function automatic logic [4:0] mf16_exponent(input logic [15:0] f);
        return f[14:10];
    endfunction

    function automatic logic [10:0] mf16_mantissa(input logic [15:0] f);
        // implicit 1 + 10 fraction bits
        return {1'b1, f[9:0]};
    endfunction


    // -----------------------------
    // FP16 ADD
    // -----------------------------
    function automatic logic [15:0] fp16_add(
        input logic [15:0] a,
        input logic [15:0] b
    );
        logic sa, sb, sr;
        logic [4:0] ea, eb, er;
        logic [10:0] ma, mb;
        logic signed [12:0] mr;
        int shift;

        sa = mf16_sign(a);
        sb = mf16_sign(b);
        ea = mf16_exponent(a);
        eb = mf16_exponent(b);
        ma = mf16_mantissa(a);
        mb = mf16_mantissa(b);

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

        // Apply sign
        mr = (sa ? -ma : ma) + (sb ? -mb : mb);

        // Result sign
        sr = mr < 0;
        if (sr) mr = -mr;

        // Normalize
        if (mr[12]) begin
            mr = mr >> 1;
            er = er + 1;
        end

        fp16_add = {sr, er, mr[9:0]};
    endfunction


    // -----------------------------
    // FP16 MUL
    // -----------------------------
    function automatic logic [15:0] fp16_mul(
        input logic [15:0] a,
        input logic [15:0] b
    );
        logic sa, sb, sr;
        logic [4:0] ea, eb, er;
        logic [10:0] ma, mb;
        logic [21:0] prod;

        sa = mf16_sign(a);
        sb = mf16_sign(b);
        sr = sa ^ sb;

        ea = mf16_exponent(a);
        eb = mf16_exponent(b);
        ma = mf16_mantissa(a);
        mb = mf16_mantissa(b);

        prod = ma * mb; // 11x11 = 22 bits

        er = ea + eb - FP16_BIAS;

        // Normalize
        if (prod[21]) begin
            prod = prod >> 1;
            er   = er + 1;
        end else begin
            prod = prod >> 10;
        end

        fp16_mul = {sr, er, prod[9:0]};
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
            end else if (decoded_imm_enable) begin
                case (decoded_alu_arithmetic_mux)

                    ADD: alu_out_logic <= rs + rt;

                    SUB: alu_out_logic <= rs - rt;

                    MUL: alu_out_logic <= rs * rt;

                    DIV: alu_out_logic <= rs / rt;
                endcase
            end else begin
                case (decoded_alu_arithmetic_mux)

                    ADD: alu_out_logic <= decoded_fp_enable
                        ? fp16_add(rs, rt)
                        : rs + rt;

                    SUB: alu_out_logic <= decoded_fp_enable
                        ? 8'b0        // FP SUB not implemented
                        : rs - rt;

                    MUL: alu_out_logic <= decoded_fp_enable
                        ? fp16_mul(rs, rt)
                        : rs * rt;

                    DIV: alu_out_logic <= decoded_fp_enable
                        ? 8'b0        // FP DIV intentionally omitted
                        : rs / rt;

                    REM: alu_out_logic <= rs % rt;

                    NOT: alu_out_logic <= ~rs;

                    AND: alu_out_logic <= rs & rt;

                    OR: alu_out_logic <= rs | rt;

                    XOR: alu_out_logic <= rs ^ rt;

                    SLL: alu_out_logic <= rs << rt;

                    SRL: alu_out_logic <= rs >> rt;

                    NOTL: alu_out_logic <= !rs;

                    ANDL: alu_out_logic <= rs && rt;

                    ORL: alu_out_logic <= rs || rt;

                endcase
            end
        end
    end

endmodule
