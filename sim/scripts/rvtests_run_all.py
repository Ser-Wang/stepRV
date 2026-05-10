import os
import subprocess
import sys

# ==============================================================================
# 全局配置参数
# ==============================================================================
# 在这里配置你需要批量测试的指令集前缀名称（相当于 compliance 的文件夹分类）
# 可选的包括 'rv32ui', 'rv32um', 'rv32uc', 'rv32ua' 等
TARGET_CATEGORIES = ['rv32ui']
# TARGET_CATEGORIES = ['rv32ui', 'rv32um']

# 基础测试目录
BASE_DIR = r'../tests/isa/generated'


# 找出path目录下的所有bin文件
def list_binfiles(path, target_categories):
    files = []
    list_dir = os.walk(path)
    for maindir, subdir, all_file in list_dir:
        for filename in all_file:
            apath = os.path.join(maindir, filename)
            if apath.endswith('.bin'):
                # 检查文件名是否以指定的分类前缀开头
                if any(filename.startswith(prefix) for prefix in target_categories):
                    files.append(apath.replace('\\', '/'))

    return files

# 主函数
def main():
    bin_files = list_binfiles(BASE_DIR, TARGET_CATEGORIES)

    anyfail = False
    fail_count = 0
    total_count = len(bin_files)
    
    if total_count == 0:
        print("No test files found in the specified categories.")
        return

    print(f"Found {total_count} tests in {TARGET_CATEGORIES}. Starting batch run...")
    print(f"===========================================")

    # 对每一个bin文件进行测试
    for file in bin_files:
        # print(f"Testing {file}...")
        cmd = r'python scripts/rvtests_run_single.py' + ' ' + file
        f = os.popen(cmd)
        r = f.read()
        f.close()
        
        if (r.find('TEST_PASS') != -1):
            print(os.path.basename(file) + '    PASS')
        else:
            print(os.path.basename(file) + '    !!!FAIL!!!')
            anyfail = True
            fail_count += 1
            # break # 注释掉 break 以便观察所有测试结果

    print(f"\n===========================================")
    print(f"Test Summary: {total_count - fail_count}/{total_count} Passed")
    print(f"===========================================")
    
    if not anyfail:
        print('Congratulation, All PASS...')
    else:
        print(f'Done. {fail_count} tests failed.')


if __name__ == '__main__':
    sys.exit(main())
