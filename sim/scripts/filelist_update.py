import os
import sys

def main():
    # 配置目标测试版本
    rtl_version = 'v0_rv32i_basic'
    
    # 定义传给 gen_filelist.py 的三个参数
    rtl_dir = f'../de_rtl/{rtl_version}'
    tb_file = r'../dv_tb/tb_soc_top.v'
    output_file = r'filelist.f'
    
    # 获取当前脚本运行目录，保证无论是从 sim/ 还是从 sim/scripts/ 执行都能找到正确的相对路径
    # 由于我们需要基于 sim/ 目录生成 filelist，如果从 scripts 目录调用，我们会先退回 sim 目录
    cwd = os.getcwd()
    if os.path.basename(cwd) == 'scripts':
        os.chdir('..')

    print(f"Updating filelist for {rtl_version}...")
    
    # 调用 gen_filelist.py 并传入参数
    cmd = f'python scripts/gen_filelist.py {rtl_dir} {tb_file} {output_file}'
    os.system(cmd)

if __name__ == '__main__':
    sys.exit(main())
