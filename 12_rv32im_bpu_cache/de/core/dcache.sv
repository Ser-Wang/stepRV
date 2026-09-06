`timescale 1ns / 1ps

module dcache (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        i_cpu_req_vld,
    output wire        o_cpu_req_rdy,
    input  wire [31:0] i_cpu_req_addr,
    input  wire        i_cpu_req_load,
    input  wire        i_cpu_req_write,
    input  wire [ 3:0] i_cpu_req_wmask,
    input  wire [31:0] i_cpu_req_wdata,
    output wire        o_cpu_rsp_vld,
    input  wire        i_cpu_rsp_rdy,
    output wire [31:0] o_cpu_rsp_data,

    output wire        o_mem_req_vld,
    input  wire        i_mem_req_rdy,
    output wire [31:0] o_mem_req_addr,
    output wire        o_mem_req_write,
    output wire [ 3:0] o_mem_req_wmask,
    output wire [31:0] o_mem_req_wdata,
    input  wire        i_mem_rsp_vld,
    output wire        o_mem_rsp_rdy,
    input  wire [31:0] i_mem_rsp_data
);

localparam integer SET_COUNT = 128;
localparam [3:0] ST_IDLE        = 4'd0;
localparam [3:0] ST_LOOKUP      = 4'd1;
localparam [3:0] ST_VICTIM_REQ  = 4'd2;
localparam [3:0] ST_VICTIM_CAP  = 4'd3;
localparam [3:0] ST_WRITEBACK   = 4'd4;
localparam [3:0] ST_REFILL      = 4'd5;
localparam [3:0] ST_INSTALL     = 4'd6;
localparam [3:0] ST_STORE_HIT   = 4'd7;
localparam [3:0] ST_RSP         = 4'd8;

reg [3:0] r_state;
reg       r_valid_way0 [0:SET_COUNT-1];
reg       r_valid_way1 [0:SET_COUNT-1];
reg       r_dirty_way0 [0:SET_COUNT-1];
reg       r_dirty_way1 [0:SET_COUNT-1];
reg       r_rr         [0:SET_COUNT-1];

reg [31:0] r_req_addr;
reg        r_req_load;
reg        r_req_write;
reg [ 3:0] r_req_wmask;
reg [31:0] r_req_wdata;
reg        r_hit_way;
reg        r_victim_way;
reg [19:0] r_victim_tag;
reg [ 1:0] r_chunk_count;
reg [ 3:0] r_wb_req_count;
reg [ 3:0] r_wb_rsp_count;
reg [ 3:0] r_refill_req_count;
reg [ 3:0] r_refill_rsp_count;
reg [ 1:0] r_install_count;
reg [255:0] r_victim_line;
reg [255:0] r_fill_line;
reg [31:0] r_cpu_rsp_data;

wire [19:0] way0_tag_rdata;
wire [19:0] way1_tag_rdata;
wire [63:0] way0_data_rdata;
wire [63:0] way1_data_rdata;

wire [6:0] req_set = r_req_addr[11:5];
wire [2:0] req_word = r_req_addr[4:2];
wire [19:0] req_tag = r_req_addr[31:12];

wire lookup_hit_way0 = r_valid_way0[req_set]
                     && (way0_tag_rdata == req_tag);
wire lookup_hit_way1 = r_valid_way1[req_set]
                     && (way1_tag_rdata == req_tag);
wire lookup_hit = lookup_hit_way0 || lookup_hit_way1;
wire lookup_way = lookup_hit_way1 && !lookup_hit_way0;
wire [63:0] lookup_chunk_data = lookup_way
                              ? way1_data_rdata : way0_data_rdata;
wire [31:0] lookup_word_data = req_word[0]
                             ? lookup_chunk_data[63:32]
                             : lookup_chunk_data[31:0];

wire victim_way = !r_valid_way0[req_set] ? 1'b0
                : !r_valid_way1[req_set] ? 1'b1
                : r_rr[req_set];
wire victim_valid = victim_way ? r_valid_way1[req_set]
                               : r_valid_way0[req_set];
wire victim_dirty = victim_way ? r_dirty_way1[req_set]
                               : r_dirty_way0[req_set];
wire [19:0] victim_tag = victim_way ? way1_tag_rdata
                                    : way0_tag_rdata;

wire lookup_rsp_vld = (r_state == ST_LOOKUP) && lookup_hit
                    && !r_req_write;
assign o_cpu_rsp_vld = lookup_rsp_vld || (r_state == ST_RSP);
assign o_cpu_rsp_data = lookup_rsp_vld
                      ? (r_req_load ? lookup_word_data : 32'b0)
                      : r_cpu_rsp_data;

assign o_cpu_req_rdy = (r_state == ST_IDLE)
                     || ((r_state == ST_LOOKUP) && lookup_hit
                         && !r_req_write && i_cpu_rsp_rdy)
                     || ((r_state == ST_RSP) && i_cpu_rsp_rdy);

wire cpu_req_fire = i_cpu_req_vld && o_cpu_req_rdy;
wire cpu_rsp_fire = o_cpu_rsp_vld && i_cpu_rsp_rdy;
wire mem_req_fire = o_mem_req_vld && i_mem_req_rdy;
wire mem_rsp_fire = i_mem_rsp_vld && o_mem_rsp_rdy;
wire wb_last_rsp = (r_wb_rsp_count == 4'd7);
wire refill_last_rsp = (r_refill_rsp_count == 4'd7);

assign o_mem_req_vld = ((r_state == ST_WRITEBACK)
                     && (r_wb_req_count < 4'd8)
                     && (r_wb_req_count == r_wb_rsp_count))
                     || ((r_state == ST_REFILL)
                     && (r_refill_req_count < 4'd8)
                     && (r_refill_req_count == r_refill_rsp_count));
assign o_mem_req_addr = (r_state == ST_WRITEBACK)
                      ? ({r_victim_tag, req_set, 5'b0}
                         + {26'b0, r_wb_req_count, 2'b00})
                      : ({r_req_addr[31:5], 5'b0}
                         + {26'b0, r_refill_req_count, 2'b00});
assign o_mem_req_write = (r_state == ST_WRITEBACK);
assign o_mem_req_wmask = (r_state == ST_WRITEBACK) ? 4'b1111 : 4'b0000;
assign o_mem_req_wdata = r_victim_line[r_wb_req_count[2:0]*32 +: 32];
assign o_mem_rsp_rdy = (r_state == ST_WRITEBACK) || (r_state == ST_REFILL);

wire lookup_array_en = cpu_req_fire;
wire victim_read_way0 = (r_state == ST_VICTIM_REQ) && !r_victim_way;
wire victim_read_way1 = (r_state == ST_VICTIM_REQ) && r_victim_way;
wire store_write_way0 = (r_state == ST_STORE_HIT) && !r_hit_way;
wire store_write_way1 = (r_state == ST_STORE_HIT) && r_hit_way;
wire install_way0 = (r_state == ST_INSTALL) && !r_victim_way;
wire install_way1 = (r_state == ST_INSTALL) && r_victim_way;
wire install_last = (r_install_count == 2'd3);

wire [8:0] lookup_data_addr = {i_cpu_req_addr[11:5],
                               i_cpu_req_addr[4:3]};
wire [8:0] victim_data_addr = {req_set, r_chunk_count};
wire [8:0] store_data_addr = {req_set, r_req_addr[4:3]};
wire [8:0] install_data_addr = {req_set, r_install_count};
wire [7:0] store_data_wmask = req_word[0]
                             ? {r_req_wmask, 4'b0000}
                             : {4'b0000, r_req_wmask};
wire [63:0] store_data_wdata = req_word[0]
                              ? {r_req_wdata, 32'b0}
                              : {32'b0, r_req_wdata};
wire [63:0] install_data = r_fill_line[r_install_count*64 +: 64];

wire way0_data_en = lookup_array_en || victim_read_way0
                  || store_write_way0 || install_way0;
wire way1_data_en = lookup_array_en || victim_read_way1
                  || store_write_way1 || install_way1;
wire way0_data_write = store_write_way0 || install_way0;
wire way1_data_write = store_write_way1 || install_way1;

wire [8:0] way0_data_addr = lookup_array_en ? lookup_data_addr
                           : victim_read_way0 ? victim_data_addr
                           : store_write_way0 ? store_data_addr
                                              : install_data_addr;
wire [8:0] way1_data_addr = lookup_array_en ? lookup_data_addr
                           : victim_read_way1 ? victim_data_addr
                           : store_write_way1 ? store_data_addr
                                              : install_data_addr;
wire [7:0] way0_data_wmask = store_write_way0 ? store_data_wmask : 8'hff;
wire [7:0] way1_data_wmask = store_write_way1 ? store_data_wmask : 8'hff;
wire [63:0] way0_data_wdata = store_write_way0 ? store_data_wdata
                                               : install_data;
wire [63:0] way1_data_wdata = store_write_way1 ? store_data_wdata
                                               : install_data;

cache_data_array_1rw u_data_way0 (
    .clk     (clk),
    .i_en    (way0_data_en),
    .i_write (way0_data_write),
    .i_addr  (way0_data_addr),
    .i_wmask (way0_data_wmask),
    .i_wdata (way0_data_wdata),
    .o_rdata (way0_data_rdata)
);

cache_data_array_1rw u_data_way1 (
    .clk     (clk),
    .i_en    (way1_data_en),
    .i_write (way1_data_write),
    .i_addr  (way1_data_addr),
    .i_wmask (way1_data_wmask),
    .i_wdata (way1_data_wdata),
    .o_rdata (way1_data_rdata)
);

cache_tag_array_1rw u_tag_way0 (
    .clk     (clk),
    .i_en    (lookup_array_en || (install_way0 && install_last)),
    .i_write (install_way0 && install_last),
    .i_addr  (lookup_array_en ? i_cpu_req_addr[11:5] : req_set),
    .i_wdata (req_tag),
    .o_rdata (way0_tag_rdata)
);

cache_tag_array_1rw u_tag_way1 (
    .clk     (clk),
    .i_en    (lookup_array_en || (install_way1 && install_last)),
    .i_write (install_way1 && install_last),
    .i_addr  (lookup_array_en ? i_cpu_req_addr[11:5] : req_set),
    .i_wdata (req_tag),
    .o_rdata (way1_tag_rdata)
);

function automatic [31:0] merge_word;
    input [31:0] old_word;
    input [31:0] new_word;
    input [ 3:0] byte_mask;
    integer byte_idx;
    begin
        merge_word = old_word;
        for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
            if (byte_mask[byte_idx])
                merge_word[byte_idx*8 +: 8] = new_word[byte_idx*8 +: 8];
        end
    end
endfunction

wire [31:0] refill_word = (r_req_write
                         && (r_refill_rsp_count[2:0] == req_word))
                         ? merge_word(i_mem_rsp_data, r_req_wdata, r_req_wmask)
                         : i_mem_rsp_data;

integer set_idx;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_state <= ST_IDLE;
        r_req_addr <= 32'b0;
        r_req_load <= 1'b0;
        r_req_write <= 1'b0;
        r_req_wmask <= 4'b0;
        r_req_wdata <= 32'b0;
        r_hit_way <= 1'b0;
        r_victim_way <= 1'b0;
        r_victim_tag <= 20'b0;
        r_chunk_count <= 2'b0;
        r_wb_req_count <= 4'b0;
        r_wb_rsp_count <= 4'b0;
        r_refill_req_count <= 4'b0;
        r_refill_rsp_count <= 4'b0;
        r_install_count <= 2'b0;
        r_victim_line <= 256'b0;
        r_fill_line <= 256'b0;
        r_cpu_rsp_data <= 32'b0;
        for (set_idx = 0; set_idx < SET_COUNT; set_idx = set_idx + 1) begin
            r_valid_way0[set_idx] <= 1'b0;
            r_valid_way1[set_idx] <= 1'b0;
            r_dirty_way0[set_idx] <= 1'b0;
            r_dirty_way1[set_idx] <= 1'b0;
            r_rr[set_idx] <= 1'b0;
        end
    end else begin
        if (cpu_req_fire) begin
            r_req_addr <= i_cpu_req_addr;
            r_req_load <= i_cpu_req_load;
            r_req_write <= i_cpu_req_write;
            r_req_wmask <= i_cpu_req_wmask;
            r_req_wdata <= i_cpu_req_wdata;
        end

        case (r_state)
            ST_IDLE: begin
                if (cpu_req_fire)
                    r_state <= ST_LOOKUP;
            end

            ST_LOOKUP: begin
                if (lookup_hit) begin
                    if (r_req_write) begin
                        r_hit_way <= lookup_way;
                        r_state <= ST_STORE_HIT;
                    end else if (cpu_rsp_fire) begin
                        if (cpu_req_fire)
                            r_state <= ST_LOOKUP;
                        else
                            r_state <= ST_IDLE;
                    end else begin
                        r_cpu_rsp_data <= r_req_load ? lookup_word_data : 32'b0;
                        r_state <= ST_RSP;
                    end
                end else begin
                    r_victim_way <= victim_way;
                    r_victim_tag <= victim_tag;
                    r_chunk_count <= 2'b0;
                    if (victim_valid && victim_dirty) begin
                        r_state <= ST_VICTIM_REQ;
                    end else begin
                        if (victim_way) begin
                            r_valid_way1[req_set] <= 1'b0;
                            r_dirty_way1[req_set] <= 1'b0;
                        end else begin
                            r_valid_way0[req_set] <= 1'b0;
                            r_dirty_way0[req_set] <= 1'b0;
                        end
                        r_refill_req_count <= 4'b0;
                        r_refill_rsp_count <= 4'b0;
                        r_state <= ST_REFILL;
                    end
                end
            end

            ST_VICTIM_REQ: begin
                r_state <= ST_VICTIM_CAP;
            end

            ST_VICTIM_CAP: begin
                r_victim_line[r_chunk_count*64 +: 64]
                    <= r_victim_way ? way1_data_rdata : way0_data_rdata;
                if (r_chunk_count == 2'd3) begin
                    r_wb_req_count <= 4'b0;
                    r_wb_rsp_count <= 4'b0;
                    r_state <= ST_WRITEBACK;
                end else begin
                    r_chunk_count <= r_chunk_count + 1'b1;
                    r_state <= ST_VICTIM_REQ;
                end
            end

            ST_WRITEBACK: begin
                if (mem_req_fire)
                    r_wb_req_count <= r_wb_req_count + 1'b1;
                if (mem_rsp_fire) begin
                    r_wb_rsp_count <= r_wb_rsp_count + 1'b1;
                    if (wb_last_rsp) begin
                        if (r_victim_way) begin
                            r_valid_way1[req_set] <= 1'b0;
                            r_dirty_way1[req_set] <= 1'b0;
                        end else begin
                            r_valid_way0[req_set] <= 1'b0;
                            r_dirty_way0[req_set] <= 1'b0;
                        end
                        r_refill_req_count <= 4'b0;
                        r_refill_rsp_count <= 4'b0;
                        r_state <= ST_REFILL;
                    end
                end
            end

            ST_REFILL: begin
                if (mem_req_fire)
                    r_refill_req_count <= r_refill_req_count + 1'b1;
                if (mem_rsp_fire) begin
                    r_fill_line[r_refill_rsp_count[2:0]*32 +: 32]
                        <= refill_word;
                    r_refill_rsp_count <= r_refill_rsp_count + 1'b1;
                    if (refill_last_rsp) begin
                        r_install_count <= 2'b0;
                        r_state <= ST_INSTALL;
                    end
                end
            end

            ST_INSTALL: begin
                if (install_last) begin
                    if (r_victim_way) begin
                        r_valid_way1[req_set] <= 1'b1;
                        r_dirty_way1[req_set] <= r_req_write;
                    end else begin
                        r_valid_way0[req_set] <= 1'b1;
                        r_dirty_way0[req_set] <= r_req_write;
                    end
                    r_rr[req_set] <= ~r_victim_way;
                    r_cpu_rsp_data <= r_req_load
                                    ? r_fill_line[req_word*32 +: 32]
                                    : 32'b0;
                    r_state <= ST_RSP;
                end else begin
                    r_install_count <= r_install_count + 1'b1;
                end
            end

            ST_STORE_HIT: begin
                if (r_hit_way)
                    r_dirty_way1[req_set] <= 1'b1;
                else
                    r_dirty_way0[req_set] <= 1'b1;
                r_cpu_rsp_data <= 32'b0;
                r_state <= ST_RSP;
            end

            ST_RSP: begin
                if (cpu_rsp_fire) begin
                    if (cpu_req_fire)
                        r_state <= ST_LOOKUP;
                    else
                        r_state <= ST_IDLE;
                end
            end

            default: r_state <= ST_IDLE;
        endcase
    end
end

`ifndef SYNTHESIS
always @(posedge clk) begin
    if (rst_n && (r_state == ST_LOOKUP)
        && lookup_hit_way0 && lookup_hit_way1)
        $error("[DCACHE SVA] duplicate way hit in set %0d", req_set);
end
`endif

endmodule
