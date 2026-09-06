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
wire        fetch_req_rdy;
wire        if_rsp_vld;
wire        if_rsp_rdy;
wire [31:0] if_rsp_data;

wire        imem_req_vld;
wire        imem_req_rdy;
wire [31:0] imem_req_addr;
wire        imem_rsp_vld;
wire        imem_rsp_rdy;
wire [31:0] imem_rsp_data;

wire mem_req_vld;
wire mem_req_rdy;
wire [31:0] mem_addr;
wire mem_req_load;
wire mem_wr_en;
wire [1:0] mem_size;
wire [3:0] mem_wr_mask;
wire [31:0] mem_wr_data;
wire mem_rsp_vld;
wire mem_rsp_rdy;
wire [31:0] mem_rd_data;

core u_core(
    .clk            (clk    ),
    .rst_n          (rst_n  ),
    // if
    .o_fetch_req    (fetch_req      ),
    .o_fetch_pc     (fetch_pc       ),
    .i_fetch_req_rdy(fetch_req_rdy  ),
    .i_if_rsp_vld   (if_rsp_vld     ),
    .o_if_rsp_rdy   (if_rsp_rdy     ),
    .i_if_instr     (if_rsp_data    ),
    // mem access
    .o_mem_req_vld  (mem_req_vld   ),
    .i_mem_req_rdy  (mem_req_rdy   ),
    .o_mem_addr     (mem_addr       ),
    .o_mem_req_load (mem_req_load   ),
    .o_mem_wr_en    (mem_wr_en      ),
    .o_mem_size     (mem_size       ),
    .o_mem_wr_mask  (mem_wr_mask    ),
    .o_mem_wr_data  (mem_wr_data    ),
    .i_mem_rsp_vld  (mem_rsp_vld   ),
    .o_mem_rsp_rdy  (mem_rsp_rdy   ),
    .i_mem_rd_data  (mem_rd_data    )
    );


wire        imem_p1_en;
wire        imem_p1_we;
wire [31:0] imem_p1_addr;
wire [ 3:0] imem_p1_wmask;
wire [31:0] imem_p1_wdata;
wire [31:0] imem_p1_rdata;

wire        dcache_req_vld;
wire        dcache_req_rdy;
wire [31:0] dcache_req_addr;
wire        dcache_req_load;
wire        dcache_req_write;
wire [ 3:0] dcache_req_wmask;
wire [31:0] dcache_req_wdata;
wire        dcache_rsp_vld;
wire        dcache_rsp_rdy;
wire [31:0] dcache_rsp_data;

wire        dmem_req_vld;
wire        dmem_req_rdy;
wire [31:0] dmem_req_addr;
wire        dmem_req_write;
wire [ 3:0] dmem_req_wmask;
wire [31:0] dmem_req_wdata;
wire        dmem_rsp_vld;
wire        dmem_rsp_rdy;
wire [31:0] dmem_rsp_data;

wire [31:0] uart_addr;
wire        uart_wr_en;
wire [31:0] uart_wr_data;
wire [31:0] uart_rd_data;

// Memory Bus & Arbitration
soc_bus u_soc_bus (
    .clk            (clk          ),
    .rst_n          (rst_n        ),
    // Core interface
    .i_mem_req_vld  (mem_req_vld ),
    .o_mem_req_rdy  (mem_req_rdy ),
    .i_mem_addr     (mem_addr     ),
    .i_mem_req_load (mem_req_load ),
    .i_mem_wr_en    (mem_wr_en    ),
    .i_mem_size     (mem_size     ),
    .i_mem_wr_mask  (mem_wr_mask  ),
    .i_mem_wr_data  (mem_wr_data  ),
    .o_mem_rsp_vld  (mem_rsp_vld ),
    .i_mem_rsp_rdy  (mem_rsp_rdy ),
    .o_mem_rd_data  (mem_rd_data  ),

    // Cacheable DMEM interface
    .o_dcache_req_vld  (dcache_req_vld  ),
    .i_dcache_req_rdy  (dcache_req_rdy  ),
    .o_dcache_req_addr (dcache_req_addr ),
    .o_dcache_req_load (dcache_req_load ),
    .o_dcache_req_write(dcache_req_write),
    .o_dcache_req_wmask(dcache_req_wmask),
    .o_dcache_req_wdata(dcache_req_wdata),
    .i_dcache_rsp_vld  (dcache_rsp_vld  ),
    .o_dcache_rsp_rdy  (dcache_rsp_rdy  ),
    .i_dcache_rsp_data (dcache_rsp_data ),

    // Uncached executable IMEM data interface
    .o_imem_p1_en   (imem_p1_en   ),
    .o_imem_p1_we   (imem_p1_we   ),
    .o_imem_p1_addr (imem_p1_addr ),
    .o_imem_p1_wmask(imem_p1_wmask),
    .o_imem_p1_wdata(imem_p1_wdata),
    .i_imem_p1_rdata(imem_p1_rdata),

    // UART interface
    .o_uart_addr    (uart_addr    ),
    .o_uart_wr_en   (uart_wr_en   ),
    .o_uart_wr_data (uart_wr_data ),
    .i_uart_rd_data (uart_rd_data )
);

icache u_icache (
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    .i_cpu_req_vld      (fetch_req      ),
    .o_cpu_req_rdy      (fetch_req_rdy  ),
    .i_cpu_req_addr     (fetch_pc       ),
    .o_cpu_rsp_vld      (if_rsp_vld     ),
    .i_cpu_rsp_rdy      (if_rsp_rdy     ),
    .o_cpu_rsp_data     (if_rsp_data    ),
    .o_mem_req_vld      (imem_req_vld   ),
    .i_mem_req_rdy      (imem_req_rdy   ),
    .o_mem_req_addr     (imem_req_addr  ),
    .i_mem_rsp_vld      (imem_rsp_vld   ),
    .o_mem_rsp_rdy      (imem_rsp_rdy   ),
    .i_mem_rsp_data     (imem_rsp_data  )
    );

backing_imem u_backing_imem (
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    // I-Cache refill transaction
    .i_p0_req_vld       (imem_req_vld   ),
    .o_p0_req_rdy       (imem_req_rdy   ),
    .i_p0_req_addr      (imem_req_addr  ),
    .o_p0_rsp_vld       (imem_rsp_vld   ),
    .i_p0_rsp_rdy       (imem_rsp_rdy   ),
    .o_p0_rsp_data      (imem_rsp_data  ),
    // Data Write (Self-modifying support)
    .i_p1_en            (imem_p1_en     ),
    .i_p1_we            (imem_p1_we     ),
    .i_p1_addr          (imem_p1_addr   ),
    .i_p1_wmask         (imem_p1_wmask  ),
    .i_p1_wdata         (imem_p1_wdata  ),
    .o_p1_rdata         (imem_p1_rdata  )
    );

dcache u_dcache (
    .clk                (clk               ),
    .rst_n              (rst_n             ),
    .i_cpu_req_vld      (dcache_req_vld    ),
    .o_cpu_req_rdy      (dcache_req_rdy    ),
    .i_cpu_req_addr     (dcache_req_addr   ),
    .i_cpu_req_load     (dcache_req_load   ),
    .i_cpu_req_write    (dcache_req_write  ),
    .i_cpu_req_wmask    (dcache_req_wmask  ),
    .i_cpu_req_wdata    (dcache_req_wdata  ),
    .o_cpu_rsp_vld      (dcache_rsp_vld    ),
    .i_cpu_rsp_rdy      (dcache_rsp_rdy    ),
    .o_cpu_rsp_data     (dcache_rsp_data   ),
    .o_mem_req_vld      (dmem_req_vld      ),
    .i_mem_req_rdy      (dmem_req_rdy      ),
    .o_mem_req_addr     (dmem_req_addr     ),
    .o_mem_req_write    (dmem_req_write    ),
    .o_mem_req_wmask    (dmem_req_wmask    ),
    .o_mem_req_wdata    (dmem_req_wdata    ),
    .i_mem_rsp_vld      (dmem_rsp_vld      ),
    .o_mem_rsp_rdy      (dmem_rsp_rdy      ),
    .i_mem_rsp_data     (dmem_rsp_data     )
    );

backing_dmem u_backing_dmem (
    .clk                (clk               ),
    .rst_n              (rst_n             ),
    .i_req_vld          (dmem_req_vld      ),
    .o_req_rdy          (dmem_req_rdy      ),
    .i_req_addr         (dmem_req_addr     ),
    .i_req_write        (dmem_req_write    ),
    .i_req_wmask        (dmem_req_wmask    ),
    .i_req_wdata        (dmem_req_wdata    ),
    .o_rsp_vld          (dmem_rsp_vld      ),
    .i_rsp_rdy          (dmem_rsp_rdy      ),
    .o_rsp_data         (dmem_rsp_data     )
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
