`timescale 1ns / 1ps
`include "config.v"

module branch_predictor #(
    parameter integer BTB_ENTRIES = `BPU_BTB_ENTRIES,
    parameter integer BHT_ENTRIES = `BPU_BHT_ENTRIES
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] i_query_pc,
    output wire [31:0] o_pred_next_pc,
    output wire        o_btb_hit,
    output wire        o_pred_taken,
    input  wire        i_update_vld,
    input  wire [31:0] i_update_pc,
    input  wire        i_update_is_cond,
    input  wire        i_update_taken,
    input  wire [31:0] i_update_target,
    input  wire        i_invalidate
);

localparam integer BTB_INDEX_WIDTH = $clog2(BTB_ENTRIES);
localparam integer BHT_INDEX_WIDTH = $clog2(BHT_ENTRIES);
localparam integer BTB_TAG_WIDTH = 32 - 2 - BTB_INDEX_WIDTH;

reg                     btb_valid [0:BTB_ENTRIES-1];
reg [BTB_TAG_WIDTH-1:0] btb_tag [0:BTB_ENTRIES-1];
reg [31:0]              btb_target [0:BTB_ENTRIES-1];
reg                     btb_is_conditional [0:BTB_ENTRIES-1];
reg [1:0]               bht_counter [0:BHT_ENTRIES-1];

wire [BTB_INDEX_WIDTH-1:0] query_btb_index =
    i_query_pc[2 + BTB_INDEX_WIDTH - 1:2];
wire [BHT_INDEX_WIDTH-1:0] query_bht_index =
    i_query_pc[2 + BHT_INDEX_WIDTH - 1:2];
wire [BTB_TAG_WIDTH-1:0] query_btb_tag =
    i_query_pc[31:2 + BTB_INDEX_WIDTH];

wire [BTB_INDEX_WIDTH-1:0] update_btb_index =
    i_update_pc[2 + BTB_INDEX_WIDTH - 1:2];
wire [BHT_INDEX_WIDTH-1:0] update_bht_index =
    i_update_pc[2 + BHT_INDEX_WIDTH - 1:2];
wire [BTB_TAG_WIDTH-1:0] update_btb_tag =
    i_update_pc[31:2 + BTB_INDEX_WIDTH];

wire btb_hit_raw = btb_valid[query_btb_index]
                 && (btb_tag[query_btb_index] == query_btb_tag);
wire direction_taken = bht_counter[query_bht_index][1];
wire pred_taken_raw = btb_hit_raw
                    && (!btb_is_conditional[query_btb_index] || direction_taken);

assign o_btb_hit = `BPU_ENABLE ? btb_hit_raw : 1'b0;
assign o_pred_taken = `BPU_ENABLE ? pred_taken_raw : 1'b0;
assign o_pred_next_pc = o_pred_taken ? btb_target[query_btb_index]
                                     : (i_query_pc + 32'd4);

integer idx;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (idx = 0; idx < BTB_ENTRIES; idx = idx + 1) begin
            btb_valid[idx] <= 1'b0;
            btb_tag[idx] <= {BTB_TAG_WIDTH{1'b0}};
            btb_target[idx] <= 32'b0;
            btb_is_conditional[idx] <= 1'b0;
        end
        for (idx = 0; idx < BHT_ENTRIES; idx = idx + 1) begin
            bht_counter[idx] <= `BPU_BHT_INIT;
        end
    end
    else if (`BPU_ENABLE && i_invalidate) begin
        for (idx = 0; idx < BTB_ENTRIES; idx = idx + 1) begin
            btb_valid[idx] <= 1'b0;
        end
        for (idx = 0; idx < BHT_ENTRIES; idx = idx + 1) begin
            bht_counter[idx] <= `BPU_BHT_INIT;
        end
    end
    else if (`BPU_ENABLE && i_update_vld) begin
        btb_valid[update_btb_index] <= 1'b1;
        btb_tag[update_btb_index] <= update_btb_tag;
        btb_target[update_btb_index] <= i_update_target;
        btb_is_conditional[update_btb_index] <= i_update_is_cond;

        if (i_update_is_cond) begin
            if (i_update_taken) begin
                if (bht_counter[update_bht_index] != 2'b11)
                    bht_counter[update_bht_index] <= bht_counter[update_bht_index] + 2'b01;
            end
            else begin
                if (bht_counter[update_bht_index] != 2'b00)
                    bht_counter[update_bht_index] <= bht_counter[update_bht_index] - 2'b01;
            end
        end
    end
end

`ifndef SYNTHESIS
initial begin
    if ((BTB_ENTRIES < 2) || ((BTB_ENTRIES & (BTB_ENTRIES - 1)) != 0))
        $error("BPU_BTB_ENTRIES must be a power of two and at least 2");
    if ((BHT_ENTRIES < 2) || ((BHT_ENTRIES & (BHT_ENTRIES - 1)) != 0))
        $error("BPU_BHT_ENTRIES must be a power of two and at least 2");
end
`endif

endmodule
