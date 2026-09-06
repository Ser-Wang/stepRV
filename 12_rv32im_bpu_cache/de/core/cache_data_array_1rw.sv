`timescale 1ns / 1ps

module cache_data_array_1rw (
    input  wire        clk,
    input  wire        i_en,
    input  wire        i_write,
    input  wire [ 8:0] i_addr,
    input  wire [ 7:0] i_wmask,
    input  wire [63:0] i_wdata,
    output reg  [63:0] o_rdata
);

reg [63:0] r_data [0:511];

integer byte_idx;
always @(posedge clk) begin
    if (i_en) begin
        if (i_write) begin
            for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
                if (i_wmask[byte_idx])
                    r_data[i_addr][byte_idx*8 +: 8]
                        <= i_wdata[byte_idx*8 +: 8];
            end
        end else begin
            o_rdata <= r_data[i_addr];
        end
    end
end

endmodule
