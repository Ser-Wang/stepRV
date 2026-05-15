import os
import argparse

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if 'XWIDTH' in content:
        new_content = content.replace('XWIDTH', 'XLEN')
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated: {filepath}")

def main(directory):
    # Extensions to modify
    target_exts = ('.v', '.sv', '.vh', '.svh', '.c', '.h', '.S', '.py', '.txt', '.md')
    
    for root, dirs, files in os.walk(directory):
        # Skip hidden directories like .git or .gemini
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        for file in files:
            if file.endswith(target_exts):
                filepath = os.path.join(root, file)
                try:
                    replace_in_file(filepath)
                except UnicodeDecodeError:
                    # Skip files that are not utf-8 text
                    pass
                except Exception as e:
                    print(f"Error processing {filepath}: {e}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Replace XWIDTH with XLEN in design files.')
    parser.add_argument('directory', type=str, nargs='?', default='.', help='Directory to scan (default: current directory)')
    args = parser.parse_args()
    
    print(f"Scanning directory: {os.path.abspath(args.directory)} ...")
    main(args.directory)
    print("Done!")
