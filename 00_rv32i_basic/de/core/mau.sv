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
    input  wire [31:0] i_mema_addr_exu,
    input  wire i_mema_wren_exu,
    input  wire [31:0] i_mema_wr_data_exu,
    input  wire [7:0] i_mema_info_bus, // {store_mask, lsu_req_load, mau_req_size, mau_req_usign}
    output wire [31:0] o_mema_addr_mau,
    output wire o_mema_wren_mau,
    output wire [3:0] o_mema_wr_mask,
    output wire [31:0] o_mema_wr_data_mau,
    input  wire [31:0] i_mema_rd_data_mau,
    // pass by
    input  wire [31:0] i_wrbk_data_exu,
    input  wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_exu,
    input  wire i_wrbk_rdwen_exu,
    output wire [31:0] o_wrbk_data_mau,
    output wire [`RFIDX_WIDTH-1:0] o_wrbk_rdidx_mau,
    output wire o_wrbk_rdwen_mau
    );


// ----------------        pipe regs        ---------------- //
reg [31:0] r_mema_addr_mau;
reg r_mema_wren_mau;
reg [31:0] r_mema_wr_data_mau;
reg [7:0] r_mema_info_bus;
// pass by
reg [31:0] r_wrbk_data_exu_d1;  // wrbk data may load from mem
reg [`RFIDX_WIDTH-1:0] r_wrbk_rdidx_mau;
reg r_wrbk_rdwen_mau;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mema_addr_mau <= 32'd0;
    end
    else begin
        r_mema_addr_mau <= i_mema_addr_exu;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mema_wren_mau <= 1'd0;
    end
    else begin
        r_mema_wren_mau <= i_mema_wren_exu;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mema_wr_data_mau <= 32'd0;
    end
    else begin
        r_mema_wr_data_mau <= i_mema_wr_data_exu;
    end
end

// pass by
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_data_exu_d1 <= 32'd0;
    end
    else begin
        r_wrbk_data_exu_d1 <= i_wrbk_data_exu;
    end
end


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdidx_mau <= {`RFIDX_WIDTH{1'b0}};
    end
    else begin
        r_wrbk_rdidx_mau <= i_wrbk_rdidx_exu;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdwen_mau <= 1'd0;
    end
    else begin
        r_wrbk_rdwen_mau <= i_wrbk_rdwen_exu;
    end
end

assign o_mema_addr_mau = r_mema_addr_mau;
assign o_mema_wren_mau = r_mema_wren_mau;
assign o_mema_wr_data_mau = r_mema_wr_data_mau;
// pass by
assign o_wrbk_data_mau = mau_req_load ? mau_load_data : r_wrbk_data_exu_d1; // wrbk data may load from mem
assign o_wrbk_rdidx_mau = r_wrbk_rdidx_mau;
assign o_wrbk_rdwen_mau = r_wrbk_rdwen_mau;



// ----------------        mau logic        ---------------- //

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mema_info_bus <= 4'd0;
    end
    else begin
        r_mema_info_bus <= i_mema_info_bus;
    end
end

wire mau_req_load;
wire [1:0] mau_req_size; // w, h, b
wire mau_req_usign;

assign o_mema_wr_mask = r_mema_info_bus[7:4];
assign mau_req_load = r_mema_info_bus[3];
assign mau_req_size = r_mema_info_bus[2:1];
assign mau_req_usign = r_mema_info_bus[0];



wire [31:0] mau_load_data;

// assign mau_load_data[7:0] = i_mema_rd_data_mau[7:0];
// assign mau_load_data[15:8] = (mau_req_size != 2'b00) ?               i_mema_rd_data_mau[15:8] 
//                              : (~mau_req_usign & i_mema_rd_data_mau[7]) ?  8'd255 : 8'b0;
// assign mau_load_data[31:16] = (mau_req_size[1]) ? i_mema_rd_data_mau[31:16] 
//                               : ((~mau_req_usign) & (((mau_req_size[0]) & i_mema_rd_data_mau[15]) | ((~mau_req_size[0]) & i_mema_rd_data_mau[7]))) ? 16'b11111111_11111111 : 16'b0;

wire [1:0] mau_addr_offset = r_mema_addr_mau[1:0];
wire [7:0]  mau_lb_data = (mau_addr_offset == 2'b00) ? i_mema_rd_data_mau[7:0] :
                          (mau_addr_offset == 2'b01) ? i_mema_rd_data_mau[15:8] :
                          (mau_addr_offset == 2'b10) ? i_mema_rd_data_mau[23:16] :
                                                       i_mema_rd_data_mau[31:24];
wire [15:0] mau_lh_data = mau_addr_offset[1] ? i_mema_rd_data_mau[31:16] : i_mema_rd_data_mau[15:0];

assign mau_load_data = (mau_req_size == 2'b10) ? i_mema_rd_data_mau : 
                       (mau_req_size == 2'b01) ? (mau_req_usign ? {16'b0, mau_lh_data} : {{16{mau_lh_data[15]}}, mau_lh_data}) : 
                       (mau_req_size == 2'b00) ? (mau_req_usign ? {24'b0, mau_lb_data} : {{24{mau_lb_data[7]}}, mau_lb_data}) : 
                       32'b0;



endmodule
