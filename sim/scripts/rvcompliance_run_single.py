"""
使用命令示例:
1. 通过测试名称直接运行 (推荐):
   python scripts/rvcompliance_run_single.py I-ADDI-01

2. 通过二进制文件完整路径运行:
   python scripts/rvcompliance_run_single.py ../tests/riscv-compliance/build_generated/rv32i/I-ADDI-01.elf.bin
"""

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
TB_FILE    = r'../dv_tb/tb_soctop_rvcompilance.v'
FILELIST_F = r'filelist.f'
TESTS_BASE_DIR   = r'../tests/riscv-compliance/build_generated'

# 当仅提供测试名称时，脚本会在以下分类文件夹中进行检索匹配
SEARCH_TARGET_FOLDERS = ['rv32i', 'rv32im', 'rv32Zicsr', 'rv32Zifencei']


# ==============================================================================
# 旧版基于遍历的搜索逻辑（已弃用，保留作对比参考）
# ==============================================================================
# def list_ref_files(path):
#     files = []
#     list_dir = os.walk(path)
#     for maindir, subdir, all_file in list_dir:
#         for filename in all_file:
#             apath = os.path.join(maindir, filename)
#             if apath.endswith('.reference_output'):
#                 files.append(apath)
#     return files
#
# def get_reference_file(bin_file):
#     file_path, file_name = os.path.split(bin_file)
#     tmp = file_name.split('.')
#     prefix = tmp[0]
#     files = []
#     if (bin_file.find('rv32im') != -1):
#         files = list_ref_files(r'../tests/riscv-compliance/riscv-test-suite/rv32im/references')
#     elif (bin_file.find('rv32i') != -1):
#         files = list_ref_files(r'../tests/riscv-compliance/riscv-test-suite/rv32i/references')
#     elif (bin_file.find('rv32Zicsr') != -1):
#         files = list_ref_files(r'../tests/riscv-compliance/riscv-test-suite/rv32Zicsr/references')
#     elif (bin_file.find('rv32Zifencei') != -1):
#         files = list_ref_files(r'../tests/riscv-compliance/riscv-test-suite/rv32Zifencei/references')
#     else:
#         return None
#     for file in files:
#         if (file.find(prefix) != -1):
#             return file
#     return None



# ==============================================================================
# 新版基于 O(1) 的路径映射逻辑
# ==============================================================================
# 根据bin文件快速映射对应的reference_output文件
def get_reference_file(bin_file):
    # bin_file 示例: ../tests/riscv-compliance/build_generated/rv32i/I-ADD-01.elf.bin
    # ref_file 预期: ../tests/riscv-compliance/riscv-test-suite/rv32i/references/I-ADD-01.reference_output
    
    file_path, file_name = os.path.split(bin_file)
    prefix = file_name.split('.')[0]
    
    # 替换基础目录 build_generated -> riscv-test-suite
    ref_dir = file_path.replace('build_generated', 'riscv-test-suite')
    
    # 拼接 references 文件夹和标准答案文件名
    ref_file = os.path.join(ref_dir, 'references', f"{prefix}.reference_output").replace('\\', '/')
    
    if os.path.exists(ref_file):
        return ref_file
    return None

# 主函数
def main():
    print(f"===========================================")
    print(f"--- Running Test on RTL: {RTL_VERSION} ---")
    print(f"===========================================")

    if len(sys.argv) < 2:
        print("Usage: python scripts/rvcompliance_run_single.py <bin_file_path_or_test_name>")
        return

    bin_file = sys.argv[1]

    # 支持仅传入测试名称，自动拼接并检查可能存在的 bin 文件路径
    if not bin_file.endswith('.bin'):
        found = False
        for folder in SEARCH_TARGET_FOLDERS:
            possible_path = f"{TESTS_BASE_DIR}/{folder}/{bin_file}.elf.bin"
            if os.path.exists(possible_path):
                bin_file = possible_path
                found = True
                break
                
        if not found:
            print(f"Error: Could not find binary for test {sys.argv[1]}")
            return

    # 1.将bin文件转成mem文件 (输出在当前运行目录)
    cmd1 = r'python scripts/BinToMem_CLI.py' + ' ' + bin_file + ' ' + './inst.data'
    os.system(cmd1)

    # 1.5 生成filelist.f
    cmd_gen = r'python scripts/gen_filelist.py' + ' ' + RTL_DIR + ' ' + TB_FILE + ' ' + FILELIST_F
    os.system(cmd_gen)

    # 2.编译rtl文件
    cmd = r'python scripts/compile_rtl.py' + ' ' + FILELIST_F
    os.system(cmd)

    # 3.运行
    logfile = open('run.log', 'w')
    vvp_cmd = [r'vvp']
    vvp_cmd.append(r'out.vvp')
    process = subprocess.Popen(vvp_cmd, stdout=logfile, stderr=logfile)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        print('!!!Fail, vvp exec timeout!!!')
    logfile.close()

    # 4.比较结果
    ref_file = get_reference_file(bin_file)
    
    if ref_file is not None and os.path.exists(ref_file):
        # 如果文件大小不一致，直接报fail
        if (os.path.getsize('signature.output') != os.path.getsize(ref_file)):
            print('!!! FAIL, size != !!!')
            return
        f1 = open('signature.output')
        f2 = open(ref_file)
        f1_lines = f1.readlines()
        i = 0
        # 逐行比较
        for line in f2.readlines():
            # 只要有一行内容不一样就报fail
            if (f1_lines[i] != line):
                print('!!! FAIL, content != !!!')
                f1.close()
                f2.close()
                return
            i = i + 1
        f1.close()
        f2.close()
        print('### PASS ###')
    else:
        print('No ref file found, please check result by yourself.')

if __name__ == '__main__':
    sys.exit(main())
