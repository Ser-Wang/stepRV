# commonSpec_devflow_dv
在对rtl进行修改后，统一最小验收标准为：

在work/my-RISCV-Projs/sim路径运行下述测试：
```
make sim_isa_all type=isa group=rv32ui
make sim_isa_all type=compli group=rv32i
make sim_isa_all type=compli group=rv32Zicsr
make sim_isa_all type=compli group=rv32Zifencei
```

除type=isa group=rv32ui的测试中，有名为`ma_data`的用例是FAIL，其他都应PASS


对于M扩展指令，在work/my-RISCV-Projs/sim路径运行下述测试：
```
make sim_isa_all type=isa group=rv32um
make sim_isa_all type=compli group=rv32im
```