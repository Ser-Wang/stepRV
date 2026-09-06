`timescale 1ns / 1ps
`include "config.v"

module mau(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_ex_ma_vld,
    output wire        o_ex_ma_rdy,
    output wire        o_ma_wb_vld,
    input  wire        i_ma_wb_rdy,
    // EX already holds this payload while valid and not ready. MAU must not
    // insert another ingress stage at the existing EX/MA pipeline boundary.
    input  wire [31:0] i_mem_addr_exu,
    input  wire [31:0] i_mem_wr_data_exu,
    input  wire        i_mem_wr_en_exu,
    input  wire [ 3:0] i_mem_wr_mask_exu,
    input  wire [ 3:0] i_mem_req_info_bus,
    // MAU-owned memory request/response
    output wire        o_mem_req_vld,
    input  wire        i_mem_req_rdy,
    output wire [31:0] o_mem_addr,
    output wire        o_mem_req_load,
    output wire        o_mem_wr_en,
    output wire [ 1:0] o_mem_size,
    output wire [ 3:0] o_mem_wr_mask,
    output wire [31:0] o_mem_wr_data,
    input  wire        i_mem_rsp_vld,
    output wire        o_mem_rsp_rdy,
    input  wire [31:0] i_mem_rsp_data,
    // Non-memory pass-through and WB metadata
    input  wire [31:0] i_wb_data_exu,
    input  wire [`RFIDX_WIDTH-1:0] i_wb_rd_idx_exu,
    input  wire        i_wb_rd_wen_exu,
    output wire [31:0] o_wb_data_mau,
    output wire [31:0] o_fwd_data_mau,
    output wire [`RFIDX_WIDTH-1:0] o_wb_rd_idx_mau,
    output wire        o_wb_rd_wen_mau
);

// One request that has fired but whose response has not fired.
reg        outstanding_r;
reg [31:0] r_txn_mem_addr;
reg        r_txn_mem_is_load;
reg [ 1:0] r_txn_mem_size;
reg        r_txn_mem_unsigned;
reg [31:0] r_txn_wb_data;
reg [`RFIDX_WIDTH-1:0] r_txn_wb_rd_idx;
reg        r_txn_wb_rd_wen;

// Existing MA/WB holding capacity. A new completion may replace the payload
// that WBU consumes on the same edge.
reg        r_completion_vld;
reg [31:0] r_completion_data;
reg [`RFIDX_WIDTH-1:0] r_completion_rd_idx;
reg        r_completion_rd_wen;

wire input_mem_is_load = i_mem_req_info_bus[3];
wire input_mem_is_store = i_mem_wr_en_exu;
wire input_is_mem = input_mem_is_load | input_mem_is_store;

wire ma_wb_fire = o_ma_wb_vld & i_ma_wb_rdy;
wire completion_can_push = !r_completion_vld | ma_wb_fire;

assign o_mem_rsp_rdy = outstanding_r & completion_can_push;
wire mem_rsp_fire = i_mem_rsp_vld & o_mem_rsp_rdy;
wire outstanding_can_replace = !outstanding_r | mem_rsp_fire;

// Request directly from the existing EX holding. Valid is independent of
// request ready. Response A and request B may replace on the same edge.
assign o_mem_req_vld = i_ex_ma_vld & input_is_mem
                     & outstanding_can_replace;
assign o_mem_addr = i_mem_addr_exu;
assign o_mem_req_load = input_mem_is_load;
assign o_mem_wr_en = input_mem_is_store;
assign o_mem_size = i_mem_req_info_bus[2:1];
assign o_mem_wr_mask = i_mem_wr_mask_exu;
assign o_mem_wr_data = i_mem_wr_data_exu;

wire mem_req_fire = o_mem_req_vld & i_mem_req_rdy;
wire nonmem_advance = i_ex_ma_vld & !input_is_mem
                    & !outstanding_r & completion_can_push;
wire completion_push = mem_rsp_fire | nonmem_advance;

// A memory instruction transfers exactly when its request fires. A non-memory
// instruction transfers directly into MA/WB, preserving the original
// five-stage latency and MA forwarding window.
assign o_ex_ma_rdy = input_is_mem
                   ? (outstanding_can_replace & i_mem_req_rdy)
                   : (!outstanding_r & completion_can_push);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        outstanding_r <= 1'b0;
        r_txn_mem_addr <= `ZERO_WORD;
        r_txn_mem_is_load <= 1'b0;
        r_txn_mem_size <= 2'b00;
        r_txn_mem_unsigned <= 1'b0;
        r_txn_wb_data <= `ZERO_WORD;
        r_txn_wb_rd_idx <= {`RFIDX_WIDTH{1'b0}};
        r_txn_wb_rd_wen <= 1'b0;
    end else begin
        case ({mem_req_fire, mem_rsp_fire})
            2'b10: outstanding_r <= 1'b1;
            2'b01: outstanding_r <= 1'b0;
            2'b11: outstanding_r <= 1'b1;
            default: outstanding_r <= outstanding_r;
        endcase

        // Response A uses the old registers while request B atomically installs
        // the metadata for the next response through nonblocking assignments.
        if (mem_req_fire) begin
            r_txn_mem_addr <= i_mem_addr_exu;
            r_txn_mem_is_load <= input_mem_is_load;
            r_txn_mem_size <= i_mem_req_info_bus[2:1];
            r_txn_mem_unsigned <= i_mem_req_info_bus[0];
            r_txn_wb_data <= i_wb_data_exu;
            r_txn_wb_rd_idx <= i_wb_rd_idx_exu;
            r_txn_wb_rd_wen <= i_wb_rd_wen_exu;
        end
    end
end

wire [1:0] load_addr_offset = r_txn_mem_addr[1:0];
wire [7:0] load_byte = (load_addr_offset == 2'b00) ? i_mem_rsp_data[7:0]
                     : (load_addr_offset == 2'b01) ? i_mem_rsp_data[15:8]
                     : (load_addr_offset == 2'b10) ? i_mem_rsp_data[23:16]
                                                   : i_mem_rsp_data[31:24];
wire [15:0] load_half = load_addr_offset[1]
                      ? i_mem_rsp_data[31:16] : i_mem_rsp_data[15:0];
wire [31:0] load_data = (r_txn_mem_size == 2'b10) ? i_mem_rsp_data
                      : (r_txn_mem_size == 2'b01)
                        ? (r_txn_mem_unsigned ? {16'b0, load_half}
                                          : {{16{load_half[15]}}, load_half})
                      : (r_txn_mem_size == 2'b00)
                        ? (r_txn_mem_unsigned ? {24'b0, load_byte}
                                          : {{24{load_byte[7]}}, load_byte})
                      : `ZERO_WORD;

wire [31:0] response_result = r_txn_mem_is_load
                            ? load_data : r_txn_wb_data;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_completion_vld <= 1'b0;
        r_completion_data <= `ZERO_WORD;
        r_completion_rd_idx <= {`RFIDX_WIDTH{1'b0}};
        r_completion_rd_wen <= 1'b0;
    end else begin
        case ({completion_push, ma_wb_fire})
            2'b10: r_completion_vld <= 1'b1;
            2'b01: r_completion_vld <= 1'b0;
            2'b11: r_completion_vld <= 1'b1;
            default: r_completion_vld <= r_completion_vld;
        endcase

        if (mem_rsp_fire) begin
            r_completion_data <= response_result;
            r_completion_rd_idx <= r_txn_wb_rd_idx;
            r_completion_rd_wen <= r_txn_wb_rd_wen;
        end else if (nonmem_advance) begin
            r_completion_data <= i_wb_data_exu;
            r_completion_rd_idx <= i_wb_rd_idx_exu;
            r_completion_rd_wen <= i_wb_rd_wen_exu;
        end
    end
end

assign o_ma_wb_vld = r_completion_vld;
assign o_wb_data_mau = r_completion_data;
assign o_fwd_data_mau = r_completion_data;
assign o_wb_rd_idx_mau = r_completion_rd_idx;
assign o_wb_rd_wen_mau = r_completion_vld & r_completion_rd_wen;

endmodule
