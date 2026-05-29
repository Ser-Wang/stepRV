import os
import argparse

def report_in_file(filepath, target_word):
    found = False
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                if target_word in line:
                    if not found:
                        print(f"\n--- Found in: {filepath} ---")
                        found = True
                    print(f"Line {line_num}: {line.strip()}")
    except UnicodeDecodeError:
        pass
    except Exception as e:
        print(f"Error processing {filepath}: {e}")

def main(directory, target_word):
    # Extensions to check
    target_exts = ('.v', '.sv', '.vh', '.svh', '.c', '.h', '.S', '.py', '.txt', '.md')
    
    for root, dirs, files in os.walk(directory):
        # Skip hidden directories like .git or .gemini
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        for file in files:
            if file.endswith(target_exts):
                filepath = os.path.join(root, file)
                report_in_file(filepath, target_word)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Report all locations of a specific word (default: XLEN) in design files.')
    parser.add_argument('directory', type=str, nargs='?', default='.', help='Directory to scan (default: current directory)')
    parser.add_argument('--word', type=str, default='XLEN', help='Word to search for (default: XLEN)')
    args = parser.parse_args()
    
    print(f"Scanning directory: {os.path.abspath(args.directory)} for '{args.word}'...")
    main(args.directory, args.word)
    print("\nDone!")
