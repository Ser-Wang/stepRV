`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/24
// Design Name: StepRV_v0
// Module Name: regfile
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module regfile(
    input wire clk,
    input wire rst_n,
    input wire [4:0] i_read_rs1_idx,
    input wire [4:0] i_read_rs2_idx,
    output wire [31:0] o_read_rs1_data,
    output wire [31:0] o_read_rs2_data,
    input wire i_wrbk_wen,
    input wire [4:0] i_wrbk_rdidx,   // write back
    input wire [31:0] i_wrbk_data
    );

reg [31:0] r_regfile[1:31];
wire [31:0] w_regfile[0:31];
wire [31:0] wen;

// write through
wire write_through_flag_rs1 = i_wrbk_wen & (i_wrbk_rdidx != 5'd0) & (i_wrbk_rdidx == i_read_rs1_idx);    // actually i_wb_en won't be 1'b1 when rdidx == x0.
wire write_through_flag_rs2 = i_wrbk_wen & (i_wrbk_rdidx != 5'd0) & (i_wrbk_rdidx == i_read_rs2_idx);

// read
assign o_read_rs1_data = write_through_flag_rs1 ? i_wrbk_data : w_regfile[i_read_rs1_idx];
assign o_read_rs2_data = write_through_flag_rs2 ? i_wrbk_data : w_regfile[i_read_rs2_idx];

// write
genvar i;
generate
    for (i=0; i<32; i=i+1) begin: gen_regfile
        if (i == 0) begin: x0
            assign wen[i] = 1'b0;
            assign w_regfile[i] = 32'b0;
        end
        else begin
            assign w_regfile[i] = r_regfile[i];
            assign wen[i] = i_wrbk_wen & (i_wrbk_rdidx == i);
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    r_regfile[i] <= 32'b0;
                end
                else if(wen[i]) begin
                    r_regfile[i] <= i_wrbk_data;
                end
            end
        end
    end
endgenerate


endmodule
