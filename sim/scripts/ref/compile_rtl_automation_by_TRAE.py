import sys
import subprocess
import os
import glob

def find_verilog_files(base_dir, subdirs):
    """在指定子目录中查找所有Verilog文件"""
    v_files = []
    for subdir in subdirs:
        pattern = os.path.join(base_dir, subdir, '*.v')
        files = glob.glob(pattern)
        # 转换为相对于base_dir的路径
        rel_paths = [os.path.relpath(f, base_dir) for f in files]
        v_files.extend(rel_paths)
    return v_files

def main():
    rtl_dir = sys.argv[1]
    
    # 确定测试平台文件
    if rtl_dir != r'..':
        tb_file = r'/tb/compliance_test/tinyriscv_soc_tb.v'
    else:
        tb_file = r'/tb/tinyriscv_soc_tb.v'

    # 定义要搜索的子目录
    search_dirs = [
        'rtl/core',
        'rtl/perips', 
        'rtl/debug',
        'rtl/soc',
        'rtl/utils'
    ]

    # 查找所有Verilog文件
    v_files = find_verilog_files(rtl_dir, search_dirs)

    # 初始化编译命令
    iverilog_cmd = ['iverilog']
    iverilog_cmd += ['-o', r'out.vvp']
    iverilog_cmd += ['-I', rtl_dir + r'/rtl/core']
    iverilog_cmd += ['-D', r'OUTPUT="signature.output"']
    
    # 添加测试平台文件
    iverilog_cmd.append(rtl_dir + tb_file)
    
    # 添加所有找到的Verilog文件
    for v_file in v_files:
        iverilog_cmd.append(os.path.join(rtl_dir, v_file))

    # 编译
    process = subprocess.Popen(iverilog_cmd)
    process.wait(timeout=5)

if __name__ == '__main__':
    sys.exit(main())
