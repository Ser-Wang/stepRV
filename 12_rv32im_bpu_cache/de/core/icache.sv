`timescale 1ns / 1ps

module icache (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        i_cpu_req_vld,
    output wire        o_cpu_req_rdy,
    input  wire [31:0] i_cpu_req_addr,
    output wire        o_cpu_rsp_vld,
    input  wire        i_cpu_rsp_rdy,
    output wire [31:0] o_cpu_rsp_data,

    output wire        o_mem_req_vld,
    input  wire        i_mem_req_rdy,
    output wire [31:0] o_mem_req_addr,
    input  wire        i_mem_rsp_vld,
    output wire        o_mem_rsp_rdy,
    input  wire [31:0] i_mem_rsp_data
);

localparam integer SET_COUNT = 128;
localparam [2:0] ST_IDLE    = 3'd0;
localparam [2:0] ST_LOOKUP  = 3'd1;
localparam [2:0] ST_REFILL  = 3'd2;
localparam [2:0] ST_INSTALL = 3'd3;
localparam [2:0] ST_RSP     = 3'd4;

reg [2:0] r_state;
reg       r_valid_way0 [0:SET_COUNT-1];
reg       r_valid_way1 [0:SET_COUNT-1];
reg       r_rr         [0:SET_COUNT-1];

reg [31:0]  r_req_addr;
reg         r_victim_way;
reg [3:0]   r_refill_req_count;
reg [3:0]   r_refill_rsp_count;
reg [1:0]   r_install_count;
reg [255:0] r_fill_line;
reg [31:0]  r_cpu_rsp_data;

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

wire lookup_rsp_vld = (r_state == ST_LOOKUP) && lookup_hit;
assign o_cpu_rsp_vld = lookup_rsp_vld || (r_state == ST_RSP);
assign o_cpu_rsp_data = lookup_rsp_vld ? lookup_word_data : r_cpu_rsp_data;

assign o_cpu_req_rdy = (r_state == ST_IDLE)
                     || ((r_state == ST_LOOKUP) && lookup_hit
                         && i_cpu_rsp_rdy)
                     || ((r_state == ST_RSP) && i_cpu_rsp_rdy);

wire cpu_req_fire = i_cpu_req_vld && o_cpu_req_rdy;
wire cpu_rsp_fire = o_cpu_rsp_vld && i_cpu_rsp_rdy;
wire mem_req_fire = o_mem_req_vld && i_mem_req_rdy;
wire mem_rsp_fire = i_mem_rsp_vld && o_mem_rsp_rdy;
wire refill_last_rsp = (r_refill_rsp_count == 4'd7);

assign o_mem_req_vld = (r_state == ST_REFILL)
                     && (r_refill_req_count < 4'd8)
                     && (r_refill_req_count == r_refill_rsp_count);
assign o_mem_req_addr = {r_req_addr[31:5], 5'b0}
                      + {26'b0, r_refill_req_count, 2'b00};
assign o_mem_rsp_rdy = (r_state == ST_REFILL);

wire lookup_array_en = cpu_req_fire;
wire install_way0 = (r_state == ST_INSTALL) && !r_victim_way;
wire install_way1 = (r_state == ST_INSTALL) && r_victim_way;
wire install_last = (r_install_count == 2'd3);
wire [8:0] lookup_data_addr = {i_cpu_req_addr[11:5],
                               i_cpu_req_addr[4:3]};
wire [8:0] install_data_addr = {r_req_addr[11:5], r_install_count};
wire [63:0] install_data = r_fill_line[r_install_count*64 +: 64];

cache_data_array_1rw u_data_way0 (
    .clk     (clk),
    .i_en    (lookup_array_en || install_way0),
    .i_write (install_way0),
    .i_addr  (lookup_array_en ? lookup_data_addr : install_data_addr),
    .i_wmask (8'hff),
    .i_wdata (install_data),
    .o_rdata (way0_data_rdata)
);

cache_data_array_1rw u_data_way1 (
    .clk     (clk),
    .i_en    (lookup_array_en || install_way1),
    .i_write (install_way1),
    .i_addr  (lookup_array_en ? lookup_data_addr : install_data_addr),
    .i_wmask (8'hff),
    .i_wdata (install_data),
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

integer set_idx;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_state <= ST_IDLE;
        r_req_addr <= 32'b0;
        r_victim_way <= 1'b0;
        r_refill_req_count <= 4'b0;
        r_refill_rsp_count <= 4'b0;
        r_install_count <= 2'b0;
        r_fill_line <= 256'b0;
        r_cpu_rsp_data <= 32'b0;
        for (set_idx = 0; set_idx < SET_COUNT; set_idx = set_idx + 1) begin
            r_valid_way0[set_idx] <= 1'b0;
            r_valid_way1[set_idx] <= 1'b0;
            r_rr[set_idx] <= 1'b0;
        end
    end else begin
        if (cpu_req_fire) begin
            r_req_addr <= i_cpu_req_addr;
        end

        case (r_state)
            ST_IDLE: begin
                if (cpu_req_fire)
                    r_state <= ST_LOOKUP;
            end

            ST_LOOKUP: begin
                if (lookup_hit) begin
                    if (cpu_rsp_fire) begin
                        if (cpu_req_fire)
                            r_state <= ST_LOOKUP;
                        else
                            r_state <= ST_IDLE;
                    end else begin
                        r_cpu_rsp_data <= lookup_word_data;
                        r_state <= ST_RSP;
                    end
                end else begin
                    r_victim_way <= victim_way;
                    r_refill_req_count <= 4'b0;
                    r_refill_rsp_count <= 4'b0;
                    if (victim_way)
                        r_valid_way1[req_set] <= 1'b0;
                    else
                        r_valid_way0[req_set] <= 1'b0;
                    r_state <= ST_REFILL;
                end
            end

            ST_REFILL: begin
                if (mem_req_fire)
                    r_refill_req_count <= r_refill_req_count + 1'b1;

                if (mem_rsp_fire) begin
                    r_fill_line[r_refill_rsp_count[2:0]*32 +: 32]
                        <= i_mem_rsp_data;
                    r_refill_rsp_count <= r_refill_rsp_count + 1'b1;
                    if (refill_last_rsp) begin
                        r_install_count <= 2'b0;
                        r_state <= ST_INSTALL;
                    end
                end
            end

            ST_INSTALL: begin
                if (install_last) begin
                    if (r_victim_way)
                        r_valid_way1[req_set] <= 1'b1;
                    else
                        r_valid_way0[req_set] <= 1'b1;
                    r_rr[req_set] <= ~r_victim_way;
                    r_cpu_rsp_data <= r_fill_line[req_word*32 +: 32];
                    r_state <= ST_RSP;
                end else begin
                    r_install_count <= r_install_count + 1'b1;
                end
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
        $error("[ICACHE SVA] duplicate way hit in set %0d", req_set);
end
`endif

endmodule
