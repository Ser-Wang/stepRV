import sys
import os
import re

# Mapping of ABI register names to standard x0-x31 registers
abi_to_x = {
    "zero": "x0", "ra": "x1", "sp": "x2", "gp": "x3", "tp": "x4",
    "t0": "x5", "t1": "x6", "t2": "x7",
    "s0": "x8", "fp": "x8", "s1": "x9",
    "a0": "x10", "a1": "x11", "a2": "x12", "a3": "x13", "a4": "x14", "a5": "x15", "a6": "x16", "a7": "x17",
    "s2": "x18", "s3": "x19", "s4": "x20", "s5": "x21", "s6": "x22", "s7": "x23", "s8": "x24", "s9": "x25", "s10": "x26", "s11": "x27",
    "t3": "x28", "t4": "x29", "t5": "x30", "t6": "x31"
}

def rename_registers(input_file, output_file):
    if not os.path.exists(input_file):
        print(f"Error: Could not find file {input_file}")
        sys.exit(1)

    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Regex to match the ABI registers as whole words
    # Using \b to ensure we don't accidentally replace substrings like 'a0' in hex codes
    reg_pattern = re.compile(r'\b(' + '|'.join(abi_to_x.keys()) + r')\b')

    # Regex to split line into (prefix with address and hex) and (assembly part)
    # e.g., "   4:   00000d93            li  s11,0" 
    # Group 1: "   4:   00000d93            "
    # Group 2: "li  s11,0"
    line_pattern = re.compile(r'^(\s*[0-9a-fA-F]+:\s*[0-9a-fA-F]+\s+)(.*)$')

    def replacer(match):
        return abi_to_x[match.group(1)]

    new_lines = []
    for line in lines:
        # Strip newline for easier processing
        line = line.rstrip('\r\n')
        
        match = line_pattern.match(line)
        if match:
            prefix = match.group(1)
            asm_part = match.group(2)
            
            # Replace registers only in the assembly part to protect the hex machine code & addresses
            new_asm = reg_pattern.sub(replacer, asm_part)
            new_lines.append(prefix + new_asm + '\n')
        else:
            # For lines that don't match the standard instruction format (like labels)
            # safe to replace on the whole line as long as we use word boundaries (\b)
            new_line = reg_pattern.sub(replacer, line)
            new_lines.append(new_line + '\n')

    with open(output_file, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

    print(f"Register renaming complete. Output saved to:\n{output_file}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python rename_regs.py <input_file> <output_file>")
        print("Example: python rename_regs.py test.dump test_rename.dump")
        sys.exit(1)
    
    in_file = sys.argv[1]
    out_file = sys.argv[2]
    rename_registers(in_file, out_file)
