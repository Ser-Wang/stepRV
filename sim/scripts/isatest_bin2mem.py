import sys
import filecmp
import subprocess
import sys
import os


# 主函数
def main():
    #print(sys.argv[0] + ' ' + sys.argv[1] + ' ' + sys.argv[2])

    # 1.将bin文件转成mem文件，输出在当前运行目录下
    cmd = r'python ./BinToMem_CLI.py' + ' ' + r'../../tests/isa/generated/rv32ui-p-' + sys.argv[1] + '.bin' + ' ' + r'inst.data'
    f = os.popen(cmd)
    f.close()


if __name__ == '__main__':
    sys.exit(main())
