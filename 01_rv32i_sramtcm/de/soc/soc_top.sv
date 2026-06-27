`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/22
// Design Name: StepRV_v0
// Module Name: soc_top
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module soc_top(
    input wire clk,
    input wire rst_n,
    output wire o_uart_tx,
    input wire i_uart_rx
    );

wire        fetch_req;
wire [31:0] fetch_pc;

wire [31:0] itcm_rd_data;

wire [31:0] mem_addr;
wire mem_req_load;
wire mem_wr_en;
wire [3:0] mem_wr_mask;
wire [31:0] mem_wr_data;
wire [31:0] mem_rd_data;

core u_core(
    .clk            (clk    ),
    .rst_n          (rst_n  ),
    // if
    .o_fetch_req    (fetch_req      ),
    .o_fetch_pc     (fetch_pc       ),
    .i_if_instr     (itcm_rd_data   ),
    // mem access
    .o_mem_addr     (mem_addr       ),
    .o_mem_req_load (mem_req_load   ),
    .o_mem_wr_en    (mem_wr_en      ),
    .o_mem_wr_mask  (mem_wr_mask    ),
    .o_mem_wr_data  (mem_wr_data    ),
    .i_mem_rd_data  (mem_rd_data    )
    );


wire        itcm_p1_en;
wire        itcm_p1_we;
wire [31:0] itcm_p1_addr;
wire [ 3:0] itcm_p1_wmask;
wire [31:0] itcm_p1_wdata;
wire [31:0] itcm_p1_rdata;

wire [31:0] dtcm_addr;
wire        dtcm_wr_en;
wire [ 3:0] dtcm_wr_mask;
wire [31:0] dtcm_wr_data;
wire [31:0] dtcm_rd_data;

wire [31:0] uart_addr;
wire        uart_wr_en;
wire [31:0] uart_wr_data;
wire [31:0] uart_rd_data;

// Memory Bus & Arbitration
soc_bus u_soc_bus (
    .clk            (clk          ),
    .rst_n          (rst_n        ),
    // Core interface
    .i_mem_addr     (mem_addr     ),
    .i_mem_req_load (mem_req_load ),
    .i_mem_wr_en    (mem_wr_en    ),
    .i_mem_wr_mask  (mem_wr_mask  ),
    .i_mem_wr_data  (mem_wr_data  ),
    .o_mem_rd_data  (mem_rd_data  ),

    // ITCM interface
    .o_itcm_p1_en   (itcm_p1_en   ),
    .o_itcm_p1_we   (itcm_p1_we   ),
    .o_itcm_p1_addr (itcm_p1_addr ),
    .o_itcm_p1_wmask(itcm_p1_wmask),
    .o_itcm_p1_wdata(itcm_p1_wdata),
    .i_itcm_p1_rdata(itcm_p1_rdata),

    // DTCM interface
    .o_dtcm_addr    (dtcm_addr    ),
    .o_dtcm_wr_en   (dtcm_wr_en   ),
    .o_dtcm_wr_mask (dtcm_wr_mask ),
    .o_dtcm_wr_data (dtcm_wr_data ),
    .i_dtcm_rd_data (dtcm_rd_data ),

    // UART interface
    .o_uart_addr    (uart_addr    ),
    .o_uart_wr_en   (uart_wr_en   ),
    .o_uart_wr_data (uart_wr_data ),
    .i_uart_rd_data (uart_rd_data )
);

mem_itcm u_imem(
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    // Instruction Fetch (Read-Only)
    .i_p0_en            (fetch_req      ),
    .i_p0_addr          (fetch_pc       ),
    .o_p0_rdata         (itcm_rd_data   ),
    // Data Write (Self-modifying support)
    .i_p1_en            (itcm_p1_en     ),
    .i_p1_we            (itcm_p1_we     ),
    .i_p1_addr          (itcm_p1_addr   ),
    .i_p1_wmask         (itcm_p1_wmask  ),
    .i_p1_wdata         (itcm_p1_wdata  ),
    .o_p1_rdata         (itcm_p1_rdata  )
    );

mem_dtcm u_dmem(
    .clk        (clk            ),
    .rst_n      (rst_n          ),
    .i_addr     (dtcm_addr      ),
    .i_wr_en    (dtcm_wr_en     ),
    .i_wr_mask  (dtcm_wr_mask   ),
    .i_wr_data  (dtcm_wr_data   ),
    .o_rd_data  (dtcm_rd_data   )
    );

uart u_uart(
    .clk        (clk         ),
    .rst_n      (rst_n       ),
    .we_i       (uart_wr_en  ),
    .addr_i     (uart_addr   ),
    .data_i     (uart_wr_data),
    .data_o     (uart_rd_data),
    .tx_pin     (o_uart_tx   ),
    .rx_pin     (i_uart_rx   )
    );


// ila_0 your_instance_name (
// 	.clk(clk), // input wire clk
// 	.probe0(o_uart_tx), // input wire [0:0]  probe0  
// 	.probe1(u_core.u_exu.r_pc_exu) // input wire [7:0]  probe1
// );


endmodule
