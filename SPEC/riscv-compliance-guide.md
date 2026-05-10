# RISC-V Compliance Test 运行原理与移植指南 (IC设计视角)

本文档面向数字 IC 设计与验证人员，详细梳理了 `riscv-compliance`（RISC-V 官方合规性测试套件）的运行机制、文件组成架构，以及将该测试套件移植到自定义 CPU 上的核心配置项。

---

## 1. 测试的核心原理逻辑

RISC-V Compliance 测试的核心思想是：**“黑盒运算，内存交卷”**。
它不依赖于任何复杂的外部设配（如 UART 串口、屏幕），纯粹通过考察 CPU 对特定指令执行后，留存在内存中的数据是否正确，来判断 CPU 逻辑的正确性。

### 1.1 数据流向与状态机
1. **加载运行**：CPU 上电复位，从预先加载了二进制机器码的指令存储器（ITCM/ROM）中取出指令并执行。
2. **运算与驻留**：汇编测试代码将大量的计算结果，依次用 `sw`（Store Word）指令保存到一段特定的内存连续区间，这段空间被称为 **Signature Area（签名区）**。
3. **触发停机（HALT）**：测试程序的最后，CPU 会向一个特殊的硬件地址（Magic Address）写入特定的值，向外部仿真环境（Testbench）发送“交卷”信号。
4. **导出比对**：Testbench 监听到停机信号后立刻停止仿真，将“签名区”的内存数据 Dump 成文本文件（`signature.output`），并与官方提供的标准答案（`.reference_output`）进行逐行文本比对。完全一致则 PASS。

---

## 2. 目录结构与核心文件解析

官方框架把系统拆成了三大核心模块：**题库**、**官方环境**、**硬件适配器**。

### 2.1 `riscv-test-suite/` (官方标准题库)
这是 RISC-V 官方维护的汇编测试用例，按指令集（如 `rv32i`, `rv32im`）分类。
*   **`src/*.S`**：测试源码。里面几乎没有原始汇编，全是用宏定义的抽象指令（如 `TEST_RR_OP`），隐藏了繁琐的数据搬运过程。
*   **`references/*.reference_output`**：**Golden Data（标准答案）**，记录了指令执行正确的终态内存数据。

### 2.2 `riscv-test-env/` (官方宏与环境模板)
这是平台无关的通用库（类似于 UVM/OVM 的 Base Class）。
*   **`test_macros.h` / `riscv_test_macros.h`**：将复杂的测试逻辑打包成单行宏（Macro）。预编译时，这些宏会展开成几十行基础汇编代码。
*   **`encoding.h`**：CSR 寄存器字典，定义了系统寄存器和控制位宽的标准名字，防止代码出现 Magic Number。
*   **`p/link.ld` (重要)**：默认的**链接脚本（Linker Script）**。它定义了全局的地址映射（Memory Map）。
    *   规定了 `.text.init`（复位启动代码）默认放在 `0x00000000`。
    *   通过 `ALIGN(0x1000)` 命令，将不同的段（如 `.tohost`, `.text`, `.data`）对齐到 4KB 边界。这要求 IC 硬件配置与之匹配的 Reset PC 和 SRAM 深度。
    *   *注：虽然这里预留了 `.tohost` 用于 HTIF 传统主机通信接口，但在多数极简 CPU（如 tinyriscv）中，数据总线并不会访问它，它在此仅作为架构兼容性的占位符。*

### 2.3 `riscv-target/` (硬件适配接口)
这是**唯一需要你针对自己的 CPU 进行大量修改**的地方，相当于让通用测试题兼容你硬件平台的“转接口”。
*   **`你的CPU名/compliance_test.h`**：软硬件握手协议。
    *   定义了魔法地址 `TESTUTIL_BASE` 和 `TESTUTIL_ADDR_HALT`。
    *   定义了停机宏 `RV_COMPLIANCE_HALT`。当代码跑到这里时，CPU 数据总线向停机地址写入数据，通知 Testbench 结束仿真。
*   **`你的CPU名/compliance_io.h`**：字符打印协议。极简验证环境下，里面通常全是空宏（跳过打印）。
*   **`你的CPU名/device/rv32*/Makefile.include`**：底层编译脚本。
    *   配置 GCC 交叉编译器的调用，利用 `-I` 参数引入上文提到的定制化 `.h` 握手文件。
    *   包含生成 `.elf`、提取 `.objdump`（反汇编文件，供 IC 调试看波形抓 PC 用）以及提取 `.bin`（直接灌入硬件的机器码）的流水线命令。
    *   *由于多数处理器同属一个系列时编译 flags 差异不大，这里不同指令集目录下的 `Makefile.include` 常常一模一样，通过上一级 Makefile 的传参 `$(1)` 来区分架构指令集。*

---

## 3. 编译流转全过程

在真正进行 RTL 仿真之前，编译系统（Makefile）会发生如下的化学反应：

1. **组合**：编译器收到一个 `.S` 测试文件。预处理器开始发力，根据 `-I` 参数，把 `riscv-test-env` 里的标准宏，和 `riscv-target` 里的硬件专属停机宏，全部替换并塞进 `.S` 源码里。
2. **汇编与链接**：结合 `link.ld` 链接脚本，把包含实际地址绝对映射的指令汇编成 `.elf` 文件。
3. **萃取**：利用 `objdump` 导出带地址的反汇编文件备查，利用 `objcopy` 去掉所有头部信息，萃取出纯粹的、连续的机器码二进制 `.bin` 文件。
4. **格式转换**：由仿真脚本（如 Python 脚本）将 `.bin` 转成 `$readmemh` 格式的 `.mem`，等待 Testbench 加载。

---

## 4. 自定义 CPU 移植与配置指南

当你要将这套框架套用到你自己研发的 CPU 时，你需要配置以下三端：

### 4.1 软件（C/汇编）端的配置
在 `riscv-target/你的CPU/` 下建立目录：
1. **修改 `compliance_test.h`**：
   * 确定一个你的数据存储器（SRAM/DTCM）以外的空闲地址作为 `HALT_ADDR`。
   * 修改 `RV_COMPLIANCE_HALT` 宏的汇编代码，使其向该地址写入标识。
2. **修改 `device/rv32*/Makefile.include`**：
   * 确保 `RISCV_GCC_OPTS` 配置对齐你的 CPU 支持的 ABI（如 `-mabi=ilp32`）和额外的编译优化选项。

### 4.2 链接脚本端的配置
1. **核对复位 PC**：确信你的 CPU `reset_pc` 与 `link.ld` 中的 `. = 0x00000000`（或你修改后的地址）严丝合缝。
2. **核对地址深度**：确认 `link.ld` 中的各个 `ALIGN(0x1000)` 所拉扯出的跨度，没有超出你在 Testbench 里挂载的 SRAM 模型的最大地址范围。

### 4.3 Testbench 端的配合
这是纯 IC 侧的工作，必须与刚才软件端的配置遥相呼应：
1. **挂载总线探针**：在你的 Verilog Testbench 中，写一段 `always` 或 `initial` 逻辑，监视 CPU 发出的数据写总线行为。
2. **捕获停机与 Dump**：
   ```verilog
   // 伪代码示例
   always @(posedge clk) begin
       if (bus_write_en && bus_addr == `HALT_ADDR) begin
           $display("Simulation Finished by CPU!");
           // 使用系统函数将 Signature 内存区间写入文件
           $writememh("signature.output", memory_array, `SIGNATURE_BEGIN, `SIGNATURE_END);
           $finish;
       end
   end
   ```
3. 最后，通过 Python/Shell 脚本拉起自动比对流程（对比你的 `signature.output` 和官方的 `.reference_output`）。
