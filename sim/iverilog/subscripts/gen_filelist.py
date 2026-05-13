import os
import sys

def main():
    if len(sys.argv) < 4:
        print("Usage: python gen_filelist.py <rtl_dir> <tb_file> <output_file> [optional_macros]")
        sys.exit(1)
        
    rtl_dir_rel = sys.argv[1]
    tb_file_rel = sys.argv[2]
    output_file_rel = sys.argv[3]
    
    # 获取绝对路径
    cwd = os.getcwd()
    rtl_dir = os.path.abspath(os.path.join(cwd, rtl_dir_rel))
    tb_file = os.path.abspath(os.path.join(cwd, tb_file_rel))
    output_file = os.path.abspath(os.path.join(cwd, output_file_rel))
    
    # 工程根目录定为相对于执行目录的上一层 (比如 sim -> 11_myRV)
    project_root = r'../'

    v_files = []
    # 先把 tb_file 放进来
    if os.path.exists(tb_file):
        v_files.append(tb_file.replace('\\', '/'))
    else:
        print(f"Warning: TB file {tb_file} does not exist.")
    
    # 定义需要递归搜索的顶层目录
    search_dirs = [rtl_dir]
    
    for search_dir in search_dirs:
        if os.path.exists(search_dir):
            # os.walk 递归遍历包括子目录在内的所有文件
            for root, dirs, files in os.walk(search_dir):
                # 仅在顶层搜索目录（RTL 根目录）下，将 defines 文件夹从遍历列表中移除
                if root == search_dir and 'defines' in dirs:
                    dirs.remove('defines')
                    
                for f in files:
                    if f.endswith('.v') or f.endswith('.sv'):
                        # 获取文件的绝对路径
                        f_path = os.path.join(root, f)
                        # 统一转换为正斜杠
                        f_path = os.path.abspath(f_path).replace('\\', '/')
                        if f_path not in v_files:
                            v_files.append(f_path)
        else:
            print(f"Warning: Directory {search_dir} does not exist.")

    # include 目录路径：当前 RTL 版本下的 defines 目录 (如 de_rtl/v0_rv32i_basic/defines)
    inc_dir = os.path.join(rtl_dir, 'defines').replace('\\', '/')
    if not os.path.exists(inc_dir):
        print(f"Warning: Include directory {inc_dir} does not exist.")

    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            # 加入 includes 路径
            if os.path.exists(inc_dir):
                f.write(f"+incdir+{inc_dir}\n")
            
            # 写入所有文件路径
            for v_file in v_files:
                f.write(f"{v_file}\n")
            
            # 写入可选的宏定义 (第4个参数，逗号分隔)
            if len(sys.argv) > 4:
                macros = sys.argv[4].split(',')
                for macro in macros:
                    # 兼容 iverilog 和 VCS 的写法
                    if macro.strip():
                        f.write(f"+define+{macro.strip()}\n")
        print(f"Successfully generated {output_file} with {len(v_files)} files.")
    except Exception as e:
        print(f"Error writing to {output_file}: {e}")

if __name__ == '__main__':
    main()
