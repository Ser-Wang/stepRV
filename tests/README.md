# RISC-V 验证测试资源目录

本目录存放用于 RISC-V 处理器仿真验证的指令集测试案例及相关源码。

## 目录结构说明

### 1. [rv_tests_isa](./rv_tests_isa) (仿真资产)
- **来源**：源自 [riscv-tests](https://github.com/riscv-software-src/riscv-tests) 编译后的文件。
- **说明**：包含按功能分类（如 `rv32ui` 基础整数、`rv32um` 乘除法）的测试案例。
- **文件后缀**：
    - `.bin`: 原始二进制镜像（已删除以减小仓库体积）。
    - `.data`: 预转化的十六进制文本，供仿真器通过 `$readmemh` 直接加载。
    - `.dump`: 对应的反汇编文件，方便调试时定位指令。

### 2. [rv_compilance](./rv_compilance) (仿真资产)
- **来源**：源自 [riscv-compliance](https://github.com/riscv/riscv-compliance) 编译后的文件。
- **说明**：用于验证处理器是否符合 RISC-V 指令集规范的标准测试。
- **文件后缀**：
    - `.bin`: 原始二进制镜像（已删除以减小仓库体积）。
    - `.data`: 预转化的十六进制文本。
    - `.ref`: 官方提供的标准结果（Reference Output），用于自动化比对。

---

## 工具说明
- **同步脚本**：`update_tests.py` 脚本负责从编译输出目录中提取资产并按规范重命名至上述仿真资产目录中。使用时
- **批量转换**：`bin2mem_batch.py` 用于一次性将所有二进制文件转换为仿真所需的 `.data` 格式。
