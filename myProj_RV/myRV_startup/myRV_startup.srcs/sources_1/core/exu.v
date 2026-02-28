`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/11 18:57:41
// Design Name: 
// Module Name: exu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "../defines/config.v"

module exu(
    input  wire clk,
    input  wire rst_n,
    input  wire [31:0] i_rf_rs1_data,
    input  wire [31:0] i_rf_rs2_data,
    input  wire [31:0] i_dec_imm,
    input  wire [`DECINFO_BUS_WIDTH-1:0] i_dec_info_bus_id,
    output wire [31:0] o_wrbk_data_ex,
    input  wire [31:0] i_pc_id,
    // mem access
    output wire [31:0] o_mema_addr,
    output wire o_mema_wren,
    input  wire [31:0] i_mema_rd_data,
    output wire [31:0] o_mema_wr_data,
    // pass by
    input  wire [`RFIDX_WIDTH-1:0] i_dec_rdidx_id,
    input  wire i_dec_rdwen_id,
    output wire [`RFIDX_WIDTH-1:0] o_wrbk_rdidx_ex,
    output wire o_wrbk_wen_ex
    );

// ================================================================
// ----------------        Pipeline Regs        ---------------- //
// to wb
reg [`RFIDX_WIDTH-1:0] r_wrbk_rdidx_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdidx_ex <= 'd0;
    end
    else begin
        r_wrbk_rdidx_ex <= i_dec_rdidx_id;
    end
end
assign o_wrbk_rdidx_ex = r_wrbk_rdidx_ex;

reg r_wrbk_wen_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_wen_ex <= 1'b0;
    end
    else begin
        r_wrbk_wen_ex <= i_dec_rdwen_id;
    end
end
assign o_wrbk_wen_ex = r_wrbk_wen_ex;


// Comb in, reg 
reg [31:0] rf_rs1_r_ex, rf_rs2_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rf_rs1_r_ex <= 32'd0;
        rf_rs2_r_ex <= 32'd0;
    end
    else begin
        rf_rs1_r_ex <= i_rf_rs1_data;
        rf_rs2_r_ex <= i_rf_rs2_data;
    end
end

reg [31:0] dec_imm_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dec_imm_r_ex <= 32'd0;
    end
    else begin
        dec_imm_r_ex <= i_dec_imm;
    end
end

reg [31:0] pc_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_r_ex <= 32'b0;
    end
    else begin
        pc_r_ex <= i_pc_id;
    end
end

reg [`DECINFO_BUS_WIDTH-1:0] r_dec_info_bus_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_dec_info_bus_ex <= {`DECINFO_BUS_WIDTH{1'b0}};
    end
    else begin
        r_dec_info_bus_ex <= i_dec_info_bus_id;
    end
end



// ================================================================
// ----------------        Datapath Dispatch        ---------------- //
wire req_disp_alu = (r_dec_info_bus_ex[`DECINFO_GRP] == `DECINFO_GRP_WIDTH'd0);
wire req_disp_lsu = (r_dec_info_bus_ex[`DECINFO_GRP] == `DECINFO_GRP_WIDTH'd1);
wire req_disp_bru = (r_dec_info_bus_ex[`DECINFO_GRP] == `DECINFO_GRP_WIDTH'd2);
wire req_disp_csr = (r_dec_info_bus_ex[`DECINFO_GRP] == `DECINFO_GRP_WIDTH'd3);

// ---- dec_info_bus dispatch
wire [`DECINFO_BUS_ALU_WIDTH-1:0] dec_info_bus_alu = {`DECINFO_BUS_ALU_WIDTH{req_disp_alu}} & r_dec_info_bus_ex[`DECINFO_BUS_ALU_WIDTH-1:0];
wire [`DECINFO_BUS_LSU_WIDTH-1:0] dec_info_bus_lsu = {`DECINFO_BUS_LSU_WIDTH{req_disp_lsu}} & r_dec_info_bus_ex[`DECINFO_BUS_LSU_WIDTH-1:0];
wire [`DECINFO_BUS_BRU_WIDTH-1:0] dec_info_bus_bru = {`DECINFO_BUS_BRU_WIDTH{req_disp_bru}} & r_dec_info_bus_ex[`DECINFO_BUS_BRU_WIDTH-1:0];
// assign dec_info_bus_alu = r_dec_info_bus_ex;


// ---- results wrbk
wire [31:0] alu_req_result;
wire [31:0] lsu_req_result;
assign o_wrbk_data_ex = ({`XWIDTH{req_disp_alu}} & alu_req_result)
                      | ({`XWIDTH{req_disp_lsu}} & lsu_req_result);


// ---- rs1, rs2, imm logic-gating
wire [`XWIDTH-1:0] alu_rs1 = {`XWIDTH{req_disp_alu}} & rf_rs1_r_ex;
wire [`XWIDTH-1:0] alu_rs2 = {`XWIDTH{req_disp_alu}} & rf_rs2_r_ex;
wire [`XWIDTH-1:0] alu_imm = {`XWIDTH{req_disp_alu}} & dec_imm_r_ex;

wire [`XWIDTH-1:0] lsu_rs1 = {`XWIDTH{req_disp_lsu}} & rf_rs1_r_ex;
wire [`XWIDTH-1:0] lsu_rs2 = {`XWIDTH{req_disp_lsu}} & rf_rs2_r_ex;
wire [`XWIDTH-1:0] lsu_imm = {`XWIDTH{req_disp_lsu}} & dec_imm_r_ex;

wire [`XWIDTH-1:0] bru_rs1 = {`XWIDTH{req_disp_bru}} & rf_rs1_r_ex;
wire [`XWIDTH-1:0] bru_rs2 = {`XWIDTH{req_disp_bru}} & rf_rs2_r_ex;
wire [`XWIDTH-1:0] bru_imm = {`XWIDTH{req_disp_bru}} & dec_imm_r_ex;


// ----------------        Instantiations        ---------------- //

// // ---- op1 and op2
// wire [31:0] alu_req_op1, alu_req_op2;
// assign alu_req_op1 = (dec_info_bus_alu[`DECINFO_ALU_OP1PC]) ? pc_r_ex : rf_rs1_r_ex;
// assign alu_req_op2 = (dec_info_bus_alu[`DECINFO_ALU_OP2IMM]) ? dec_imm_r_ex : rf_rs2_r_ex;
exu_alu u_exu_alu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_alu_rs1          (alu_rs1            ),
    .i_alu_rs2          (alu_rs2            ),
    .i_alu_imm          (alu_imm            ),
    .i_alu_pc           (pc_r_ex            ),
    .i_dec_info_bus_alu (dec_info_bus_alu   ),
    .o_alu_req_result   (alu_req_result     )
    );


exu_lsu u_exu_lsu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_lsu_rs1          (lsu_rs1            ),
    .i_lsu_rs2          (lsu_rs2            ),
    .i_lsu_imm          (lsu_imm            ),
    .i_dec_info_bus_lsu (dec_info_bus_lsu   ),
    .o_mema_addr        (o_mema_addr        ),
    .o_mema_wren        (o_mema_wren        ),
    .i_mema_rd_data     (i_mema_rd_data     ),
    .o_mema_wr_data     (o_mema_wr_data     ),
    .o_lsu_req_result   (lsu_req_result     )
    );






// exu_alu u_exu_alu(
//     .clk                (clk    ),
//     .rst_n              (rst_n  ),
//     .i_alu_req_op1      (alu_req_op1        ),
//     .i_alu_req_op2      (alu_req_op2        ),
//     .i_dec_info_bus_alu (dec_info_bus_alu   ),
//     .o_alu_req_result   (alu_req_result     )
//     );

endmodule
