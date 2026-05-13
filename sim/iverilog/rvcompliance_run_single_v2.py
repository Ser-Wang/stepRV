import sys
import os
import shutil
import subprocess

# ==============================================================================
# 全局配置参数
# ==============================================================================
RTL_VERSION = 'v0_rv32i_basic'
RTL_DIR    = f'../../de_rtl/{RTL_VERSION}'
TB_FILE    = r'../../dv_tb/tb_soctop_rvcompilance_new.sv'
FILELIST_F = r'filelist.f'
TESTS_BASE_DIR = r'../rvcompilance'
SEARCH_TARGET_FOLDERS = ['rv32i', 'rv32im', 'rv32Zicsr', 'rv32Zifencei']

def main():
    print(f"===========================================")
    print(f"--- Running Compliance Test (V2) on RTL: {RTL_VERSION} ---")
    print(f"===========================================")

    if len(sys.argv) < 2:
        print("Usage: python rvcompliance_run_single_v2.py <test_name_or_data_path>")
        return

    test_input = sys.argv[1]
    data_file = ""

    if not test_input.endswith('.data'):
        found = False
        for folder in SEARCH_TARGET_FOLDERS:
            possible_data = f"{TESTS_BASE_DIR}/{folder}/{test_input}.data"
            if os.path.exists(possible_data):
                data_file = possible_data
                found = True
                break
        if not found:
            print(f"Error: Could not find .data for test {test_input}")
            return
    else:
        data_file = test_input

    # 1. 复制指令存储数据
    if os.path.exists(data_file):
        shutil.copy(data_file, './inst.data')
        # 同时复制参考文件到当前目录，供 SV TB 使用 (tb_soctop_rvcompilance_new.sv)
        ref_src = data_file.replace('.data', '.ref')
        if os.path.exists(ref_src):
             shutil.copy(ref_src, './ref.data')
    else:
        print(f"Error: Data file {data_file} not found.")
        return

    # 1.5 生成 filelist.f
    os.system(f'python subscripts/gen_filelist.py {RTL_DIR} {TB_FILE} {FILELIST_F}')

    # 2. 编译 RTL
    os.system(f'python subscripts/compile_rtl.py {FILELIST_F}')

    # 3. 运行
    logfile = open('run.log', 'w')
    process = subprocess.Popen([r'vvp', r'out.vvp'], stdout=logfile, stderr=logfile)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        print('!!!Fail, vvp exec timeout!!!')
    logfile.close()

    # 4. 检查 SV TB 的输出结果
    with open('run.log', 'r') as f:
        log_content = f.read()
        if '### PASS ###' in log_content:
            print('### PASS ###')
        elif '!!! FAIL !!!' in log_content:
            print('!!! FAIL !!!')
        else:
            print('Simulation finished. Please check run.log for details.')

if __name__ == '__main__':
    main()
