import sys
import filecmp
import subprocess
import os


# 主函数
def main():
    vivado_proj_dirname = 'myRV_startup'
    rtl_dir = r'../../' + vivado_proj_dirname + r'/' + vivado_proj_dirname + r'.srcs'
    tb_file = r'/sim_1/tb_soc_top.v'     # 关于rtl_dir的相对路径
    #print(sys.argv[0] + ' ' + sys.argv[1] + ' ' + sys.argv[2])

    # 1.将bin文件转成mem文件
    cmd = r'python ../scripts/BinToMem_CLI.py' + ' ' + r'../tests/isa/generated/rv32ui-p-' + sys.argv[1] + '.bin' + ' ' + 'inst.data'
    f = os.popen(cmd)
    f.close()

    # 2.编译rtl文件
    cmd = r'python ../scripts/compile_rtl_auto.py' + ' ' + rtl_dir + ' ' + tb_file
    f = os.popen(cmd)
    f.close()

    # 3.运行
    vvp_cmd = [r'vvp']
    vvp_cmd.append(r'out.vvp')
    process = subprocess.Popen(vvp_cmd)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        print('!!!Fail, vvp exec timeout!!!')


if __name__ == '__main__':
    sys.exit(main())
