`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/24 17:15:04
// Design Name: 
// Module Name: c_regfile
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module c_regfile(
    input wire clk,
    input wire rst_n,
    input wire [4:0] i_read_rs1_idx,
    input wire [4:0] i_read_rs2_idx,
    output wire [31:0] o_read_rs1_data,
    output wire [31:0] o_read_rs2_data,
    input wire i_wb_wen,
    input wire [4:0] i_wb_dest_idx,   // write back
    input wire [31:0] i_wb_dest_data
    );

reg [31:0] r_regfile[1:31];
wire [31:0] w_regfile[0:31];
wire [31:0] wen;

// read
assign o_read_rs1_data = w_regfile[i_read_rs1_idx];
assign o_read_rs2_data = w_regfile[i_read_rs2_idx];

// write
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        
    end
end

genvar i;
generate
    for (i=0; i<32; i=i+1) begin: regfile
        if (i == 0) begin: x0
            assign wen[i] = 1'b0;
            assign w_regfile[i] = 32'b0;
        end
        else begin
            assign wen[i] = i_wb_wen & (i_wb_dest_idx == i);
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    r_regfile[i] <= 32'b0;
                end
                else if(wen[i]) begin
                    r_regfile[i] <= i_wb_dest_data;
                end
            end
        end
    end
endgenerate



endmodule
