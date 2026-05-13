import os
import subprocess
import sys

# ==============================================================================
# 全局配置参数
# ==============================================================================
# 批量测试的指令集分类
TARGET_CATEGORIES = ['rv32ui']
# TARGET_CATEGORIES = ['rv32ui', 'rv32um']

# 基础测试目录
BASE_DIR = r'../../tests/rv_tests_isa'
COMPLIANCE_DIR = r'../../tests/rv_compilance'

# 找出 path 目录下的所有 .data 文件
def list_datafiles(path, target_categories):
    files = []
    for maindir, subdir, all_file in os.walk(path):
        for filename in all_file:
            if filename.endswith('.data'):
                # 检查文件名是否以指定的分类前缀开头
                if any(filename.startswith(prefix) for prefix in target_categories):
                    apath = os.path.join(maindir, filename).replace('\\', '/')
                    files.append(apath)
    return files

def main():
    data_files = list_datafiles(BASE_DIR, TARGET_CATEGORIES)

    anyfail = False
    fail_count = 0
    total_count = len(data_files)
    
    if total_count == 0:
        print(f"No .data files found in categories {TARGET_CATEGORIES}.")
        return

    print(f"Found {total_count} tests in {TARGET_CATEGORIES}. Starting batch run...")
    print(f"===========================================")

    for file in data_files:
        cmd = r'python rvtests_run_single.py' + ' ' + file
        # 使用 check_output 或 popen 获取结果
        r = subprocess.check_output([sys.executable, 'rvtests_run_single.py', file], stderr=subprocess.STDOUT).decode('utf-8')
        
        if '[PASS]' in r:
            print(f"{os.path.basename(file):<30} [  PASS  ]")
        else:
            print(f"{os.path.basename(file):<30} [# FAIL #]")
            anyfail = True
            fail_count += 1

    print(f"\n===========================================")
    print(f"Test Summary: {total_count - fail_count}/{total_count} Passed")
    print(f"===========================================")
    
    if not anyfail:
        print('Congratulation, All PASS...')
    else:
        print(f'Done. {fail_count} tests failed.')

if __name__ == '__main__':
    sys.exit(main())
