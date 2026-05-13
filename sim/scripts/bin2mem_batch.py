import sys
import os
import glob
# 导入同目录下的转换工具逻辑
from BinToMem_CLI import bin_to_mem

def main():
    """
    批量将目录下的 .bin 文件转换为 .data 文件 (十六进制文本格式)
    用法: python isatest_bin2mem.py <目标目录>
    示例: python isatest_bin2mem.py ../rvtests/rv32ui
    """
    if len(sys.argv) < 2:
        print("用法: python isatest_bin2mem.py <directory_path>")
        return

    target_dir = sys.argv[1]
    
    # 检查目录是否存在
    if not os.path.exists(target_dir):
        print(f"错误: 找不到目录 {target_dir}")
        return

    # 搜索目录下所有的 .bin 文件
    # 使用 os.path.join 确保路径分隔符正确
    search_pattern = os.path.join(target_dir, "*.bin")
    bin_files = glob.glob(search_pattern)

    if not bin_files:
        print(f"提示: 在目录 {target_dir} 中未找到任何 .bin 文件。")
        return

    print(f"正在处理目录: {target_dir}")
    print(f"发现 {len(bin_files)} 个 .bin 文件，开始批量转换...")

    count = 0
    for bin_path in bin_files:
        # 保持文件名一致，仅修改后缀
        # 例如: rv32ui-p-add.bin -> rv32ui-p-add.data
        data_path = os.path.splitext(bin_path)[0] + ".data"
        
        try:
            bin_to_mem(bin_path, data_path)
            count += 1
            # 可选：打印进度
            # print(f"  [OK] {os.path.basename(bin_path)} -> .data")
        except Exception as e:
            print(f"  [FAILED] 转换 {bin_path} 时出错: {e}")

    print(f"\n批量转换完成！共成功转换 {count} 个文件。")

if __name__ == "__main__":
    main()
