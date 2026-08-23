`timescale 1ns / 1ps

module tb_ras_disabled;

reg         clk;
reg         rst_n;
reg         pred_update_fire;
reg         pred_pop;
reg         pred_push;
reg  [31:0] pred_push_addr;
reg         resolve_fire;
reg         resolve_pop;
reg         resolve_push;
reg  [31:0] resolve_push_addr;
reg         recover;
wire        top_vld;
wire [31:0] top_addr;
integer     failures;

ras_dual_full_stack #(.ENTRIES(4)) u_dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .o_top_vld           (top_vld),
    .o_top_addr          (top_addr),
    .i_pred_update_fire  (pred_update_fire),
    .i_pred_pop          (pred_pop),
    .i_pred_push         (pred_push),
    .i_pred_push_addr    (pred_push_addr),
    .i_resolve_fire      (resolve_fire),
    .i_resolve_pop       (resolve_pop),
    .i_resolve_push      (resolve_push),
    .i_resolve_push_addr (resolve_push_addr),
    .i_recover           (recover)
);

always #5 clk = ~clk;

task automatic apply_events;
    input do_recover;
    begin
        @(negedge clk);
        pred_update_fire = 1'b1;
        pred_pop = 1'b1;
        pred_push = 1'b1;
        pred_push_addr = 32'h1111_0004;
        resolve_fire = 1'b1;
        resolve_pop = 1'b1;
        resolve_push = 1'b1;
        resolve_push_addr = 32'h2222_0004;
        recover = do_recover;
        @(posedge clk);
        #1;
        if (top_vld !== 1'b0) begin
            failures = failures + 1;
            $display("FAIL: disabled RAS became valid (recover=%b addr=%08x)",
                     do_recover, top_addr);
        end
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    pred_update_fire = 1'b0;
    pred_pop = 1'b0;
    pred_push = 1'b0;
    pred_push_addr = 32'b0;
    resolve_fire = 1'b0;
    resolve_pop = 1'b0;
    resolve_push = 1'b0;
    resolve_push_addr = 32'b0;
    recover = 1'b0;
    failures = 0;

    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;
    apply_events(1'b0);
    apply_events(1'b1);
    apply_events(1'b0);

    if (failures == 0)
        $display("PASS: ras_dual_full_stack disabled directed test");
    else
        $display("FAIL: disabled RAS directed test, failures=%0d", failures);
    $finish;
end

endmodule
