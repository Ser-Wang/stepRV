import os
import sys

# ==============================================================================
# 全局配置参数
# ==============================================================================
# 在这里配置你需要批量测试的文件夹名称
# 可选的包括 'rv32i', 'rv32im', 'rv32Zicsr', 'rv32Zifencei' 等
TARGET_FOLDERS = ['rv32i']
# TARGET_FOLDERS = ['rv32i', 'rv32im']

# 测试文件基础目录
BASE_DIR = r'../tests/riscv-compliance/build_generated'


# 找出指定path目录下的所有测试 bin 文件
def list_binfiles(path):
    files = []
    list_dir = os.walk(path)
    for maindir, subdir, all_file in list_dir:
        for filename in all_file:
            apath = os.path.join(maindir, filename)
            # compliance测试文件通常以 .elf.bin 结尾
            if apath.endswith('.elf.bin'):
                files.append(apath.replace('\\', '/'))
    return files

def main():
    all_bin_files = []
    
    for folder in TARGET_FOLDERS:
        folder_path = os.path.join(BASE_DIR, folder)
        if os.path.exists(folder_path):
            all_bin_files.extend(list_binfiles(folder_path))
        else:
            print(f"Warning: Directory {folder_path} does not exist.")

    anyfail = False
    fail_count = 0
    total_count = len(all_bin_files)
    
    if total_count == 0:
        print("No test files found in the specified folders.")
        return

    print(f"Found {total_count} tests in {TARGET_FOLDERS}. Starting batch run...")
    print(f"===========================================")

    for file in all_bin_files:
        # 运行单个compliance测试
        cmd = r'python scripts/rvcompliance_run_single.py' + ' ' + file
        f = os.popen(cmd)
        r = f.read()
        f.close()
        
        # rvcompliance_run_single.py 在成功比对后会打印 ### PASS ###
        if r.find('### PASS ###') != -1:
            print(os.path.basename(file) + '    PASS')
        else:
            print(os.path.basename(file) + '    !!!FAIL!!!')
            anyfail = True
            fail_count += 1

    print(f"\n===========================================")
    print(f"Compliance Test Summary: {total_count - fail_count}/{total_count} Passed")
    print(f"===========================================")
    
    if not anyfail:
        print('Congratulation, All PASS...')
    else:
        print(f'Done. {fail_count} tests failed.')

if __name__ == '__main__':
    sys.exit(main())
