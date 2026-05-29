import os
import sys
import subprocess

# ==============================================================================
# 全局配置参数
# ==============================================================================
TARGET_FOLDERS = ['rv32i']
# TARGET_FOLDERS = ['rv32i', 'rv32im', 'rv32Zicsr', 'rv32Zifencei']
BASE_DIR = r'../../tests/rv_compliance'

def list_datafiles(path):
    files = []
    for maindir, subdir, all_file in os.walk(path):
        for filename in all_file:
            if filename.endswith('.data'):
                files.append(os.path.join(maindir, filename).replace('\\', '/'))
    return files

def main():
    all_data_files = []
    for folder in TARGET_FOLDERS:
        folder_path = os.path.join(BASE_DIR, folder)
        if os.path.exists(folder_path):
            all_data_files.extend(list_datafiles(folder_path))
        else:
            print(f"Warning: Directory {folder_path} does not exist.")

    total_count = len(all_data_files)
    if total_count == 0:
        print("No .data files found in the specified folders.")
        return

    print(f"Found {total_count} compliance tests in {TARGET_FOLDERS}. Starting batch run...")
    print(f"===========================================")

    fail_count = 0
    for file in all_data_files:
        # 运行单个 compliance 测试，该脚本会执行仿真并进行结果比对
        r = subprocess.check_output([sys.executable, 'rvcompliance_run_single.py', file], stderr=subprocess.STDOUT).decode('utf-8')
        
        if '[PASS]' in r:
            print(f"{os.path.basename(file):<30} [  PASS  ]")
        else:
            print(f"{os.path.basename(file):<30} [# FAIL #]")
            fail_count += 1

    print(f"\n===========================================")
    print(f"Compliance Test Summary: {total_count - fail_count}/{total_count} Passed")
    print(f"===========================================")
    
    if fail_count == 0:
        print('Congratulation, All PASS...')
    else:
        print(f'Done. {fail_count} tests failed.')

if __name__ == '__main__':
    sys.exit(main())
