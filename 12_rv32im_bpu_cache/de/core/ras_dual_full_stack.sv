`timescale 1ns / 1ps
`include "config.v"

module ras_dual_full_stack #(
    parameter integer ENTRIES = `BPU_RAS_ENTRIES
)(
    input  wire        clk,
    input  wire        rst_n,

    output wire        o_top_vld,
    output wire [31:0] o_top_addr,

    input  wire        i_pred_update_fire,
    input  wire        i_pred_pop,
    input  wire        i_pred_push,
    input  wire [31:0] i_pred_push_addr,

    input  wire        i_resolve_fire,
    input  wire        i_resolve_pop,
    input  wire        i_resolve_push,
    input  wire [31:0] i_resolve_push_addr,

    input  wire        i_recover
);

localparam integer COUNT_WIDTH = $clog2(ENTRIES + 1);

reg [31:0] pred_entries [0:ENTRIES-1];
reg [31:0] resolved_entries [0:ENTRIES-1];
reg [COUNT_WIDTH-1:0] pred_count;
reg [COUNT_WIDTH-1:0] resolved_count;

reg [31:0] pred_entries_next [0:ENTRIES-1];
reg [31:0] resolved_entries_next [0:ENTRIES-1];
reg [COUNT_WIDTH-1:0] pred_count_next;
reg [COUNT_WIDTH-1:0] resolved_count_next;

wire ras_enable = (`BPU_ENABLE != 0) && (`BPU_RAS_ENABLE != 0);

assign o_top_vld = ras_enable && (pred_count != {COUNT_WIDTH{1'b0}});
assign o_top_addr = o_top_vld ? pred_entries[0] : 32'b0;

integer comb_idx;
always @(*) begin
    pred_count_next = pred_count;
    resolved_count_next = resolved_count;
    for (comb_idx = 0; comb_idx < ENTRIES; comb_idx = comb_idx + 1) begin
        pred_entries_next[comb_idx] = pred_entries[comb_idx];
        resolved_entries_next[comb_idx] = resolved_entries[comb_idx];
    end

    if (ras_enable && i_pred_update_fire) begin
        case ({i_pred_pop, i_pred_push})
            2'b01: begin
                for (comb_idx = ENTRIES - 1; comb_idx > 0; comb_idx = comb_idx - 1)
                    pred_entries_next[comb_idx] = pred_entries[comb_idx-1];
                pred_entries_next[0] = i_pred_push_addr;
                if (pred_count < ENTRIES)
                    pred_count_next = pred_count + {{COUNT_WIDTH-1{1'b0}}, 1'b1};
            end
            2'b10: begin
                if (pred_count != 0) begin
                    for (comb_idx = 0; comb_idx < ENTRIES - 1; comb_idx = comb_idx + 1)
                        pred_entries_next[comb_idx] = pred_entries[comb_idx+1];
                    pred_entries_next[ENTRIES-1] = 32'b0;
                    pred_count_next = pred_count - {{COUNT_WIDTH-1{1'b0}}, 1'b1};
                end
            end
            2'b11: begin
                pred_entries_next[0] = i_pred_push_addr;
                if (pred_count == 0)
                    pred_count_next = {{COUNT_WIDTH-1{1'b0}}, 1'b1};
            end
            default: begin
            end
        endcase
    end

    if (ras_enable && i_resolve_fire) begin
        case ({i_resolve_pop, i_resolve_push})
            2'b01: begin
                for (comb_idx = ENTRIES - 1; comb_idx > 0; comb_idx = comb_idx - 1)
                    resolved_entries_next[comb_idx] = resolved_entries[comb_idx-1];
                resolved_entries_next[0] = i_resolve_push_addr;
                if (resolved_count < ENTRIES)
                    resolved_count_next = resolved_count + {{COUNT_WIDTH-1{1'b0}}, 1'b1};
            end
            2'b10: begin
                if (resolved_count != 0) begin
                    for (comb_idx = 0; comb_idx < ENTRIES - 1; comb_idx = comb_idx + 1)
                        resolved_entries_next[comb_idx] = resolved_entries[comb_idx+1];
                    resolved_entries_next[ENTRIES-1] = 32'b0;
                    resolved_count_next = resolved_count - {{COUNT_WIDTH-1{1'b0}}, 1'b1};
                end
            end
            2'b11: begin
                resolved_entries_next[0] = i_resolve_push_addr;
                if (resolved_count == 0)
                    resolved_count_next = {{COUNT_WIDTH-1{1'b0}}, 1'b1};
            end
            default: begin
            end
        endcase
    end
end

integer seq_idx;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pred_count <= {COUNT_WIDTH{1'b0}};
        resolved_count <= {COUNT_WIDTH{1'b0}};
        for (seq_idx = 0; seq_idx < ENTRIES; seq_idx = seq_idx + 1) begin
            pred_entries[seq_idx] <= 32'b0;
            resolved_entries[seq_idx] <= 32'b0;
        end
    end
    else if (ras_enable) begin
        resolved_count <= resolved_count_next;
        for (seq_idx = 0; seq_idx < ENTRIES; seq_idx = seq_idx + 1)
            resolved_entries[seq_idx] <= resolved_entries_next[seq_idx];

        if (i_recover) begin
            pred_count <= resolved_count_next;
            for (seq_idx = 0; seq_idx < ENTRIES; seq_idx = seq_idx + 1)
                pred_entries[seq_idx] <= resolved_entries_next[seq_idx];
        end
        else begin
            pred_count <= pred_count_next;
            for (seq_idx = 0; seq_idx < ENTRIES; seq_idx = seq_idx + 1)
                pred_entries[seq_idx] <= pred_entries_next[seq_idx];
        end
    end
end

`ifndef SYNTHESIS
initial begin
    if (ENTRIES < 2)
        $error("BPU_RAS_ENTRIES must be at least 2");
end
`endif

endmodule
