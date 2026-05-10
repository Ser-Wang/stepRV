`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/22 17:00:00
// Design Name: 
// Module Name: soc_top_v0
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


module soc_top_v0(
    input wire clk,
    input wire rst_n
    );

wire [31:0] pc_addr_if;
wire [31:0] instr_if_data;

wire [31:0] mema_addr;
wire mema_wren;
wire [3:0] mema_wr_mask;
wire [31:0] mema_rd_data;
wire [31:0] mema_wr_data;


core_rv32i_v0 u_core(
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    // if
    .o_pc_if_addr       (pc_addr_if     ),
    .i_instr_if_data    (instr_if_data  ),
    // mem access
    .o_mema_addr        (mema_addr      ),
    .o_mema_wren        (mema_wren      ),
    .o_mema_wr_mask     (mema_wr_mask   ),
    .i_mema_rd_data     (mema_rd_data   ),
    .o_mema_wr_data     (mema_wr_data   )
    );


// Address Decoding Logic
// ITCM: 0x0000_0000 - 0x7FFF_FFFF
// DTCM: 0x8000_0000 - 0xFFFF_FFFF
wire itcm_sel = (mema_addr[31] == 1'b0);
wire dtcm_sel = (mema_addr[31] == 1'b1);

wire itcm_wr_en = mema_wren & itcm_sel;
wire dtcm_wr_en = mema_wren & dtcm_sel;

wire [31:0] itcm_data_rd_data;
wire [31:0] dtcm_rd_data;
assign mema_rd_data = itcm_sel ? itcm_data_rd_data : dtcm_rd_data;

mem_itcm u_imem(
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    // Port A: Instruction Fetch
    .i_rd_addr          (pc_addr_if     ),
    .o_rd_data          (instr_if_data  ),
    // Port B: Data Access (Self-modifying support)
    .i_wr_en            (itcm_wr_en     ),
    .i_wr_mask          (mema_wr_mask   ),
    .i_addr             (mema_addr      ),
    .i_wr_data          (mema_wr_data   ),
    .o_data_rd_data     (itcm_data_rd_data)
    );

mem_dtcm u_dmem(
    .clk        (clk            ),
    .rst_n      (rst_n          ),
    .i_wr_en    (dtcm_wr_en     ),
    .i_wr_mask  (mema_wr_mask   ),
    .i_addr     (mema_addr      ),
    .i_wr_data  (mema_wr_data   ),
    .o_rd_data  (dtcm_rd_data   )
    );


endmodule
