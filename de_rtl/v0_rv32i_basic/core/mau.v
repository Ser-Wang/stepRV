`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/17 19:33:45
// Design Name: 
// Module Name: mau
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

module mau(
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_mema_addr_exu,
    input wire i_mema_wren_exu,
    input wire [31:0] i_mema_wr_data_exu,
    input wire [3:0] i_mema_ld_info, // {lsu_req_load, mau_req_size, mau_req_usign}
    output wire [31:0] o_mema_addr_mau,
    output wire o_mema_wren_mau,
    output wire [31:0] o_mema_wr_data_mau,
    input wire [31:0] i_mema_rd_data_mau,
    // pass by
    input wire [31:0] i_wrbk_data_ex,
    input wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_ex,
    input wire i_wrbk_rdwen_ex,
    output wire [31:0] o_wrbk_data_mema,
    output wire [`RFIDX_WIDTH-1:0] o_wrbk_rdidx_mema,
    output wire o_wrbk_rdwen_mema
    );


// ----------------        pipe regs        ---------------- //
reg [31:0] r_mema_addr_mau;
reg r_mema_wren_mau;
reg [31:0] r_mema_wr_data_mau;
reg [3:0] r_mema_ld_info;
// pass by
reg [31:0] r_wrbk_data_exu_d1;  // wrbk data may load from mem
reg [`RFIDX_WIDTH-1:0] r_wrbk_rdidx_mema;
reg r_wrbk_rdwen_mema;

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
        r_wrbk_data_exu_d1 <= i_wrbk_data_ex;
    end
end


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdidx_mema <= {`RFIDX_WIDTH{1'b0}};
    end
    else begin
        r_wrbk_rdidx_mema <= i_wrbk_rdidx_ex;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdwen_mema <= 1'd0;
    end
    else begin
        r_wrbk_rdwen_mema <= i_wrbk_rdwen_ex;
    end
end

assign o_mema_addr_mau = r_mema_addr_mau;
assign o_mema_wren_mau = r_mema_wren_mau;
assign o_mema_wr_data_mau = r_mema_wr_data_mau;
// pass by
assign o_wrbk_data_mema = mau_req_load ? mau_load_data : r_wrbk_data_exu_d1; // wrbk data may load from mem
assign o_wrbk_rdidx_mema = r_wrbk_rdidx_mema;
assign o_wrbk_rdwen_mema = r_wrbk_rdwen_mema;



// ----------------        mau logic        ---------------- //

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mema_ld_info <= 4'd0;
    end
    else begin
        r_mema_ld_info <= i_mema_ld_info;
    end
end

wire mau_req_load;
wire [1:0] mau_req_size; // w, h, b
wire mau_req_usign;

assign mau_req_load = r_mema_ld_info[3];
assign mau_req_size = r_mema_ld_info[2:1];
assign mau_req_usign = r_mema_ld_info[0];


wire [31:0] mau_load_data;

assign mau_load_data[7:0] = i_mema_rd_data_mau[7:0];
assign mau_load_data[15:8] = (mau_req_size != 2'b00) ?               i_mema_rd_data_mau[15:8] 
                             : (~mau_req_usign & i_mema_rd_data_mau[7]) ?  8'd255 : 8'b0;
assign mau_load_data[31:16] = (mau_req_size[1]) ? i_mema_rd_data_mau[31:16] 
                              : ((~mau_req_usign) & (((mau_req_size[0]) & i_mema_rd_data_mau[15]) | ((~mau_req_size[0]) & i_mema_rd_data_mau[7]))) ? 16'b11111111_11111111 : 16'b0;
// assign o_lsu_req_result = mau_load_data;


endmodule
