# SystemVerilog 断言（SVA）采样机制与“打印滞后”问题分析

在进行 SystemVerilog 仿真时，经常会遇到一个困惑：**断言明明触发了，但断言报错信息里打印出的信号值却是正常的（或者是下一个时钟周期的值）。** 这种“打印滞后”现象是由 SystemVerilog 的仿真调度机制决定的。

---

## 1. 原理分析：采样值 vs. 当前值

SystemVerilog 将一个时钟周期划分为多个“调度区域（Scheduling Regions）”。

### 采样值 (Sampled Values)
*   **区域**：Preponed 区域（时钟上升沿之前的时刻）。
*   **用途**：**并发断言（Concurrent Assertions）** 使用采样值。它检查的是时钟跳变前一刻信号的状态。
*   **逻辑**：这符合硬件行为，即触发器在时钟上升沿捕获的是稳定的前级输入。

### 当前值 (Current Values)
*   **区域**：Active / Observed / Reactive 区域（时钟上升沿之后的时刻）。
*   **用途**：**动作块（Action Blocks）**，即 `assert property (...) else begin $display(...); end` 中的 `$display` 语句使用的是当前值。
*   **逻辑**：此时时钟已经上升，非阻塞赋值（`<=`）已经生效，寄存器可能已经更新到了下一个状态。

**结论：** 断言是根据“过去”的采样值判断失败的，但 `$display` 打印的是“现在”的更新值，导致看到的信息与触发原因不一致。

---

## 2. 案例描述：RISC-V LSU 地址对齐检查

在一个 RISC-V 处理器的加载/存储单元（LSU）中，我们需要检查内存访问地址（`mema_addr`）是否对齐（例如访问 4 字节 Word 时，地址低两位必须为 `2'b00`）。

### 场景代码
```systemverilog
property p_mema_addr_align;
    @(posedge clk) disable iff (!rst_n)
        (lsu_req_load || lsu_req_store) |-> (mema_addr[1:0] == 2'b00);
endproperty

assert property (p_mema_addr_align) else begin
    // 问题点：这里打印出的 mema_addr 往往是下一个指令的地址
    $display("SVA FAILED: Addr: 0x%h", mema_addr); 
    $fatal(1);
end
```

### 故障表现
1.  在 `T=10ns` 时钟上升沿，`mema_addr` 为 `0x8000_0001`（不对齐），触发断言失败。
2.  由于 CPU 流水线运行，在 `T=10ns` 这一时刻，`mema_addr` 被更新为下一条指令的地址 `0x8000_0004`。
3.  `$display` 执行时读取的是当前值 `0x8000_0004`。
4.  最终日志输出：`SVA FAILED: Addr: 0x80000004`。
5.  **结果**：调试者看着输出的 `0x80000004`（它是对齐的）会感到莫名其妙，不知道为什么断言会失败。

---

## 3. 解决方法：使用 `$sampled()`

为了获取导致断言失败的“案发现场”值，必须使用 `$sampled()` 系统函数。

### 修复后的代码
```systemverilog
assert property (p_mema_addr_align) else begin
    // $sampled() 会强制返回断言采样时刻（Preponed 区域）的值
    $display("SVA FAILED: Addr: 0x%h", $sampled(mema_addr)); 
    $fatal(1);
end
```

使用 `$sampled(mema_addr)` 后，即使 `mema_addr` 已经发生了变化，打印出来的依然是触发断言那一瞬间的 `0x8000_0001`。

---

## 4. 最佳实践建议

1.  **并发断言必用 `$sampled`**：在任何并发断言（`assert property`）的 `else` 或 `pass` 动作块中打印变量时，应始终使用 `$sampled()`。
2.  **立即断言（Immediate Assertions）**：如果你在 `always_comb` 或 `initial` 块中使用 `assert (condition)`，它使用的是当前值，此时不需要 `$sampled`。
3.  **调试技巧**：如果 `$sampled` 依然不够清晰，可以使用 `$past(signal, 1)` 查看前一个时钟周期的状态，这在分析多周期序列（Sequences）时非常有用。
