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

localparam integer LINE_COUNT = 128;
localparam integer WORDS_PER_LINE = 8;
localparam [1:0] ST_IDLE   = 2'd0;
localparam [1:0] ST_REFILL = 2'd1;
localparam [1:0] ST_RSP    = 2'd2;

reg [1:0]  r_state;
reg        r_valid [0:LINE_COUNT-1];
reg [19:0] r_tag   [0:LINE_COUNT-1];
reg [31:0] r_data  [0:LINE_COUNT-1][0:WORDS_PER_LINE-1];

reg [31:0] r_miss_addr;
reg [3:0]  r_refill_req_count;
reg [3:0]  r_refill_rsp_count;
reg [31:0] r_cpu_rsp_data;

wire [6:0] cpu_index = i_cpu_req_addr[11:5];
wire [2:0] cpu_word  = i_cpu_req_addr[4:2];
wire [19:0] cpu_tag  = i_cpu_req_addr[31:12];
wire cpu_hit = r_valid[cpu_index] && (r_tag[cpu_index] == cpu_tag);

wire [6:0] miss_index = r_miss_addr[11:5];
wire [2:0] miss_word  = r_miss_addr[4:2];
wire [19:0] miss_tag  = r_miss_addr[31:12];

wire cpu_rsp_fire = o_cpu_rsp_vld && i_cpu_rsp_rdy;
wire cpu_req_fire = i_cpu_req_vld && o_cpu_req_rdy;
wire mem_req_fire = o_mem_req_vld && i_mem_req_rdy;
wire mem_rsp_fire = i_mem_rsp_vld && o_mem_rsp_rdy;
wire refill_last_rsp = (r_refill_rsp_count == 4'd7);

assign o_cpu_req_rdy = (r_state == ST_IDLE)
                     || ((r_state == ST_RSP) && i_cpu_rsp_rdy);
assign o_cpu_rsp_vld = (r_state == ST_RSP);
assign o_cpu_rsp_data = r_cpu_rsp_data;

// Keep at most one backend word transaction outstanding. A backend may hold
// its response for arbitrary cycles; each accepted response owns one slot.
assign o_mem_req_vld = (r_state == ST_REFILL)
                     && (r_refill_req_count < 4'd8)
                     && (r_refill_req_count == r_refill_rsp_count);
assign o_mem_req_addr = {r_miss_addr[31:5], 5'b0}
                      + {26'b0, r_refill_req_count, 2'b00};
assign o_mem_rsp_rdy = (r_state == ST_REFILL);

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_state <= ST_IDLE;
        r_miss_addr <= 32'b0;
        r_refill_req_count <= 4'b0;
        r_refill_rsp_count <= 4'b0;
        r_cpu_rsp_data <= 32'b0;
        for (i = 0; i < LINE_COUNT; i = i + 1)
            r_valid[i] <= 1'b0;
    end else begin
        case (r_state)
            ST_IDLE: begin
                if (cpu_req_fire) begin
                    if (cpu_hit) begin
                        r_cpu_rsp_data <= r_data[cpu_index][cpu_word];
                        r_state <= ST_RSP;
                    end else begin
                        r_miss_addr <= i_cpu_req_addr;
                        r_refill_req_count <= 4'b0;
                        r_refill_rsp_count <= 4'b0;
                        r_valid[cpu_index] <= 1'b0;
                        r_state <= ST_REFILL;
                    end
                end
            end

            ST_REFILL: begin
                if (mem_req_fire)
                    r_refill_req_count <= r_refill_req_count + 1'b1;

                if (mem_rsp_fire) begin
                    r_data[miss_index][r_refill_rsp_count[2:0]] <= i_mem_rsp_data;
                    r_refill_rsp_count <= r_refill_rsp_count + 1'b1;
                    if (refill_last_rsp) begin
                        r_tag[miss_index] <= miss_tag;
                        r_valid[miss_index] <= 1'b1;
                        r_cpu_rsp_data <= (miss_word == 3'd7)
                                        ? i_mem_rsp_data
                                        : r_data[miss_index][miss_word];
                        r_state <= ST_RSP;
                    end
                end
            end

            ST_RSP: begin
                if (cpu_rsp_fire) begin
                    if (cpu_req_fire) begin
                        if (cpu_hit) begin
                            r_cpu_rsp_data <= r_data[cpu_index][cpu_word];
                        end else begin
                            r_miss_addr <= i_cpu_req_addr;
                            r_refill_req_count <= 4'b0;
                            r_refill_rsp_count <= 4'b0;
                            r_valid[cpu_index] <= 1'b0;
                            r_state <= ST_REFILL;
                        end
                    end else begin
                        r_state <= ST_IDLE;
                    end
                end
            end

            default: r_state <= ST_IDLE;
        endcase
    end
end

endmodule
