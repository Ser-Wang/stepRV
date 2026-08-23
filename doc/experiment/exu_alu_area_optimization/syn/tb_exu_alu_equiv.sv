`timescale 1ns / 1ps
`include "config.v"

module tb_exu_alu_equiv;
reg  [31:0] i_alu_rs1;
reg  [31:0] i_alu_rs2;
reg  [31:0] i_alu_imm;
reg  [31:0] i_alu_pc;
reg  [`DECINFO_BUS_ALU_WIDTH-1:0] i_dec_info_bus_alu;
wire [31:0] current_data;
wire [31:0] unshared_data;
wire [31:0] no_isolation_data;
integer vector_idx;
integer op_idx;
integer errors;

exu_alu u_current (
    .i_alu_rs1(i_alu_rs1), .i_alu_rs2(i_alu_rs2),
    .i_alu_imm(i_alu_imm), .i_alu_pc(i_alu_pc),
    .i_dec_info_bus_alu(i_dec_info_bus_alu), .o_alu_wb_data(current_data)
);

exu_alu_unshared u_unshared (
    .i_alu_rs1(i_alu_rs1), .i_alu_rs2(i_alu_rs2),
    .i_alu_imm(i_alu_imm), .i_alu_pc(i_alu_pc),
    .i_dec_info_bus_alu(i_dec_info_bus_alu), .o_alu_wb_data(unshared_data)
);

exu_alu_no_isolation u_no_isolation (
    .i_alu_rs1(i_alu_rs1), .i_alu_rs2(i_alu_rs2),
    .i_alu_imm(i_alu_imm), .i_alu_pc(i_alu_pc),
    .i_dec_info_bus_alu(i_dec_info_bus_alu), .o_alu_wb_data(no_isolation_data)
);

initial begin
    errors = 0;
    for (vector_idx = 0; vector_idx < 1000; vector_idx = vector_idx + 1) begin
        i_alu_rs1 = $urandom;
        i_alu_rs2 = $urandom;
        i_alu_imm = $urandom;
        i_alu_pc  = $urandom;
        for (op_idx = 0; op_idx < 11; op_idx = op_idx + 1) begin
            i_dec_info_bus_alu = '0;
            i_dec_info_bus_alu[`DECINFO_ALU_OP1PC]  = $urandom_range(0, 1);
            i_dec_info_bus_alu[`DECINFO_ALU_OP2IMM] = $urandom_range(0, 1);
            case (op_idx)
                0:  i_dec_info_bus_alu[`DECINFO_ALU_ADD]  = 1'b1;
                1:  i_dec_info_bus_alu[`DECINFO_ALU_SUB]  = 1'b1;
                2:  i_dec_info_bus_alu[`DECINFO_ALU_SLL]  = 1'b1;
                3:  i_dec_info_bus_alu[`DECINFO_ALU_SLT]  = 1'b1;
                4:  i_dec_info_bus_alu[`DECINFO_ALU_SLTU] = 1'b1;
                5:  i_dec_info_bus_alu[`DECINFO_ALU_XOR]  = 1'b1;
                6:  i_dec_info_bus_alu[`DECINFO_ALU_SRL]  = 1'b1;
                7:  i_dec_info_bus_alu[`DECINFO_ALU_SRA]  = 1'b1;
                8:  i_dec_info_bus_alu[`DECINFO_ALU_OR]   = 1'b1;
                9:  i_dec_info_bus_alu[`DECINFO_ALU_AND]  = 1'b1;
                10: i_dec_info_bus_alu[`DECINFO_ALU_LUI]  = 1'b1;
            endcase
            #1;
            if ((current_data !== unshared_data) ||
                (current_data !== no_isolation_data)) begin
                $display("Mismatch vector=%0d op=%0d current=%h unshared=%h no_iso=%h",
                         vector_idx, op_idx, current_data, unshared_data, no_isolation_data);
                errors = errors + 1;
            end
        end
    end
    if (errors == 0)
        $display("[PASS] 11000 single-operation vectors matched");
    else
        $display("[FAIL] %0d mismatches", errors);
    $finish;
end

endmodule
