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

localparam integer LINE_COUNT = 128;
localparam integer WORDS_PER_LINE = 8;
localparam [1:0] ST_IDLE   = 2'd0;
localparam [1:0] ST_REFILL = 2'd1;
localparam [1:0] ST_STORE  = 2'd2;
localparam [1:0] ST_RSP    = 2'd3;

reg [1:0]  r_state;
reg        r_valid [0:LINE_COUNT-1];
reg [19:0] r_tag   [0:LINE_COUNT-1];
reg [31:0] r_data  [0:LINE_COUNT-1][0:WORDS_PER_LINE-1];

reg [31:0] r_req_addr;
reg [ 3:0] r_req_wmask;
reg [31:0] r_req_wdata;
reg        r_store_hit;
reg        r_store_req_sent;
reg [ 3:0] r_refill_req_count;
reg [ 3:0] r_refill_rsp_count;
reg [31:0] r_cpu_rsp_data;

wire [6:0] cpu_index = i_cpu_req_addr[11:5];
wire [2:0] cpu_word  = i_cpu_req_addr[4:2];
wire [19:0] cpu_tag  = i_cpu_req_addr[31:12];
wire cpu_hit = r_valid[cpu_index] && (r_tag[cpu_index] == cpu_tag);

wire [6:0] req_index = r_req_addr[11:5];
wire [2:0] req_word  = r_req_addr[4:2];
wire [19:0] req_tag  = r_req_addr[31:12];

wire cpu_rsp_fire = o_cpu_rsp_vld && i_cpu_rsp_rdy;
wire cpu_req_fire = i_cpu_req_vld && o_cpu_req_rdy;
wire mem_req_fire = o_mem_req_vld && i_mem_req_rdy;
wire mem_rsp_fire = i_mem_rsp_vld && o_mem_rsp_rdy;
wire refill_last_rsp = (r_refill_rsp_count == 4'd7);

assign o_cpu_req_rdy = (r_state == ST_IDLE)
                     || ((r_state == ST_RSP) && i_cpu_rsp_rdy);
assign o_cpu_rsp_vld = (r_state == ST_RSP);
assign o_cpu_rsp_data = r_cpu_rsp_data;

assign o_mem_req_vld = ((r_state == ST_REFILL)
                     && (r_refill_req_count < 4'd8)
                     && (r_refill_req_count == r_refill_rsp_count))
                     || ((r_state == ST_STORE) && !r_store_req_sent);
assign o_mem_req_addr = (r_state == ST_REFILL)
                      ? ({r_req_addr[31:5], 5'b0}
                         + {26'b0, r_refill_req_count, 2'b00})
                      : r_req_addr;
assign o_mem_req_write = (r_state == ST_STORE);
assign o_mem_req_wmask = (r_state == ST_STORE) ? r_req_wmask : 4'b0000;
assign o_mem_req_wdata = r_req_wdata;
assign o_mem_rsp_rdy = (r_state == ST_REFILL)
                     || ((r_state == ST_STORE) && (r_store_req_sent || mem_req_fire));

task automatic accept_cpu_request;
    begin
        r_req_addr <= i_cpu_req_addr;
        if (i_cpu_req_load) begin
            if (cpu_hit) begin
                r_cpu_rsp_data <= r_data[cpu_index][cpu_word];
                r_state <= ST_RSP;
            end else begin
                r_refill_req_count <= 4'b0;
                r_refill_rsp_count <= 4'b0;
                r_valid[cpu_index] <= 1'b0;
                r_state <= ST_REFILL;
            end
        end else if (i_cpu_req_write) begin
            r_req_wmask <= i_cpu_req_wmask;
            r_req_wdata <= i_cpu_req_wdata;
            r_store_hit <= cpu_hit;
            r_store_req_sent <= 1'b0;
            r_state <= ST_STORE;
        end else begin
            r_cpu_rsp_data <= 32'b0;
            r_state <= ST_RSP;
        end
    end
endtask

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_state <= ST_IDLE;
        r_req_addr <= 32'b0;
        r_req_wmask <= 4'b0;
        r_req_wdata <= 32'b0;
        r_store_hit <= 1'b0;
        r_store_req_sent <= 1'b0;
        r_refill_req_count <= 4'b0;
        r_refill_rsp_count <= 4'b0;
        r_cpu_rsp_data <= 32'b0;
        for (i = 0; i < LINE_COUNT; i = i + 1)
            r_valid[i] <= 1'b0;
    end else begin
        case (r_state)
            ST_IDLE: begin
                if (cpu_req_fire)
                    accept_cpu_request();
            end

            ST_REFILL: begin
                if (mem_req_fire)
                    r_refill_req_count <= r_refill_req_count + 1'b1;
                if (mem_rsp_fire) begin
                    r_data[req_index][r_refill_rsp_count[2:0]] <= i_mem_rsp_data;
                    r_refill_rsp_count <= r_refill_rsp_count + 1'b1;
                    if (refill_last_rsp) begin
                        r_tag[req_index] <= req_tag;
                        r_valid[req_index] <= 1'b1;
                        r_cpu_rsp_data <= (req_word == 3'd7)
                                        ? i_mem_rsp_data
                                        : r_data[req_index][req_word];
                        r_state <= ST_RSP;
                    end
                end
            end

            ST_STORE: begin
                if (mem_req_fire) begin
                    r_store_req_sent <= 1'b1;
                    if (r_store_hit) begin
                        if (r_req_wmask[0])
                            r_data[req_index][req_word][7:0] <= r_req_wdata[7:0];
                        if (r_req_wmask[1])
                            r_data[req_index][req_word][15:8] <= r_req_wdata[15:8];
                        if (r_req_wmask[2])
                            r_data[req_index][req_word][23:16] <= r_req_wdata[23:16];
                        if (r_req_wmask[3])
                            r_data[req_index][req_word][31:24] <= r_req_wdata[31:24];
                    end
                end
                if (mem_rsp_fire) begin
                    r_cpu_rsp_data <= 32'b0;
                    r_state <= ST_RSP;
                end
            end

            ST_RSP: begin
                if (cpu_rsp_fire) begin
                    if (cpu_req_fire)
                        accept_cpu_request();
                    else
                        r_state <= ST_IDLE;
                end
            end
        endcase
    end
end

endmodule
