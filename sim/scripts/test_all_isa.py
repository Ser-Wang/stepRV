import os
import subprocess
import sys


# 找出path目录下的所有bin文件
def list_binfiles(path):
    files = []
    list_dir = os.walk(path)
    for maindir, subdir, all_file in list_dir:
        for filename in all_file:
            apath = os.path.join(maindir, filename)
            if apath.endswith('.bin'):
                files.append(apath)

    return files

# 主函数
def main():
    bin_files = list_binfiles(r'../tests/isa/generated')

    anyfail = False
    fail_count = 0
    total_count = len(bin_files)

    # 对每一个bin文件进行测试
    for file in bin_files:
        # print(f"Testing {file}...")
        # 相应于 sim_new_nowave.py 在本环境中是 scripts/test_single.py
        cmd = r'python scripts/test_single.py' + ' ' + file
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
