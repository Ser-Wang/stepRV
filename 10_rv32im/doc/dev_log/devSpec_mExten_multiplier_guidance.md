# RV32 乘法器两阶段实现指导 SPEC

> 文档性质：指导性架构草案  
> 适用范围：在现有 RV32 顺序流水核中加入整数乘法功能  
> 工艺与频率目标：55 nm，SS 综合库，75 MHz  
> 当前阶段：仅实现乘法指令；除法与余数指令暂不包含  
> 后续用途：交由开发 agent 结合实际流水线、端口命名、异常机制和综合脚本生成正式实现 SPEC

---

## 1. 文档目标

本 SPEC 规定乘法器的两阶段演进路线：

1. **Phase 1：Radix-2 迭代乘法器**
   - 优先完成功能闭环；
   - 固定延迟、单请求在途；
   - 以低面积、低时序风险和易验证为首要目标。

2. **Phase 2：单个 17×17 MAC 的快速多周期乘法器**
   - 保持外部接口和流水线控制语义不变；
   - 仅替换乘法器内部数据通路与状态机；
   - 目标延迟为 `MUL` 3 个计算周期、MULH 类指令 4 个计算周期；
   - 必须在实际 55 nm SS 库下重新验证 75 MHz 时序。

本 SPEC 不直接规定最终 RTL 文件名和所有端口名。正式 SPEC 应结合现有核的模块边界命名、vld/rdy 规范、flush 语义和流水级划分进行映射。

---

## 2. ISA 范围

### 2.1 当前必须支持的指令

当前乘法器必须支持 RV32 的以下四条指令：

| 指令 | 操作数解释 | 写回结果 |
|---|---|---|
| `MUL` | 低 32 位结果与有符号性无关 | 完整乘积 `[31:0]` |
| `MULH` | signed `rs1` × signed `rs2` | 完整乘积 `[63:32]` |
| `MULHSU` | signed `rs1` × unsigned `rs2` | 完整乘积 `[63:32]` |
| `MULHU` | unsigned `rs1` × unsigned `rs2` | 完整乘积 `[63:32]` |

### 2.2 扩展声明

仅实现上述四条乘法指令时，处理器当前实现的是 **Zmmul 乘法子集**，不能单独宣称已经完整实现 RV32M。

完整 RV32M 还需要：

- `DIV`
- `DIVU`
- `REM`
- `REMU`

除法器将在后续独立 SPEC 中处理。

---

## 3. 总体设计原则

### 3.1 外部接口稳定

Phase 1 和 Phase 2 必须使用相同的逻辑请求/响应接口。升级到 17×17 MAC 时，不应修改：

- 译码结果语义；
- EX 级长延时指令控制框架；
- 请求/响应握手语义；
- 写回和前递接口；
- flush/kill 的外部行为。

建议将乘法器划分为：

```text
乘法器公共封装
├── 请求/响应协议
├── 操作码与结果选择
├── kill、复位和响应保持
└── 可替换实现
    ├── Radix-2 实现
    └── 17×17 MAC 实现
```

Phase 1 应保留为可综合、可回归的基线实现，Phase 2 不应直接覆盖并删除 Phase 1。

### 3.2 单请求在途

前两个阶段均只允许一个乘法请求在途：

- 乘法器空闲时才允许接受请求；
- 请求接受后，直至结果被下游接收或请求被 kill，不得接受新请求；
- 不实现请求队列；
- 不实现多个乘法并行在途；
- 不追求启动间隔 `II=1`。

### 3.3 结果必须寄存

乘法结果必须先进入乘法器内部响应寄存器，再进入处理器正常的 EX/MEM、写回和前递路径。

禁止形成以下组合路径：

```text
乘法器内部迭代组合结果
→ EX 结果选择
→ forwarding 选择
→ 流水寄存器
```

允许的路径应为：

```text
乘法器计算数据通路
→ 乘法器结果寄存器
→ EX 正常结果选择
→ 后续流水寄存器
```

这样可以避免乘法器内部关键路径继续串联普通 ALU 结果选择和前递逻辑。

---

## 4. 逻辑接口要求

以下名称仅表示语义，正式端口名按项目统一规范映射。

### 4.1 请求通道

```text
req_vld
req_rdy
req_op
req_operand_a[31:0]
req_operand_b[31:0]
```

请求仅在以下条件成立时被接受：

```text
req_fire = req_vld && req_rdy
```

要求：

- `req_rdy` 仅在乘法器能够无条件接收新请求时置 1；
- 乘法器 busy 或存在未消费响应时，`req_rdy` 必须为 0；
- 操作码和两个操作数仅在 `req_fire` 时采样；
- EX 级必须保证同一条指令只发起一次请求。

### 4.2 响应通道

```text
rsp_vld
rsp_rdy
rsp_result[31:0]
```

响应仅在以下条件成立时被接收：

```text
rsp_fire = rsp_vld && rsp_rdy
```

要求：

- 结果完成后置 `rsp_vld`；
- 当 `rsp_vld=1 && rsp_rdy=0` 时，`rsp_vld` 和 `rsp_result` 必须保持稳定；
- 响应被接收前，不得清除结果或接受下一请求；
- 结果被接收后，乘法器返回空闲态。

### 4.3 kill 接口

建议乘法器接收按事务限定的 `kill` 信号，而不是在模块内部自行解释全局 flush。

要求：

- `kill` 表示当前在途乘法指令已经不再具有架构效应；
- kill 后必须立即或在下一时钟边沿取消当前运算；
- kill 后不得产生有效响应；
- kill 必须能够取消计算中的请求和等待下游接收的响应；
- 是否由分支预测失败、旧指令异常、调试进入或其他全局事件产生 kill，由处理器集成逻辑决定。

优先级建议为：

```text
reset > kill > 响应握手 > 请求握手 > 正常状态推进
```

异步中断的最简策略是：在乘法指令完成前暂缓进入中断；若现有核采用其他精确异常策略，应在正式 SPEC 中重新定义。

---

## 5. EX 流水集成要求

### 5.1 长延时行为

乘法指令位于 EX 级时：

1. EX 向乘法器发起一次请求；
2. 请求被接受后，EX 保留该指令的有效状态；
3. 乘法器未返回结果时，EX 对上游施加反压；
4. 结果返回且下游允许接收时，乘法指令进入后续流水级；
5. 乘法指令未离开 EX 前，禁止重复发起请求。

在当前顺序单发射架构中，允许乘法执行期间停住前端和后续进入 EX 的指令。

暂不要求：

- 普通 ALU 指令越过正在执行的乘法；
- scoreboard；
- 独立发射队列；
- 乱序完成；
- 多个目的寄存器 busy 跟踪。

### 5.2 forwarding

乘法结果应复用普通 EX 结果的写回和 forwarding 通路。

必须验证：

- 紧邻下一条指令读取乘法目的寄存器；
- 中间间隔一条或多条指令的相关；
- 目的寄存器为 `x0`；
- 连续两条乘法指令；
- 乘法结果参与 branch、地址计算、store data 和下一次乘法。

不得从未寄存的乘法器内部中间结果进行前递。

---

## 6. Phase 1：Radix-2 迭代乘法器

## 6.1 目标

Phase 1 的目标是：

- 完整支持四条 RV32 乘法指令；
- 固定延迟；
- 单请求在途；
- 数据通路简单；
- 综合关键路径可控；
- 在 55 nm SS 库、13.333 ns 时钟周期下满足时序；
- 为后续 17×17 实现建立接口、验证和处理器集成基线。

Phase 1 不进行提前结束优化。

---

## 6.2 推荐算法

使用“高半部分累加、整体右移”的经典无符号 Radix-2 结构。

建议核心寄存器：

```text
raw_operand_a_q[31:0]
raw_operand_b_q[31:0]
op_q

multiplicand_q[31:0]
multiplier_q[31:0]
acc_q[32:0]
iter_count_q[5:0]

result_neg_q
result_q[31:0]
```

每次迭代执行：

```text
acc_add =
    acc_q
    + (multiplier_q[0] ? {1'b0, multiplicand_q} : 33'b0)

{acc_q, multiplier_q} =
    {acc_add, multiplier_q} >> 1
```

完成 32 次迭代后，无符号幅值乘积为：

```text
magnitude_product[63:0] = {acc_q[31:0], multiplier_q[31:0]}
```

该结构每个迭代周期的主要组合路径为：

```text
寄存器 clk-q
→ multiplier_q[0] 控制的选择
→ 33 位加法器
→ 移位连线
→ acc/multiplier 寄存器 setup
```

不得将其改写为每周期执行完整 64 位部分积加法，除非综合结果证明没有明显时序和面积劣化。

---

## 6.3 有符号处理

Phase 1 采用“操作数幅值化 + 无符号乘法 + 最终符号修正”。

### 6.3.1 操作数有符号属性

| 指令 | operand A signed | operand B signed | 结果选择 |
|---|---:|---:|---|
| `MUL` | 0 | 0 | low 32 |
| `MULH` | 1 | 1 | high 32 |
| `MULHSU` | 1 | 0 | high 32 |
| `MULHU` | 0 | 0 | high 32 |

对于 `MUL`，低 32 位与输入的有符号解释无关，因此可直接按无符号乘法处理。

### 6.3.2 幅值转换

```text
neg_a = operand_a_signed && raw_operand_a_q[31]
neg_b = operand_b_signed && raw_operand_b_q[31]

magnitude_a = neg_a ? (~raw_operand_a_q + 1'b1) : raw_operand_a_q
magnitude_b = neg_b ? (~raw_operand_b_q + 1'b1) : raw_operand_b_q

result_neg = neg_a ^ neg_b
```

`32'h8000_0000` 的幅值仍表示为 `32'h8000_0000`，不得因为有符号绝对值溢出而特殊报错。

### 6.3.3 最终符号修正

32 次迭代结束后：

```text
full_product =
    result_neg
    ? (~magnitude_product + 64'd1)
    : magnitude_product
```

结果选择：

```text
MUL    : full_product[31:0]
MULH   : full_product[63:32]
MULHSU : full_product[63:32]
MULHU  : full_product[63:32]
```

符号修正必须放在独立 FINAL 状态，不与最后一次迭代组合在同一周期。

---

## 6.4 状态机

推荐状态：

```text
IDLE
PREPARE
ITERATE
FINAL
RESPONSE
```

### IDLE

- `req_rdy=1`；
- 接受请求后寄存原始操作数和操作码；
- 转入 PREPARE。

### PREPARE

- 解析两个操作数的 signed 属性；
- 计算幅值和结果符号；
- 初始化：

```text
multiplicand_q = magnitude_a
multiplier_q   = magnitude_b
acc_q          = 0
iter_count_q   = 0
```

- 转入 ITERATE。

### ITERATE

- 每周期完成一次 Radix-2 迭代；
- 共执行 32 次；
- 禁止数据相关提前退出；
- 完成第 32 次迭代后转入 FINAL。

### FINAL

- 形成 64 位幅值乘积；
- 完成最终符号修正；
- 按操作码选择高 32 位或低 32 位；
- 写入响应结果寄存器；
- 转入 RESPONSE。

### RESPONSE

- `rsp_vld=1`；
- 下游未 ready 时保持结果不变；
- `rsp_fire` 后转入 IDLE。

### 固定延迟

模块内部计算过程固定包含：

- 1 个 PREPARE 周期；
- 32 个 ITERATE 周期；
- 1 个 FINAL 周期。

RESPONSE 等待时间取决于下游反压，不计入计算延迟。

---

## 6.5 Phase 1 禁止项

第一版不得加入：

- 乘数为零提前退出；
- 乘数为一特殊旁路；
- 基于前导零的可变迭代次数；
- Radix-4 Booth；
- MULH/MUL 指令融合；
- 共享普通 ALU 加法器而引入复杂仲裁；
- 多请求队列；
- 时钟门控单元的手工实例化；
- 未经综合验证的复杂操作数隔离。

这些优化会增加控制状态和验证空间，应在基本功能及综合基线稳定后再单独评估。

---

## 7. Phase 2：单 17×17 MAC 快速多周期乘法器

## 7.1 目标

Phase 2 保持 Phase 1 的外部协议和处理器集成完全不变，仅替换内部实现。

目标：

- 复用一个 17×17 乘法核；
- 配置一个约 34 位累加器；
- `MUL` 目标为 3 个计算周期；
- `MULH/MULHSU/MULHU` 目标为 4 个计算周期；
- 仍只允许一个请求在途；
- 结果仍必须经过响应寄存器；
- 在 55 nm SS 库下满足 75 MHz。

17×17 乘法与累加建议使用独立于普通 ALU 的内部 MAC，避免与地址生成、分支和普通算术操作争用组合资源。

---

## 7.2 操作数分块

将两个 32 位操作数拆为：

```text
A = {A_H[15:0], A_L[15:0]}
B = {B_H[15:0], B_L[15:0]}
```

低 16 位分块始终按无符号解释。

高 16 位分块的符号扩展由指令决定：

```text
sign_a = operand_a_signed && operand_a[31]
sign_b = operand_b_signed && operand_b[31]
```

17 位乘法器输入采用：

```text
{sign_a_for_current_partial, selected_half_a[15:0]}
{sign_b_for_current_partial, selected_half_b[15:0]}
```

MAC 中间结果必须使用有符号运算，并留出足够的保护位。建议组合临时结果至少使用 35 位，再明确截取并寄存所需的 34 位结果，禁止依赖 SystemVerilog 隐式位宽扩展。

---

## 7.3 推荐计算状态

推荐内部状态：

```text
ALBL
ALBH
AHBL
AHBH
RESPONSE
```

其中：

- `ALBL`：`A_L × B_L`
- `ALBH`：`A_L × B_H`
- `AHBL`：`A_H × B_L`
- `AHBH`：`A_H × B_H`

### MUL 路径

`MUL` 只需要低 32 位，因此：

1. `ALBL`
2. `ALBH`
3. `AHBL`
4. 形成低 32 位结果并进入 RESPONSE

`A_H × B_H` 从 bit 32 开始贡献，不影响低 32 位，因此 MUL 不执行 AHBH。

目标计算延迟：3 周期。

### MULH 类路径

高 32 位结果需要全部四个部分积：

1. `ALBL`
2. `ALBH`
3. `AHBL`
4. `AHBH`
5. 形成高 32 位结果并进入 RESPONSE

目标计算延迟：4 周期。

---

## 7.4 部分积累加要求

正式实现可以参考以下数学分解：

```text
A × B =
    A_L × B_L
  + (A_L × B_H << 16)
  + (A_H × B_L << 16)
  + (A_H × B_H << 32)
```

但 RTL 不应直接实例化四个并行乘法器。

每个状态只允许使用同一个 17×17 乘法核，并通过中间寄存器保留：

- 已确定的低 16 位；
- 尚需与后续部分积相加的中间高位；
- 有符号高分块产生的符号扩展。

建议正式实现 SPEC 进一步给出逐状态、逐 bit 的寄存器更新公式，并通过独立参考模型证明：

- 中间结果不丢失进位；
- `MULH` 负数符号扩展正确；
- `MULHSU` 仅 A 的高分块按有符号解释；
- `MULHU` 的所有分块均按无符号解释；
- `MUL` 的低 32 位不受高位符号解释影响。

Phase 2 可以参考 Ibex fast multi-cycle multiplier 的 ALBL/ALBH/AHBL/AHBH 组织，但不得未经理解直接复制；必须适配当前项目的握手、状态寄存器、编码风格和许可证管理要求。

---

## 7.5 Phase 2 时序风险

Phase 2 的预期主要组合路径为：

```text
半操作数选择
→ 17×17 有符号乘法
→ 34 位左右累加
→ 中间结果寄存器
```

该路径是否能满足 13.333 ns，必须以实际 55 nm SS 库和 Design Compiler 报告为准，不能仅根据其他开源核的周期数判断。

如果该路径不满足时序：

1. 不得通过 false path 或放宽约束掩盖；
2. 应检查是否因隐式位宽扩展生成了过宽加法器；
3. 应检查乘法器是否被错误推断为 32×32；
4. 应检查 MAC 后是否串联了结果选择、前递或大扇出控制；
5. 若仍不满足，应在正式修订 SPEC 中增加内部寄存级并接受更长延迟，而不是牺牲顶层 75 MHz。

---

## 8. 综合与时序验收

## 8.1 基本约束

目标时钟：

```text
75 MHz
period = 13.333 ns
```

验收必须使用：

- 目标 55 nm SS 标准单元库；
- 实际工作电压和温度对应库；
- 项目已有 clock uncertainty；
- 项目已有 input/output delay；
- SRAM 宏及其他黑盒的正确时序模型；
- 与现有顶层一致的最大转换时间、最大扇出等约束。

不得用 TT 库结果替代最终判断。

## 8.2 必须检查的路径

每个阶段至少检查：

1. 乘法器内部最差路径；
2. 请求输入到内部寄存器路径；
3. 响应寄存器到 EX/MEM 路径；
4. 普通 ALU 原有关键路径是否因结果 mux 扩大而恶化；
5. forwarding 路径是否意外串入乘法器组合逻辑；
6. kill、状态译码和计数器是否形成高扇出控制路径。

## 8.3 时序通过标准

在完整核层级、SS 库、13.333 ns 约束下：

```text
WNS >= 0
TNS = 0
```

同时不得存在：

- 未约束路径；
- 意外组合环；
- latch；
- 状态机不可达或 X 状态；
- 通过错误 multicycle path 例外掩盖真实单周期内部路径。

## 8.4 对比报告

Phase 1 和 Phase 2 均应保存：

- 总组合面积；
- 乘法器模块组合面积；
- 寄存器面积；
- WNS/TNS；
- 关键路径起点、终点和逻辑组成；
- 每条乘法指令的固定计算周期；
- 连续乘法指令的总执行周期；
- 乘法密集测试的总周期数。

Phase 2 合入前必须与 Phase 1 基线对比，而不是只检查功能通过。

---

## 9. 验证要求

## 9.1 独立模块级参考模型

参考模型必须生成完整 64 位乘积，再选择高低 32 位。

必须避免因宿主语言隐式类型转换导致错误。尤其检查：

- signed 32 × signed 32；
- signed 32 × unsigned 32；
- unsigned 32 × unsigned 32；
- 负数乘积转换为 64 位补码后的 bit slice。

Phase 1 和 Phase 2 必须使用同一套参考模型和测试向量。

## 9.2 定向测试

每条指令至少覆盖以下操作数的交叉组合：

```text
0x0000_0000
0x0000_0001
0xffff_ffff
0x7fff_ffff
0x8000_0000
0x8000_0001
0x0000_ffff
0x0001_0000
0xffff_0000
```

重点用例：

- `0 × X`
- `1 × X`
- `-1 × X`
- `INT_MIN × -1`
- `INT_MIN × INT_MIN`
- `INT_MAX × INT_MAX`
- `UINT_MAX × UINT_MAX`
- `MULHSU` 中 A 为负、B 大于 `INT_MAX`
- 部分积跨 16 位边界产生进位
- 低 32 位全零但高 32 位非零
- 高 32 位全 1 的负乘积

## 9.3 随机测试

每个操作码至少执行大量随机测试，建议不少于 10,000 组，并保证：

- 四种操作码分别统计；
- 全 32 位随机；
- 定向增加符号边界附近数据；
- Phase 1 和 Phase 2 结果逐项一致。

## 9.4 协议测试

必须覆盖：

- 空闲时请求握手；
- busy 时持续拉高 `req_vld`；
- 结果完成时下游立即 ready；
- `rsp_rdy` 长时间为 0；
- 响应等待期间结果稳定；
- RESPONSE 被接收后立即发起下一请求；
- PREPARE、每个 ITERATE 状态、FINAL、RESPONSE 中分别注入 kill；
- reset 发生在各状态；
- kill 后无幽灵响应；
- 同一 EX 指令不会重复请求。

## 9.5 处理器级测试

必须覆盖：

- 四条指令的指令级测试；
- 写回 `x0`；
- 乘法结果被下一条指令立即使用；
- back-to-back 乘法；
- 乘法前后出现 load/store；
- 乘法结果作为 store data；
- 乘法结果作为 load/store 地址；
- 乘法结果参与 branch 比较；
- 旧指令异常导致在途乘法被 kill；
- 分支 flush 与乘法请求边界；
- 中断到达乘法执行期间的既定策略。

## 9.6 建议断言

至少加入以下性质：

```text
rsp_vld && !rsp_rdy |=> rsp_vld && $stable(rsp_result)

busy |-> !req_rdy

req_fire |-> 当前请求只被接受一次

kill |=> !rsp_vld，直到新的 req_fire 后产生新结果

Phase 1 的 ITERATE 次数严格为 32

Phase 2：
MUL 只经过 ALBL/ALBH/AHBL
MULH 类必须经过 ALBL/ALBH/AHBL/AHBH
```

断言语法和放置位置由项目现有验证规范决定。

---

## 10. 分阶段完成标准

## 10.1 Phase 1 完成标准

只有同时满足以下条件，Phase 1 才视为完成：

- 四条乘法指令功能正确；
- 模块级定向、随机、协议测试通过；
- 处理器级依赖和 flush 测试通过；
- 固定 32 次迭代，无提前退出；
- 响应反压期间结果稳定；
- 无重复请求和幽灵写回；
- SS 75 MHz 顶层综合 `WNS >= 0`、`TNS = 0`；
- 保存面积和关键路径基线报告；
- Phase 1 实现可独立配置并持续回归。

## 10.2 Phase 2 完成标准

只有同时满足以下条件，Phase 2 才可替换默认实现：

- 复用 Phase 1 全部功能和协议测试；
- 与 Phase 1 进行随机等价对比；
- 单个 17×17 MAC，不得意外推断多个并行乘法器；
- `MUL` 达到目标 3 个计算周期；
- MULH 类达到目标 4 个计算周期；
- SS 75 MHz 顶层综合通过；
- 普通 ALU 和 forwarding 关键路径没有不可接受退化；
- 面积和性能相对 Phase 1 的变化已量化；
- Phase 1 仍保留为回退配置。

如果 17×17 MAC 无法在 SS 75 MHz 下满足时序，则性能周期目标让位于主频目标，进入新的 SPEC 修订，而不是强行合入。

---

## 11. 当前明确不做的内容

本 SPEC 不包含：

- `DIV/DIVU/REM/REMU`；
- Radix-4 或更高基数 Booth；
- 单周期 32×32 乘法器；
- 两级或多级满吞吐流水乘法器；
- 多请求在途；
- MULH+MUL 融合；
- 乘法提前退出；
- 多发射和乱序完成；
- scoreboard；
- 精细低功耗设计；
- DFT 与后端物理实现细节。

---

## 12. 交给后续 agent 补充的内容

后续正式 SPEC 必须结合实际核代码补充：

1. 乘法指令当前在 ID、EX、MEM、WB 各级携带的控制字段；
2. EX 级 vld/rdy 的实际端口和握手方程；
3. 如何保证同一乘法指令只请求一次；
4. 结果进入 EX/MEM 还是其他流水寄存器；
5. forwarding 的实际数据源和优先级；
6. branch、exception、interrupt、debug 对 kill 的实际映射；
7. 写回目的寄存器号由哪个流水级保存；
8. 乘法器 busy 是否冻结整个 EX 或仅冻结当前指令；
9. 精确的周期计数定义；
10. RTL 文件组织和参数选择方式；
11. VCS 测试入口、参考模型和回归命令；
12. Design Compiler 顶层、SS 库、约束文件和报告路径；
13. Phase 1 与 Phase 2 的模块级及顶层综合对比脚本。

---

## 13. 参考依据

- RISC-V International, **“M” Extension for Integer Multiplication and Division, Version 2.0**  
  https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html

- lowRISC Ibex Documentation, **Multiplier/Divider Block**  
  https://ibex-core.readthedocs.io/en/latest/03_reference/instruction_decode_execute.html

- lowRISC Ibex RTL, **ibex_multdiv_fast.sv**  
  https://github.com/lowRISC/ibex/blob/master/rtl/ibex_multdiv_fast.sv
