import sys
import filecmp
import subprocess
import os


# 主函数
def main():
    # 配置 RTL 版本 (可通过改变此处变量，测试不同版本的核心代码)
    rtl_version = 'v0_rv32i_basic'
    print(f"===========================================")
    print(f"--- Running Test on RTL: {rtl_version} ---")
    print(f"===========================================")
    # 配置 GTKWave 是否打开
    OPEN_GTKWAVE = False # or True

    rtl_dir = f'../de_rtl/{rtl_version}'
    tb_file = r'../dv_tb/tb_soc_top.v'
    filelist_f = r'filelist.f'

    # 1.将bin文件转成mem文件 (输出在当前运行目录)
    cmd1 = r'python scripts/BinToMem_CLI.py' + ' ' + r'../tests/isa/generated/rv32ui-p-' + sys.argv[1] + '.bin' + ' ' + './inst.data'
    os.system(cmd1)
    # f = os.popen(cmd1)
    # f.close()

    # 1.5 生成filelist.f
    cmd_gen = r'python scripts/gen_filelist.py' + ' ' + rtl_dir + ' ' + tb_file + ' ' + filelist_f
    os.system(cmd_gen)
    # f = os.popen(cmd_gen)
    # f.close()

    # 2.编译rtl文件
    cmd = r'python scripts/compile_rtl.py' + ' ' + filelist_f
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
        gtkw_cmd = r'gtkwave' + ' ' + r'tb_soc_top.vcd'
        os.system(gtkw_cmd)
        # f = os.popen(gtkw_cmd)
        # f.close()


if __name__ == '__main__':
    sys.exit(main())
