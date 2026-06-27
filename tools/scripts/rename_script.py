import os

target_dirs = [
    '/home/moxiao/work/my-RISCV-Projs/01_rv32i_sramtcm',
    '/home/moxiao/work/my-RISCV-Projs/sim'
]

replacements = {
    'core': 'core',
    'soc_bus': 'soc_bus',
    'soc_top': 'soc_top',
    'wrapper_soc_top': 'wrapper_soc_top'
}

def process():
    # 1. replace content
    for d in target_dirs:
        for root, dirs, files in os.walk(d):
            if '.git' in root:
                continue
            for f in files:
                path = os.path.join(root, f)
                # Skip binary files or non-text files if we want, but let's just use try-except
                if path.endswith('.png') or path.endswith('.pyc') or path.endswith('.fsdb'):
                    continue
                try:
                    with open(path, 'r', encoding='utf-8') as file:
                        content = file.read()
                except Exception:
                    continue
                
                new_content = content
                for old, new in replacements.items():
                    new_content = new_content.replace(old, new)
                    
                if new_content != content:
                    with open(path, 'w', encoding='utf-8') as file:
                        file.write(new_content)
                        print(f"Updated content in {path}")

    # 2. rename files
    for d in target_dirs:
        for root, dirs, files in os.walk(d, topdown=False):
            if '.git' in root:
                continue
            for f in files:
                new_f = f
                for old, new in replacements.items():
                    if old in new_f:
                        new_f = new_f.replace(old, new)
                if new_f != f:
                    old_path = os.path.join(root, f)
                    new_path = os.path.join(root, new_f)
                    os.rename(old_path, new_path)
                    print(f"Renamed file {old_path} -> {new_path}")

if __name__ == '__main__':
    process()
