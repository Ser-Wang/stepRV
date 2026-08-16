# 手工笔记

## wire load model 线负载模型
当前.db里缺少线负载模型
link的.db包括：
scc55ulp_hdlp_rvt_ss_v1p08_125c_ccs.db
smic55_4096x32_1rw_ss_1.08_125.db
smic55_8192x32_2p_ss_1.08_125.db

影响：
影响不止 timing report 里 net delay 为 0。没有 WLM 时，综合阶段等于缺少 pre-layout interconnect 估算，主要影响这些地方：

1. **cell delay 也会偏乐观**
   连线电容没有被加到 net 上，driver 看到的负载主要是下一级 pin cap。输出负载偏小后，cell arc delay 会变小，transition/slew 也会更好看。

2. **max transition / slew 检查偏乐观**
   因为 wire cap 不存在，很多本来可能 slew 变慢的 net 不会暴露。综合器也就不会为了修 transition 去插 buffer 或换大驱动。

3. **buffer 插入和 gate sizing 会偏少**
   DC 优化时认为连线负载很轻，就可能少插 buffer、少 upsize cell。后端真实布线后，长线和大 fanout net 可能突然变慢。

4. **面积报告没有 net interconnect area**
   你已经看到：
   ```text
   Net Interconnect area: undefined (No wire load specified)
   Total area: undefined
   ```
   cell area 还能看，但 total area 不完整。

5. **功耗估算偏低，尤其 dynamic power**
   线电容不计入或严重低估，开关电容变小，所以 net switching power 会偏低。cell internal/switching 也可能因为负载偏小而偏乐观。

6. **SDF 反标不包含有效 interconnect delay**
   当前 SDF 里 `INTERCONNECT` 都是 0。用这个 SDF 做门级仿真，只能反映 cell delay，不能反映综合估算的线延时。

7. **综合 QoR 和后端 QoR 差异会更大**
   综合看到的关键路径可能不是后端真实关键路径。后端布局布线后，长跨区路径、高扇出控制信号、总线 mux 相关路径更容易冒出来。

8. **hold 分析也不完整**
   setup 通常偏乐观更明显，但 hold 也会受影响。没有线延时时，有些短路径可能看起来更短；不过真实 CTS/route 后 hold 主要还是要以后端 STA 为准。

9. **高 fanout net 的处理更粗糙**
   report 里有：
   ```text
   A fanout number of 1000 was used for high fanout net computations.
   ```
   但没有 WLM 时，fanout 对 wire length/cap 的建模能力很弱，DC 对 reset/enable/control 这类高扇出网的优化参考会更有限。

简单说：**没有 WLM 的综合 timing 是纯 cell-dominated 的早期估计，通常偏乐观；面积/功耗/transition/buffering 也都会少算 interconnect 的那部分。**  
如果后面要做 APR，最终还是以后端抽 SPEF 后的 STA 为准。