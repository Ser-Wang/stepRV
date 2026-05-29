import shutil
import os
import glob

def main():
    # 使用前需要修改源目录！！！
    # 脚本位置: tests/rv_compliance/update_compliance.py
    # 目标根目录: 当前目录 (.)
    dst_root = "."
    
    # 基础源目录路径 (相对于 tests/rv_compliance)
    # 1. 编译生成的 bin 和 dump 路径
    build_base = os.path.join("..", "riscv-compliance", "build_generated")
    # 2. 官方提供的 reference 路径
    ref_base = os.path.join("..", "riscv-compliance", "riscv-test-suite")
    
    # 需要处理的四个指令集文件夹
    isa_list = ["rv32i", "rv32im", "rv32Zicsr", "rv32Zifencei"]
    
    print("开始同步 Compliance 测试文件...")
    
    total_count = 0
    
    for isa in isa_list:
        print(f"--- 处理指令集: {isa} ---")
        
        # 确定源和目标的具体路径
        src_build_dir = os.path.join(build_base, isa)
        src_ref_dir = os.path.join(ref_base, isa, "references")
        dst_isa_dir = os.path.join(dst_root, isa)
        
        # 确保目标 ISA 目录存在
        if not os.path.exists(dst_isa_dir):
            os.makedirs(dst_isa_dir)
            
        if not os.path.exists(src_build_dir):
            print(f"警告: 找不到编译目录 {src_build_dir}，跳过。")
            continue

        # 1. 处理 bin 和 dump (来自 build_generated)
        # 查找所有的 .elf.bin 文件作为基准
        bin_files = glob.glob(os.path.join(src_build_dir, "*.elf.bin"))
        
        for bin_path in bin_files:
            # 提取测试名称，例如: I-ADD-01
            test_name = os.path.basename(bin_path).replace(".elf.bin", "")
            
            # --- 复制 .bin ---
            shutil.copy(bin_path, os.path.join(dst_isa_dir, f"{test_name}.bin"))
            
            # --- 复制 .dump ---
            dump_src = os.path.join(src_build_dir, f"{test_name}.elf.objdump")
            if os.path.exists(dump_src):
                shutil.copy(dump_src, os.path.join(dst_isa_dir, f"{test_name}.dump"))
            
            # --- 复制 .ref ---
            # reference 文件通常命名为 test_name.reference_output
            ref_src = os.path.join(src_ref_dir, f"{test_name}.reference_output")
            if os.path.exists(ref_src):
                shutil.copy(ref_src, os.path.join(dst_isa_dir, f"{test_name}.ref"))
            else:
                # 兼容性处理：有些参考文件命名可能略有不同，可在此添加逻辑
                print(f"提示: 未找到 {test_name} 的参考文件 (.ref)")
            
            total_count += 1
            
    print(f"\n同步完成！共处理了 {total_count} 个测试案例。")
    print("文件已重命名为: .bin, .dump, .ref")

if __name__ == "__main__":
    main()
