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
    input  wire i_stall,
    input  wire i_flush,
    input  wire [31:0] i_rf_rs1_data,
    input  wire [31:0] i_rf_rs2_data,
    input  wire [31:0] i_dec_imm,
    input  wire [31:0] i_pc_id,
    input  wire [`DECINFO_BUS_WIDTH-1:0] i_dec_info_bus_id,
    output wire [31:0] o_wrbk_data_exu,
    // forwarding
    input wire i_need_rs1_idu,
    input wire i_need_rs2_idu,
    output wire o_need_rs1_exu,
    output wire o_need_rs2_exu,
    input wire [`RFIDX_WIDTH-1:0] i_rs1idx_idu,
    input wire [`RFIDX_WIDTH-1:0] i_rs2idx_idu,
    output wire [`RFIDX_WIDTH-1:0] o_rs1idx_exu,
    output wire [`RFIDX_WIDTH-1:0] o_rs2idx_exu,
    input wire [31:0] i_fwd_wrbk_data_mau,
    input wire [31:0] i_fwd_wrbk_data_wbu,
    input wire [1:0] i_fwding_rs1_sel,
    input wire [1:0] i_fwding_rs2_sel,
    // branch
    output wire [31:0] o_pc_next_bru,
    output wire o_jump_flag,
    // to mem access unit
    output wire [31:0] o_mema_addr_exu,
    output wire [31:0] o_mema_wr_data_exu,
    output wire o_mema_wren_exu,
    output wire [3:0] o_mema_wr_mask,
    output wire [3:0] o_mema_ld_info,  // {lsu_req_load, lsu_req_info_size, lsu_req_info_usign}
    // input  wire [31:0] i_mema_rd_data,
    // pass by
    input  wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_idu,
    input  wire i_wrbk_rdwen_idu,
    output wire [`RFIDX_WIDTH-1:0] o_wrbk_rdidx_exu,
    output wire o_wrbk_rdwen_exu
    );

// ================================================================
// ----------------        Pipeline Regs        ---------------- //
//---- pass by, to wb
reg [`RFIDX_WIDTH-1:0] r_wrbk_rdidx_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdidx_exu <= 'd0;
    end
    else if(!i_stall) begin
        r_wrbk_rdidx_exu <= i_wrbk_rdidx_idu;
    end
end
assign o_wrbk_rdidx_exu = r_wrbk_rdidx_exu;

reg r_wrbk_wen_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_wen_exu <= 1'b0;
    end
    else if(i_flush) begin
        r_wrbk_wen_exu <= 1'b0;
    end
    else if(!i_stall) begin
        r_wrbk_wen_exu <= i_wrbk_rdwen_idu;
    end
end
assign o_wrbk_rdwen_exu = r_wrbk_wen_exu;


// Comb in, reg 
reg [31:0] rf_rs1_r_ex, rf_rs2_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rf_rs1_r_ex <= 32'd0;
        rf_rs2_r_ex <= 32'd0;
    end
    else if(!i_stall) begin
        rf_rs1_r_ex <= i_rf_rs1_data;
        rf_rs2_r_ex <= i_rf_rs2_data;
    end
end

reg [31:0] dec_imm_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dec_imm_r_ex <= 32'd0;
    end
    else if(!i_stall) begin
        dec_imm_r_ex <= i_dec_imm;
    end
end

reg [31:0] r_pc_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_pc_exu <= 32'b0;
    end
    else if(!i_stall) begin
        r_pc_exu <= i_pc_id;
    end
end

reg [`DECINFO_BUS_WIDTH-1:0] r_dec_info_bus_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_dec_info_bus_ex <= {`DECINFO_BUS_WIDTH{1'b0}};
    end
    else if(i_flush) begin
        r_dec_info_bus_ex <= 'd0;
    end
    else if(!i_stall) begin
        r_dec_info_bus_ex <= i_dec_info_bus_id;
    end
end

//---- for forwarding and stall
reg r_need_rs1_exu, r_need_rs2_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_need_rs1_exu <= 1'b0;
        r_need_rs2_exu <= 1'b0;
    end
    else if(i_flush) begin
        r_need_rs1_exu <= 1'b0;
        r_need_rs2_exu <= 1'b0;
    end
    else if(!i_stall) begin
        r_need_rs1_exu <= i_need_rs1_idu;
        r_need_rs2_exu <= i_need_rs2_idu;
    end
end
assign o_need_rs1_exu = r_need_rs1_exu;
assign o_need_rs2_exu = r_need_rs2_exu;


reg [`RFIDX_WIDTH-1:0] r_rs1idx_exu;
reg [`RFIDX_WIDTH-1:0] r_rs2idx_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rs1idx_exu <= 'd0;
        r_rs2idx_exu <= 'd0;
    end
    else if(!i_stall) begin
        r_rs1idx_exu <= i_rs1idx_idu;
        r_rs2idx_exu <= i_rs2idx_idu;
    end
end
assign o_rs1idx_exu = r_rs1idx_exu;
assign o_rs2idx_exu = r_rs2idx_exu;


// ================================================================
// ----------------        Data Forwarding        ---------------- //
wire [`XWIDTH-1:0] rs1_fwded, rs2_fwded;
assign rs1_fwded = (~i_fwding_rs1_sel[1]) ? rf_rs1_r_ex : 
                   ( i_fwding_rs1_sel[0]) ? i_fwd_wrbk_data_wbu : i_fwd_wrbk_data_mau;
assign rs2_fwded = (~i_fwding_rs2_sel[1]) ? rf_rs2_r_ex : 
                   ( i_fwding_rs2_sel[0]) ? i_fwd_wrbk_data_wbu : i_fwd_wrbk_data_mau;



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


// ---- rs1, rs2, imm logic-gating
wire [`XWIDTH-1:0] alu_rs1 = {`XWIDTH{req_disp_alu}} & rs1_fwded;
wire [`XWIDTH-1:0] alu_rs2 = {`XWIDTH{req_disp_alu}} & rs2_fwded;
wire [`XWIDTH-1:0] alu_imm = dec_imm_r_ex;
// wire [`XWIDTH-1:0] alu_imm = {`XWIDTH{req_disp_alu}} & dec_imm_r_ex;
// alu的imm不需要立即数隔离，因为它只是adder的输入，在非alu req时mux会选rs2，而rs2已经过立即数隔离。因此可以省下立即数隔离所需的门。
// alu的pc也不需要立即数隔离，因为它只是adder的输入，在非alu req时mux会选rs1，而rs1已经过立即数隔离。

wire [`XWIDTH-1:0] lsu_rs1 = {`XWIDTH{req_disp_lsu}} & rs1_fwded;
wire [`XWIDTH-1:0] lsu_rs2 = {`XWIDTH{req_disp_lsu}} & rs2_fwded;
wire [`XWIDTH-1:0] lsu_imm = {`XWIDTH{req_disp_lsu}} & dec_imm_r_ex;

wire [`XWIDTH-1:0] bru_rs1 = {`XWIDTH{req_disp_bru}} & rs1_fwded;
wire [`XWIDTH-1:0] bru_rs2 = {`XWIDTH{req_disp_bru}} & rs2_fwded;
wire [`XWIDTH-1:0] bru_imm = {`XWIDTH{req_disp_bru}} & dec_imm_r_ex;
wire [`XWIDTH-1:0] bru_pc = {`XWIDTH{req_disp_bru}} & r_pc_exu;


// ---- results wrbk
wire [31:0] alu_wrbk_data;
wire [31:0] bru_wrbk_data;
// wire [31:0] lsu_req_result;
assign o_wrbk_data_exu = ({`XWIDTH{req_disp_alu}} & alu_wrbk_data)
                      | ({`XWIDTH{req_disp_bru}} & bru_wrbk_data);
                    //   | ({`XWIDTH{req_disp_lsu}} & lsu_req_result);


// ----------------        Instantiations        ---------------- //

// // ---- op1 and op2
// wire [31:0] alu_req_op1, alu_req_op2;
// assign alu_req_op1 = (dec_info_bus_alu[`DECINFO_ALU_OP1PC]) ? r_pc_exu : rf_rs1_r_ex;
// assign alu_req_op2 = (dec_info_bus_alu[`DECINFO_ALU_OP2IMM]) ? dec_imm_r_ex : rf_rs2_r_ex;
exu_alu u_exu_alu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_alu_rs1          (alu_rs1            ),
    .i_alu_rs2          (alu_rs2            ),
    .i_alu_imm          (alu_imm            ),
    .i_alu_pc           (r_pc_exu           ),
    .i_dec_info_bus_alu (dec_info_bus_alu   ),
    .o_alu_wrbk_res     (alu_wrbk_data      )
    );


exu_lsu u_exu_lsu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_lsu_rs1          (lsu_rs1            ),
    .i_lsu_rs2          (lsu_rs2            ),
    .i_lsu_imm          (lsu_imm            ),
    .i_dec_info_bus_lsu (dec_info_bus_lsu   ),
    .o_mema_addr_exu    (o_mema_addr_exu    ),
    .o_mema_wr_data_exu (o_mema_wr_data_exu ),
    .o_mema_wren_exu    (o_mema_wren_exu    ),
    .o_mema_wr_mask     (o_mema_wr_mask     ),
    .o_mema_ld_info     (o_mema_ld_info     )  // {lsu_req_info_size, lsu_req_info_usign}
    // .i_mema_rd_data     (i_mema_rd_data     ),
    // .o_lsu_req_result   (lsu_req_result     )
    );

exu_bru u_exu_bru(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_bru_rs1          (bru_rs1            ),
    .i_bru_rs2          (bru_rs2            ),
    .i_bru_imm          (bru_imm            ),
    .i_bru_pc           (bru_pc             ),
    .i_dec_info_bus_bru (dec_info_bus_bru   ),
    .o_bru_wrbk_data    (bru_wrbk_data      ),
    .o_pc_next_bru      (o_pc_next_bru      ),
    .o_jump_flag        (o_jump_flag        )
    );



endmodule
