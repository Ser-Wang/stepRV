import sys
import os
import shutil

# ==============================================================================
# 全局配置参数
# ==============================================================================
# 配置 RTL 版本 (可通过改变此处变量，测试不同版本的核心代码)
RTL_VERSION = 'v0_rv32i_basic'

# 目录与文件路径配置
RTL_DIR    = f'../../de_rtl/{RTL_VERSION}'
TB_FILE    = r'../../dv_tb/tb_soctop_rvtests.sv'
FILELIST_F = r'filelist.f'
TESTS_BASE_DIR = r'../../tests/rv_tests_isa'

# 主函数
def main():
    print(f"===========================================")
    print(f"--- Running Test on RTL: {RTL_VERSION} ---")
    print(f"===========================================")

    # 支持传入完整路径或仅指令名
    if len(sys.argv) < 2:
        print("Usage: python rvtests_run_single.py <inst_name_or_data_path>")
        return
        
    test_input = sys.argv[1]
    data_file = ""
    
    # 如果仅传入指令名 (如 "add")，则在子目录下检索 .data 文件
    if not test_input.endswith('.data'):
        found = False
        SEARCH_FOLDERS = ['rv32ui', 'rv32um']
        for folder in SEARCH_FOLDERS:
            # 文件名固定结构: {isa}-p-{inst}.data
            possible_data = f"{TESTS_BASE_DIR}/{folder}/{folder}-p-{test_input}.data"
            if os.path.exists(possible_data):
                data_file = possible_data
                found = True
                break
        
        if not found:
            print(f"Error: Could not find .data for test '{test_input}' in {SEARCH_FOLDERS}")
            return
    else:
        # 如果输入的是完整路径
        data_file = test_input

    # 1. 获取指令存储数据 (直接复制预转化的 .data 文件)
    if os.path.exists(data_file):
        shutil.copy(data_file, './inst.data')
    else:
        print(f"Error: Data file '{data_file}' does not exist.")
        return

    # 1.5 生成 filelist.f
    cmd_gen = r'python subscripts/gen_filelist.py' + ' ' + RTL_DIR + ' ' + TB_FILE + ' ' + FILELIST_F
    os.system(cmd_gen)

    # 2. 编译 RTL 文件
    cmd_compile = r'python subscripts/compile_rtl.py' + ' ' + FILELIST_F
    os.system(cmd_compile)

    # 3. 运行仿真
    import subprocess
    logfile = open('run.log', 'w')
    vvp_cmd = [r'vvp', r'out.vvp']
    process = subprocess.Popen(vvp_cmd, stdout=logfile, stderr=logfile)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        print('!!!Fail, vvp exec timeout!!!')
    logfile.close()

    # 4. 检查结果
    with open('run.log', 'r') as f:
        if 'TEST_PASS' in f.read():
            print("\n~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~~")
            print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
            print("~~~~~~~~~ #####     ##     ####    ####  ~~~~~~~~~")
            print("~~~~~~~~~ #    #   #  #   #       #      ~~~~~~~~~")
            print("~~~~~~~~~ #    #  #    #   ####    ####  ~~~~~~~~~")
            print("~~~~~~~~~ #####   ######       #       # ~~~~~~~~~")
            print("~~~~~~~~~ #       #    #  #    #  #    # ~~~~~~~~~")
            print("~~~~~~~~~ #       #    #   ####    ####  ~~~~~~~~~")
            print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
        else:
            print("\n!!! TEST_FAIL, check run.log for details !!!")

if __name__ == '__main__':
    main()
