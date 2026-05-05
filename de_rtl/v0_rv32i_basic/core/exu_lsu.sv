`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/27 01:13:41
// Design Name: 
// Module Name: exu_lsu
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
`include "../defines/config.v"

module exu_lsu(
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_lsu_rs1,
    input wire [31:0] i_lsu_rs2,
    input wire [31:0] i_lsu_imm,
    input wire [`DECINFO_BUS_LSU_WIDTH-1:0] i_dec_info_bus_lsu,
    output wire [31:0] o_mema_addr_exu,
    output wire [31:0] o_mema_wr_data_exu,
    output wire o_mema_wren_exu,
    output wire [3:0] o_mema_wr_mask,
    output wire [3:0] o_mema_ld_info, // {lsu_req_load, lsu_req_info_size, lsu_req_info_usign}
    output wire o_lsu_misaligned_exc  // Add exception signal for misaligned access
    );

// ----------------        dec_info debus        ---------------- //
// ---- dec_info debus
wire lsu_req_load       = i_dec_info_bus_lsu[`DECINFO_LSU_LOAD];
wire lsu_req_store      = i_dec_info_bus_lsu[`DECINFO_LSU_STORE];
wire lsu_req_info_usign = i_dec_info_bus_lsu[`DECINFO_LSU_USIGN];
wire [1:0] lsu_req_info_size  = i_dec_info_bus_lsu[`DECINFO_LSU_SIZE];  // 00:b 01:h 10:w


// ----------------        addr_gen, load, store        ---------------- //
// ---- Address Generation
wire [31:0] lsu_req_ag_op1 = i_lsu_rs1;
wire [31:0] lsu_req_ag_op2 = i_lsu_imm;
// wire [31:0] lsu_req_ag_op2 = (i_dec_info_bus_lsu[`DECINFO_LSU_OP2IMM]) ? i_lsu_imm : i_lsu_rs2;
wire [31:0] mema_addr = lsu_req_ag_op1 + lsu_req_ag_op2;
assign o_mema_addr_exu = mema_addr;

// ---- store data mask
wire [3:0] mema_wr_mask;
assign mema_wr_mask = (lsu_req_info_size == 2'b10) ? 4'b1111 : 
                      (lsu_req_info_size == 2'b01) ? 4'b0011 : 4'b0001;

// ---- store data
wire [31:0] lsu_data_tostore;
assign lsu_data_tostore[7:0] = i_lsu_rs2[7:0];
assign lsu_data_tostore[15:8] = (lsu_req_info_size != 2'b00) ? i_lsu_rs2[15:8] : 8'b0;
assign lsu_data_tostore[31:16] = (lsu_req_info_size == 2'b10) ? i_lsu_rs2[31:16] : 16'b0;
assign o_mema_wr_data_exu = lsu_data_tostore;

// ---- ctrl logic
assign o_mema_wren_exu = lsu_req_store && !o_lsu_misaligned_exc; // Prevent writing if address is misaligned
assign o_mema_ld_info = {lsu_req_load && !o_lsu_misaligned_exc, lsu_req_info_size, lsu_req_info_usign};


// ---- Misalignment Check
wire addr_misaligned = (lsu_req_load || lsu_req_store) && (
                       (lsu_req_info_size == 2'b10 && mema_addr[1:0] != 2'b00) || // Word must be 4-byte aligned
                       (lsu_req_info_size == 2'b01 && mema_addr[0]   != 1'b0 )    // Halfword must be 2-byte aligned
                       );
assign o_lsu_misaligned_exc = addr_misaligned;

// Simulation-only error reporting
`ifdef SIMULATION
always @(posedge clk) begin
    if (rst_n) begin
        // Existing misaligned reporting
        if (o_lsu_misaligned_exc) begin
            $display("ERROR: LSU Address Misaligned! Addr: 0x%h, Size: %b", mema_addr, lsu_req_info_size);
        end
    end
end

// SystemVerilog Assertion: for any load/store request, low two bits must not be 01 or 11
property p_mema_addr_align;
    @(posedge clk) disable iff (!rst_n)
        ( (lsu_req_load || lsu_req_store) |-> (mema_addr[1:0] != 2'b01 && mema_addr[1:0] != 2'b11) );
endproperty

// Assert the property and stop simulation on failure
// Keep this assertion separate from the existing misaligned check
assert property (p_mema_addr_align) else begin
    $display("SVA ASSERTION FAILED: mema_addr[1:0] must not be 2'b01 or 2'b11. Addr: 0x%h, Size: %b", mema_addr, lsu_req_info_size);
    $fatal(1);
end

`endif

endmodule
