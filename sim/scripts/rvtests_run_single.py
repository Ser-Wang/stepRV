import sys
import filecmp
import subprocess
import os

# ==============================================================================
# 全局配置参数
# ==============================================================================
# 配置 RTL 版本 (可通过改变此处变量，测试不同版本的核心代码)
RTL_VERSION = 'v0_rv32i_basic'

# 目录与文件路径配置
RTL_DIR    = f'../de_rtl/{RTL_VERSION}'
TB_FILE    = r'../dv_tb/tb_soc_top.sv'
FILELIST_F = r'filelist.f'
TESTS_BASE_DIR = r'../tests/isa/generated'

# 配置 GTKWave 是否打开
OPEN_GTKWAVE = False # False or True


# 主函数
def main():
    print(f"===========================================")
    print(f"--- Running Test on RTL: {RTL_VERSION} ---")
    print(f"===========================================")

    # 1.将bin文件转成mem文件 (输出在当前运行目录)
    # 支持传入完整路径或仅指令名
    if len(sys.argv) < 2:
        print("Usage: python test_single.py <inst_name_or_bin_path>")
        return
        
    bin_file = sys.argv[1]
    if not bin_file.endswith('.bin'):
        bin_file = f"{TESTS_BASE_DIR}/rv32ui-p-{bin_file}.bin"
        
    cmd1 = r'python scripts/BinToMem_CLI.py' + ' ' + bin_file + ' ' + './inst.data'
    os.system(cmd1)
    # f = os.popen(cmd1)
    # f.close()

    # 1.5 生成filelist.f
    cmd_gen = r'python scripts/gen_filelist.py' + ' ' + RTL_DIR + ' ' + TB_FILE + ' ' + FILELIST_F
    os.system(cmd_gen)
    # f = os.popen(cmd_gen)
    # f.close()

    # 2.编译rtl文件
    cmd = r'python scripts/compile_rtl.py' + ' ' + FILELIST_F
    os.system(cmd)
    # f = os.popen(cmd)
    # f.close()

    # 3.运行
    vvp_cmd = [r'vvp']
    vvp_cmd.append(r'out.vvp')
    process = subprocess.Popen(vvp_cmd)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        print('!!!Fail, vvp exec timeout!!!')

    # 4.查看波形
    if OPEN_GTKWAVE:
        # gtkw_cmd = r'gtkwave' + ' ' + r'tb_soc_top.vcd'
        gtkw_cmd = r'gtkwave' + ' ' + r'tb_soc_top.vcd' + ' ' + r'top_core_behav.gtkw'
        os.system(gtkw_cmd)
        # f = os.popen(gtkw_cmd)
        # f.close()


if __name__ == '__main__':
    sys.exit(main())
