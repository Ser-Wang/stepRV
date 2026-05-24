import sys
import os
import subprocess
import shutil

# Ensure subscripts is in import path to use the existing BinToMem_CLI script
sys.path.append(os.path.join(os.path.dirname(__file__), 'subscripts'))
from BinToMem_CLI import bin_to_mem

# ==============================================================================
# Global Configuration
# ==============================================================================
RTL_VERSION = '00_rv32i_basic'
RTL_DIR    = f'../../{RTL_VERSION}/de'
TB_FILE    = f'../../{RTL_VERSION}/dv/tb_soctop_isatest.sv'
FILELIST_F = r'filelist.f'
PROGRAMS_BASE_DIR = r'../../tests/programs'

def main():
    print("===========================================")
    print(f"--- Running Custom Program on RTL: {RTL_VERSION} ---")
    print("===========================================")

    if len(sys.argv) < 2:
        print("Usage: python test_program.py <program_name>")
        print("Example: python test_program.py simple")
        return

    program_name = sys.argv[1]
    
    # Locate the .bin file
    bin_file = f"{PROGRAMS_BASE_DIR}/{program_name}/{program_name}.bin"
    if not os.path.exists(bin_file):
        print(f"Error: Could not find program binary at '{bin_file}'")
        return

    print(f"Converting binary '{bin_file}' to memory data...")
    # Convert .bin to ./inst.data
    try:
        bin_to_mem(bin_file, './inst.data')
        print("Successfully generated './inst.data'.")
    except Exception as e:
        print(f"Error during bin_to_mem conversion: {e}")
        return

    # 1.5 Generate filelist.f
    cmd_gen = f"python subscripts/gen_filelist.py {RTL_DIR} {TB_FILE} {FILELIST_F} RVTEST_ISA"
    print(f"Generating filelist: {cmd_gen}")
    os.system(cmd_gen)

    # 2. Compile RTL
    cmd_compile = f"python subscripts/compile_rtl.py {FILELIST_F}"
    print(f"Compiling RTL: {cmd_compile}")
    os.system(cmd_compile)

    # 3. Run Simulation
    print("Running simulation...")
    logfile = open('run.log', 'w')
    vvp_cmd = [r'vvp', r'out.vvp']
    process = subprocess.Popen(vvp_cmd, stdout=logfile, stderr=logfile)
    try:
        # Graceful timeout of 30 seconds
        process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        process.kill()
        print('!!!Fail, vvp exec timeout!!!')
    logfile.close()

    # 4. Check results
    if os.path.exists('run.log'):
        with open('run.log', 'r') as f:
            log_content = f.read()
            # Print simulation outputs so the user can easily see execution trace
            print("\n--- Simulation Output (run.log) ---")
            print(log_content.strip())
            print("------------------------------------\n")
            
            if '[PASS]' in log_content:
                print('[PASS]')
            else:
                print('[FAIL] Check run.log for details.')
    else:
        print("Error: run.log was not created.")

if __name__ == '__main__':
    main()
