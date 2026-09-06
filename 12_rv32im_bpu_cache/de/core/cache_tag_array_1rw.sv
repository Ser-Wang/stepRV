`timescale 1ns / 1ps

module cache_tag_array_1rw (
    input  wire        clk,
    input  wire        i_en,
    input  wire        i_write,
    input  wire [ 6:0] i_addr,
    input  wire [19:0] i_wdata,
    output reg  [19:0] o_rdata
);

reg [19:0] r_tag [0:127];

always @(posedge clk) begin
    if (i_en) begin
        if (i_write)
            r_tag[i_addr] <= i_wdata;
        else
            o_rdata <= r_tag[i_addr];
    end
end

endmodule
