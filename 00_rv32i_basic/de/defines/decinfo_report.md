# DECINFO Macro Resolved Values Report

Source: `config.v`

---

## Common / GRP Segment

| # | Macro Name | Expression | Value |
|---|-----------|------------|-------|
| 1 | `DECINFO_GRP_WIDTH` | `3` | **3** |
| 2 | `DECINFO_GRP_ALU` | ``DECINFO_GRP_WIDTH'd0` | **0** |
| 3 | `DECINFO_GRP_LSU` | ``DECINFO_GRP_WIDTH'd1` | **1** |
| 4 | `DECINFO_GRP_BRU` | ``DECINFO_GRP_WIDTH'd2` | **2** |
| 5 | `DECINFO_GRP_CSR` | ``DECINFO_GRP_WIDTH'd3` | **3** |
| 6 | `DECINFO_GRP_LSB` | `0` | **0** |
| 7 | `DECINFO_GRP_MSB` | `(`DECINFO_GRP_LSB + `DECINFO_GRP_WIDTH -1)` | **2** |
| 8 | `DECINFO_SUBDECINFO_LSB` | `(`DECINFO_GRP_MSB +1)` | **3** |

**Bit-field Ranges:**

| Field | Bit Range [MSB:LSB] | Width |
|-------|--------------------:|------:|
| `DECINFO_GRP` | [2:0] | 3 |

---

## ALU Group

| # | Macro Name | Expression | Value |
|---|-----------|------------|-------|
| 1 | `DECINFO_ALU_ADD_LSB` | ``DECINFO_SUBDECINFO_LSB` | **3** |
| 2 | `DECINFO_ALU_ADD_MSB` | `(`DECINFO_ALU_ADD_LSB+1-1)` | **3** |
| 3 | `DECINFO_ALU_SUB_LSB` | `(`DECINFO_ALU_ADD_MSB+1)` | **4** |
| 4 | `DECINFO_ALU_SUB_MSB` | `(`DECINFO_ALU_SUB_LSB+1-1)` | **4** |
| 5 | `DECINFO_ALU_SLL_LSB` | `(`DECINFO_ALU_SUB_MSB+1)` | **5** |
| 6 | `DECINFO_ALU_SLL_MSB` | `(`DECINFO_ALU_SLL_LSB+1-1)` | **5** |
| 7 | `DECINFO_ALU_SLT_LSB` | `(`DECINFO_ALU_SLL_MSB+1)` | **6** |
| 8 | `DECINFO_ALU_SLT_MSB` | `(`DECINFO_ALU_SLT_LSB+1-1)` | **6** |
| 9 | `DECINFO_ALU_SLTU_LSB` | `(`DECINFO_ALU_SLT_MSB+1)` | **7** |
| 10 | `DECINFO_ALU_SLTU_MSB` | `(`DECINFO_ALU_SLTU_LSB+1-1)` | **7** |
| 11 | `DECINFO_ALU_XOR_LSB` | `(`DECINFO_ALU_SLTU_MSB+1)` | **8** |
| 12 | `DECINFO_ALU_XOR_MSB` | `(`DECINFO_ALU_XOR_LSB+1-1)` | **8** |
| 13 | `DECINFO_ALU_SRL_LSB` | `(`DECINFO_ALU_XOR_MSB+1)` | **9** |
| 14 | `DECINFO_ALU_SRL_MSB` | `(`DECINFO_ALU_SRL_LSB+1-1)` | **9** |
| 15 | `DECINFO_ALU_SRA_LSB` | `(`DECINFO_ALU_SRL_MSB+1)` | **10** |
| 16 | `DECINFO_ALU_SRA_MSB` | `(`DECINFO_ALU_SRA_LSB+1-1)` | **10** |
| 17 | `DECINFO_ALU_OR_LSB` | `(`DECINFO_ALU_SRA_MSB+1)` | **11** |
| 18 | `DECINFO_ALU_OR_MSB` | `(`DECINFO_ALU_OR_LSB+1-1)` | **11** |
| 19 | `DECINFO_ALU_AND_LSB` | `(`DECINFO_ALU_OR_MSB+1)` | **12** |
| 20 | `DECINFO_ALU_AND_MSB` | `(`DECINFO_ALU_AND_LSB+1-1)` | **12** |
| 21 | `DECINFO_ALU_LUI_LSB` | `(`DECINFO_ALU_AND_MSB+1)` | **13** |
| 22 | `DECINFO_ALU_LUI_MSB` | `(`DECINFO_ALU_LUI_LSB+1-1)` | **13** |
| 23 | `DECINFO_ALU_OP1PC_LSB` | `(`DECINFO_ALU_LUI_MSB+1)` | **14** |
| 24 | `DECINFO_ALU_OP1PC_MSB` | `(`DECINFO_ALU_OP1PC_LSB+1-1)` | **14** |
| 25 | `DECINFO_ALU_OP2IMM_LSB` | `(`DECINFO_ALU_OP1PC_MSB+1)` | **15** |
| 26 | `DECINFO_ALU_OP2IMM_MSB` | `(`DECINFO_ALU_OP2IMM_LSB+1-1)` | **15** |
| 27 | `DECINFO_BUS_ALU_WIDTH` | `(`DECINFO_ALU_OP2IMM_MSB+1)` | **16** |

**Bit-field Ranges:**

| Field | Bit Range [MSB:LSB] | Width |
|-------|--------------------:|------:|
| `DECINFO_ALU_ADD` | [3:3] | 1 |
| `DECINFO_ALU_SUB` | [4:4] | 1 |
| `DECINFO_ALU_SLL` | [5:5] | 1 |
| `DECINFO_ALU_SLT` | [6:6] | 1 |
| `DECINFO_ALU_SLTU` | [7:7] | 1 |
| `DECINFO_ALU_XOR` | [8:8] | 1 |
| `DECINFO_ALU_SRL` | [9:9] | 1 |
| `DECINFO_ALU_SRA` | [10:10] | 1 |
| `DECINFO_ALU_OR` | [11:11] | 1 |
| `DECINFO_ALU_AND` | [12:12] | 1 |
| `DECINFO_ALU_LUI` | [13:13] | 1 |
| `DECINFO_ALU_OP1PC` | [14:14] | 1 |
| `DECINFO_ALU_OP2IMM` | [15:15] | 1 |

---

## LSU Group

| # | Macro Name | Expression | Value |
|---|-----------|------------|-------|
| 1 | `DECINFO_LSU_LOAD_LSB` | ``DECINFO_SUBDECINFO_LSB` | **3** |
| 2 | `DECINFO_LSU_LOAD_MSB` | `(`DECINFO_LSU_LOAD_LSB+1-1)` | **3** |
| 3 | `DECINFO_LSU_STORE_LSB` | `(`DECINFO_LSU_LOAD_MSB+1)` | **4** |
| 4 | `DECINFO_LSU_STORE_MSB` | `(`DECINFO_LSU_STORE_LSB+1-1)` | **4** |
| 5 | `DECINFO_LSU_SIZE_LSB` | `(`DECINFO_LSU_STORE_MSB+1)` | **5** |
| 6 | `DECINFO_LSU_SIZE_MSB` | `(`DECINFO_LSU_SIZE_LSB+2-1)` | **6** |
| 7 | `DECINFO_LSU_USIGN_LSB` | `(`DECINFO_LSU_SIZE_MSB+1)` | **7** |
| 8 | `DECINFO_LSU_USIGN_MSB` | `(`DECINFO_LSU_USIGN_LSB+1-1)` | **7** |
| 9 | `DECINFO_LSU_OP2IMM_LSB` | `(`DECINFO_LSU_USIGN_MSB+1)` | **8** |
| 10 | `DECINFO_LSU_OP2IMM_MSB` | `(`DECINFO_LSU_OP2IMM_LSB+1-1)` | **8** |
| 11 | `DECINFO_BUS_LSU_WIDTH` | `(`DECINFO_LSU_OP2IMM_MSB+1)` | **9** |

**Bit-field Ranges:**

| Field | Bit Range [MSB:LSB] | Width |
|-------|--------------------:|------:|
| `DECINFO_LSU_LOAD` | [3:3] | 1 |
| `DECINFO_LSU_STORE` | [4:4] | 1 |
| `DECINFO_LSU_SIZE` | [6:5] | 2 |
| `DECINFO_LSU_USIGN` | [7:7] | 1 |
| `DECINFO_LSU_OP2IMM` | [8:8] | 1 |

---

## BRU Group

| # | Macro Name | Expression | Value |
|---|-----------|------------|-------|
| 1 | `DECINFO_BRU_JAL_LSB` | ``DECINFO_SUBDECINFO_LSB` | **3** |
| 2 | `DECINFO_BRU_JAL_MSB` | `(`DECINFO_BRU_JAL_LSB+1-1)` | **3** |
| 3 | `DECINFO_BRU_JALR_LSB` | `(`DECINFO_BRU_JAL_MSB+1)` | **4** |
| 4 | `DECINFO_BRU_JALR_MSB` | `(`DECINFO_BRU_JALR_LSB+1-1)` | **4** |
| 5 | `DECINFO_BRU_JUMP_LSB` | `(`DECINFO_BRU_JALR_MSB+1)` | **5** |
| 6 | `DECINFO_BRU_JUMP_MSB` | `(`DECINFO_BRU_JUMP_LSB+1-1)` | **5** |
| 7 | `DECINFO_BRU_BEQ_LSB` | `(`DECINFO_BRU_JUMP_MSB+1)` | **6** |
| 8 | `DECINFO_BRU_BEQ_MSB` | `(`DECINFO_BRU_BEQ_LSB+1-1)` | **6** |
| 9 | `DECINFO_BRU_BNE_LSB` | `(`DECINFO_BRU_BEQ_MSB+1)` | **7** |
| 10 | `DECINFO_BRU_BNE_MSB` | `(`DECINFO_BRU_BNE_LSB+1-1)` | **7** |
| 11 | `DECINFO_BRU_BLT_LSB` | `(`DECINFO_BRU_BNE_MSB+1)` | **8** |
| 12 | `DECINFO_BRU_BLT_MSB` | `(`DECINFO_BRU_BLT_LSB+1-1)` | **8** |
| 13 | `DECINFO_BRU_BGE_LSB` | `(`DECINFO_BRU_BLT_MSB+1)` | **9** |
| 14 | `DECINFO_BRU_BGE_MSB` | `(`DECINFO_BRU_BGE_LSB+1-1)` | **9** |
| 15 | `DECINFO_BRU_BLTU_LSB` | `(`DECINFO_BRU_BGE_MSB+1)` | **10** |
| 16 | `DECINFO_BRU_BLTU_MSB` | `(`DECINFO_BRU_BLTU_LSB+1-1)` | **10** |
| 17 | `DECINFO_BRU_BGEU_LSB` | `(`DECINFO_BRU_BLTU_MSB+1)` | **11** |
| 18 | `DECINFO_BRU_BGEU_MSB` | `(`DECINFO_BRU_BGEU_LSB+1-1)` | **11** |
| 19 | `DECINFO_BRU_BXX_LSB` | `(`DECINFO_BRU_BGEU_MSB+1)` | **12** |
| 20 | `DECINFO_BRU_BXX_MSB` | `(`DECINFO_BRU_BXX_LSB+1-1)` | **12** |
| 21 | `DECINFO_BRU_FENCE_LSB` | `(`DECINFO_BRU_BXX_MSB+1)` | **13** |
| 22 | `DECINFO_BRU_FENCE_MSB` | `(`DECINFO_BRU_FENCE_LSB+1-1)` | **13** |
| 23 | `DECINFO_BRU_FENCEI_LSB` | `(`DECINFO_BRU_FENCE_MSB+1)` | **14** |
| 24 | `DECINFO_BRU_FENCEI_MSB` | `(`DECINFO_BRU_FENCEI_LSB+1-1)` | **14** |
| 25 | `DECINFO_BUS_BRU_WIDTH` | `(`DECINFO_BRU_FENCEI_MSB+1)` | **15** |

**Bit-field Ranges:**

| Field | Bit Range [MSB:LSB] | Width |
|-------|--------------------:|------:|
| `DECINFO_BRU_JAL` | [3:3] | 1 |
| `DECINFO_BRU_JALR` | [4:4] | 1 |
| `DECINFO_BRU_JUMP` | [5:5] | 1 |
| `DECINFO_BRU_BEQ` | [6:6] | 1 |
| `DECINFO_BRU_BNE` | [7:7] | 1 |
| `DECINFO_BRU_BLT` | [8:8] | 1 |
| `DECINFO_BRU_BGE` | [9:9] | 1 |
| `DECINFO_BRU_BLTU` | [10:10] | 1 |
| `DECINFO_BRU_BGEU` | [11:11] | 1 |
| `DECINFO_BRU_BXX` | [12:12] | 1 |
| `DECINFO_BRU_FENCE` | [13:13] | 1 |
| `DECINFO_BRU_FENCEI` | [14:14] | 1 |

---

## CSR Group

| # | Macro Name | Expression | Value |
|---|-----------|------------|-------|
| 1 | `DECINFO_CSR_CSRRW_LSB` | ``DECINFO_SUBDECINFO_LSB` | **3** |
| 2 | `DECINFO_CSR_CSRRW_MSB` | `(`DECINFO_CSR_CSRRW_LSB+1-1)` | **3** |
| 3 | `DECINFO_CSR_CSRRS_LSB` | `(`DECINFO_CSR_CSRRW_MSB+1)` | **4** |
| 4 | `DECINFO_CSR_CSRRS_MSB` | `(`DECINFO_CSR_CSRRS_LSB+1-1)` | **4** |
| 5 | `DECINFO_CSR_CSRRC_LSB` | `(`DECINFO_CSR_CSRRS_MSB+1)` | **5** |
| 6 | `DECINFO_CSR_CSRRC_MSB` | `(`DECINFO_CSR_CSRRC_LSB+1-1)` | **5** |
| 7 | `DECINFO_CSR_RS1IMM_LSB` | `(`DECINFO_CSR_CSRRC_MSB+1)` | **6** |
| 8 | `DECINFO_CSR_RS1IMM_MSB` | `(`DECINFO_CSR_RS1IMM_LSB+1-1)` | **6** |
| 9 | `DECINFO_CSR_ZIMM_LSB` | `(`DECINFO_CSR_RS1IMM_MSB+1)` | **7** |
| 10 | `DECINFO_CSR_ZIMM_MSB` | `(`DECINFO_CSR_ZIMM_LSB+5-1)` | **11** |
| 11 | `DECINFO_CSR_RS1X0_LSB` | `(`DECINFO_CSR_ZIMM_MSB+1)` | **12** |
| 12 | `DECINFO_CSR_RS1X0_MSB` | `(`DECINFO_CSR_RS1X0_LSB+1-1)` | **12** |
| 13 | `DECINFO_CSR_CSRIDX_LSB` | `(`DECINFO_CSR_RS1X0_MSB+1)` | **13** |
| 14 | `DECINFO_CSR_CSRIDX_MSB` | `(`DECINFO_CSR_CSRIDX_LSB+12-1)` | **24** |
| 15 | `DECINFO_BUS_CSR_WIDTH` | `(`DECINFO_CSR_CSRIDX_MSB+1)` | **25** |

**Bit-field Ranges:**

| Field | Bit Range [MSB:LSB] | Width |
|-------|--------------------:|------:|
| `DECINFO_CSR_CSRRW` | [3:3] | 1 |
| `DECINFO_CSR_CSRRS` | [4:4] | 1 |
| `DECINFO_CSR_CSRRC` | [5:5] | 1 |
| `DECINFO_CSR_RS1IMM` | [6:6] | 1 |
| `DECINFO_CSR_ZIMM` | [11:7] | 5 |
| `DECINFO_CSR_RS1X0` | [12:12] | 1 |
| `DECINFO_CSR_CSRIDX` | [24:13] | 12 |

---

## Total Bus Width

| # | Macro Name | Expression | Value |
|---|-----------|------------|-------|
| 1 | `DECINFO_BUS_WIDTH` | ``DECINFO_BUS_CSR_WIDTH` | **25** |

---

## Summary: Sub-bus Widths

| Sub-bus | Width Macro | Total Bits |
|---------|-----------|:----------:|
| ALU | `DECINFO_BUS_ALU_WIDTH` | **16** |
| LSU | `DECINFO_BUS_LSU_WIDTH` | **9** |
| BRU | `DECINFO_BUS_BRU_WIDTH` | **15** |
| CSR | `DECINFO_BUS_CSR_WIDTH` | **25** |
| **TOTAL** | `DECINFO_BUS_WIDTH` | **25** |

