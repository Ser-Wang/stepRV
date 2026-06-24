`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/02/17
// Design Name: StepRV_v0
// Module Name: mau
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module mau(
    input  wire clk,
    input  wire rst_n,
    input  wire [31:0] i_mem_addr_exu,
    input  wire i_mem_wr_en_exu,
    input  wire [31:0] i_mem_wr_data_exu,
    input  wire [7:0] i_mem_req_info_bus, // {store_mask, lsu_req_load, mau_req_size, mau_req_usign}
    output wire [31:0] o_mem_addr_mau,
    output wire o_mem_wr_en_mau,
    output wire [3:0] o_mem_wr_mask,
    output wire [31:0] o_mem_wr_data_mau,
    input  wire [31:0] i_mem_rd_data_mau,
    // pass by
    input  wire [31:0] i_wb_data_exu,
    input  wire [`RFIDX_WIDTH-1:0] i_wb_rd_idx_exu,
    input  wire i_wb_rd_wen_exu,
    output wire [31:0] o_wb_data_mau,
    output wire [`RFIDX_WIDTH-1:0] o_wb_rd_idx_mau,
    output wire o_wb_rd_wen_mau
    );


reg [31:0] r_mem_addr_mau;
reg r_mem_wr_en_mau;
reg [31:0] r_mem_wr_data_mau;
reg [7:0] r_mem_req_info_bus;

reg [31:0] r_wb_data_exu_d1;  // write-back data may load from mem
reg [`RFIDX_WIDTH-1:0] r_wb_rd_idx_mau;
reg r_wb_rd_wen_mau;

wire mau_req_load;
wire [1:0] mau_req_size; // w, h, b
wire mau_req_usign;
wire [31:0] mau_load_data;

// ----------------        pipe regs        ---------------- //
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mem_addr_mau <= 32'd0;
    end
    else begin
        r_mem_addr_mau <= i_mem_addr_exu;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mem_wr_en_mau <= 1'd0;
    end
    else begin
        r_mem_wr_en_mau <= i_mem_wr_en_exu;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mem_wr_data_mau <= 32'd0;
    end
    else begin
        r_mem_wr_data_mau <= i_mem_wr_data_exu;
    end
end

// pass by
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_data_exu_d1 <= 32'd0;
    end
    else begin
        r_wb_data_exu_d1 <= i_wb_data_exu;
    end
end


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_rd_idx_mau <= {`RFIDX_WIDTH{1'b0}};
    end
    else begin
        r_wb_rd_idx_mau <= i_wb_rd_idx_exu;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_rd_wen_mau <= 1'd0;
    end
    else begin
        r_wb_rd_wen_mau <= i_wb_rd_wen_exu;
    end
end

assign o_mem_addr_mau = r_mem_addr_mau;
assign o_mem_wr_en_mau = r_mem_wr_en_mau;
assign o_mem_wr_data_mau = r_mem_wr_data_mau;
// pass by
assign o_wb_data_mau = mau_req_load ? mau_load_data : r_wb_data_exu_d1; // write-back data may load from mem
assign o_wb_rd_idx_mau = r_wb_rd_idx_mau;
assign o_wb_rd_wen_mau = r_wb_rd_wen_mau;


// ----------------        mau logic        ---------------- //

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mem_req_info_bus <= 8'd0;
    end
    else begin
        r_mem_req_info_bus <= i_mem_req_info_bus;
    end
end

assign o_mem_wr_mask = r_mem_req_info_bus[7:4];
assign mau_req_load = r_mem_req_info_bus[3];
assign mau_req_size = r_mem_req_info_bus[2:1];
assign mau_req_usign = r_mem_req_info_bus[0];


// assign mau_load_data[7:0] = i_mem_rd_data_mau[7:0];
// assign mau_load_data[15:8] = (mau_req_size != 2'b00) ?               i_mem_rd_data_mau[15:8] 
//                              : (~mau_req_usign & i_mem_rd_data_mau[7]) ?  8'd255 : 8'b0;
// assign mau_load_data[31:16] = (mau_req_size[1]) ? i_mem_rd_data_mau[31:16] 
//                               : ((~mau_req_usign) & (((mau_req_size[0]) & i_mem_rd_data_mau[15]) | ((~mau_req_size[0]) & i_mem_rd_data_mau[7]))) ? 16'b11111111_11111111 : 16'b0;

wire [1:0] mau_addr_offset = r_mem_addr_mau[1:0];
wire [7:0]  mau_lb_data = (mau_addr_offset == 2'b00) ? i_mem_rd_data_mau[7:0] :
                          (mau_addr_offset == 2'b01) ? i_mem_rd_data_mau[15:8] :
                          (mau_addr_offset == 2'b10) ? i_mem_rd_data_mau[23:16] :
                                                       i_mem_rd_data_mau[31:24];
wire [15:0] mau_lh_data = mau_addr_offset[1] ? i_mem_rd_data_mau[31:16] : i_mem_rd_data_mau[15:0];

assign mau_load_data = (mau_req_size == 2'b10) ? i_mem_rd_data_mau : 
                       (mau_req_size == 2'b01) ? (mau_req_usign ? {16'b0, mau_lh_data} : {{16{mau_lh_data[15]}}, mau_lh_data}) : 
                       (mau_req_size == 2'b00) ? (mau_req_usign ? {24'b0, mau_lb_data} : {{24{mau_lb_data[7]}}, mau_lb_data}) : 
                       32'b0;


endmodule
