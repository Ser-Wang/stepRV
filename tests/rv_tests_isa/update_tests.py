import shutil
import glob
import os

    # 使用前需要修改源目录！！！
    # 使用说明：所有isa test文件在源目录tests下是平铺的，复制到本目录（tests/rv_tests_isa）后也是平铺的。
    # 脚本在 tests/rv_tests_isa 目录下运行

def main():
    dst_dir = "."
    
    # 源目录相对于 tests/rv_tests_isa 的路径是 ../isa/generated
    src_dir = os.path.join("..", "isa", "generated")
    
    # 检查源目录是否存在
    if not os.path.exists(src_dir):
        print(f"错误: 找不到源目录 {os.path.abspath(src_dir)}")
        return

    print(f"正在从 {src_dir} 同步测试文件...")

    count = 0
    # 匹配并复制文件
    for ext in ['*.bin', '*.dump']:
        files = glob.glob(os.path.join(src_dir, ext))
        for file_path in files:
            shutil.copy(file_path, dst_dir)
            count += 1
            
    print(f"同步完成！共复制了 {count} 个文件 (*.bin, *.dump) 到当前目录。")

if __name__ == "__main__":
    main()
