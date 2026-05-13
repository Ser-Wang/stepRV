import sys
import os
import shutil
import subprocess

# ==============================================================================
# 全局配置参数
# ==============================================================================
RTL_VERSION = '00_rv32i_basic'
RTL_DIR    = f'../../{RTL_VERSION}/de'
TB_FILE    = f'../../{RTL_VERSION}/dv/tb_soctop_isatest.sv'
FILELIST_F = r'filelist.f'
TESTS_BASE_DIR   = r'../../tests/rv_compilance'
SEARCH_TARGET_FOLDERS = ['rv32i', 'rv32im', 'rv32Zicsr', 'rv32Zifencei']

def get_reference_file(data_file):
    # data_file 示例: ../rvcompilance/rv32i/I-ADD-01.data
    # ref_file 预期: ../rvcompilance/rv32i/I-ADD-01.ref
    prefix, _ = os.path.splitext(data_file)
    ref_file = prefix + ".ref"
    if os.path.exists(ref_file):
        return ref_file
    return None

def main():
    print(f"===========================================")
    print(f"--- Running Compliance Test on RTL: {RTL_VERSION} ---")
    print(f"===========================================")

    if len(sys.argv) < 2:
        print("Usage: python rvcompliance_run_single.py <test_name_or_data_path>")
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
    else:
        print(f"Error: Data file {data_file} not found.")
        return

    # 1.5 生成 filelist.f
    os.system(f'python subscripts/gen_filelist.py {RTL_DIR} {TB_FILE} {FILELIST_F} RVTEST_COMPLIANCE')

    # 2. 编译 RTL
    os.system(f'python subscripts/compile_rtl.py {FILELIST_F}')

    # 3. 运行
    logfile = open('run.log', 'w')
    process = subprocess.Popen([r'vvp', r'out.vvp'], stdout=logfile, stderr=logfile)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        print('[FAIL] vvp exec timeout.')
    logfile.close()

    # 4. 比较结果
    ref_file = get_reference_file(data_file)
    if ref_file and os.path.exists(ref_file):
        if os.path.getsize('signature.output') != os.path.getsize(ref_file):
            print('[FAIL] Signature size mismatch.')
            return
        
        with open('signature.output', 'r') as f1, open(ref_file, 'r') as f2:
            f1_lines = f1.readlines()
            f2_lines = f2.readlines()
            for i, line in enumerate(f2_lines):
                if i >= len(f1_lines) or f1_lines[i] != line:
                    print(f'[FAIL] Mismatch at line {i+1}.')
                    return
        print('[PASS]')
    else:
        print('No ref file found, please check result manually.')

if __name__ == '__main__':
    main()
