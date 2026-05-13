import sys
import subprocess
import os

def main():
    # 从命令行参数获取 filelist 路径，如果没有提供则默认使用当前目录下的 filelist.f
    if len(sys.argv) > 1:
        filelist_path = sys.argv[1]
    else:
        filelist_path = r'filelist.f'

    # 初始化编译命令
    iverilog_cmd = ['iverilog']
    iverilog_cmd += ['-o', r'out.vvp']
    iverilog_cmd += ['-g2012']
    iverilog_cmd += ['-D', 'IVERILOG']
    # iverilog_cmd += ['-I', rtl_dir + r'/sources_1/defines']
    iverilog_cmd += ['-D', r'OUTPUT="signature.output"']
    
    # 采用 -c 读取所有源文件和 include 路径
    iverilog_cmd += ['-c', filelist_path]

    # 编译
    print(f"Running iverilog with {filelist_path} ...")
    process = subprocess.Popen(iverilog_cmd)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        print('!!!Fail, iverilog exec timeout!!!')

if __name__ == '__main__':
    sys.exit(main())
