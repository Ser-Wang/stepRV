#!/usr/bin/env python3
# -*- coding: utf-8 -*-

r"""
Verilog/SystemVerilog Module Hierarchy Analyzer
Author: Antigravity (Planning: Gemini 3 Pro (High) | Execution: Gemini 3 Flash)
Completion Time: 2026-05-17 18:52:42

Description:
This script parses a list of Verilog/SystemVerilog files (either from a filelist or a directory)
to analyze their module instantiation hierarchy. It outputs a tree-like structural representation
and lists any discrepancies where module names differ from their filenames.

Usage (运行方式):
    1. Analyze an RTL directory recursively:
       python analyze_hierarchy.py <path_to_rtl_dir> [-o <output_file>]
       Example:
       python analyze_hierarchy.py d:\myProj_WJH\Flashattention\rtl -o hierarchy_output.txt

    2. Analyze files from a filelist:
       python analyze_hierarchy.py <path_to_filelist> [-o <output_file>]
       Example:
       python analyze_hierarchy.py d:\myProj_WJH\Flashattention\Browse\filelist.f -o hierarchy_output.txt

Version Log (版本更新记录):
    v1.0 (2026-05-17 18:22:42):
        - 初始版本：由 Gemini 3 Pro (High) 规划与 Gemini 3 Flash 执行。
        - 实现了轻量级 Verilog/SystemVerilog 注释剥离、多级实例化提取与 parent-child 解析。
        - 采用 Vivado 风格的 Unicode 字符输出模块层级树。
        - 提供模块名与文件名不一致检测报告表。
    v1.1 (2026-05-17 18:52:42):
        - Bug 修复：修正了宏定义（`）的过于激进正则过滤，防止将 `stall[`STALL_PC])` 等表达式中的整行截断，改用特定关键字匹配并在解析中移除 ` 反单引号将其安全转为合法标识符。
        - 默认输出：将输出文件 `hierarchy_output.txt` 的默认路径修改为当前运行工作目录 (CWD)。
        - 工业级增强：在 filelist 解析中支持剥离行内注释（`//` 与 `#`）。
        - 工业级增强：路径解析中引入 `os.path.expandvars` 支持解析环境变量（如 `$PRJ_ROOT`）。
        - 解析鲁棒性：将 SystemVerilog 关键字 `bind`、`alias` 等排除，防止验证 bind 语句被误解析为模块。
        - 格式优化：为开头 Docstring 增加 `r` 前缀，消除 Windows 反斜杠引起的转义语法警告。
"""

import os
import sys
import re
import argparse

# Standard Verilog and SystemVerilog keywords to exclude from module detection
EXCLUDE_KEYWORDS = {
    'always', 'always_comb', 'always_ff', 'always_latch', 'initial', 'assign',
    'wire', 'reg', 'logic', 'integer', 'real', 'time', 'genvar',
    'input', 'output', 'inout', 'parameter', 'localparam', 'specparam',
    'typedef', 'struct', 'union', 'enum', 'string', 'chandle', 'event',
    'import', 'export', 'package', 'endpackage', 'interface', 'endinterface',
    'program', 'endprogram', 'class', 'endclass', 'covergroup', 'endgroup',
    'property', 'endproperty', 'sequence', 'endsequence', 'assert', 'assume',
    'cover', 'expect', 'restrict', 'generate', 'endgenerate',
    'function', 'endfunction', 'task', 'endtask', 'config', 'endconfig',
    'design', 'instance', 'cell', 'library', 'use', 'bind', 'alias',
    # Gates / Primitives
    'and', 'nand', 'or', 'nor', 'xor', 'xnor', 'buf', 'not',
    'bufif0', 'bufif1', 'notif0', 'notif1', 'pullup', 'pulldown',
    'tran', 'rtran', 'tranif0', 'tranif1', 'rtranif0', 'rtranif1',
    # SystemVerilog data types and qualifiers
    'signed', 'unsigned', 'unique', 'priority', 'const', 'local', 'static', 'automatic',
    'protected', 'virtual', 'byte', 'shortint', 'int', 'longint', 'bit', 'realtime', 'shortreal',
    # Control flow / standard keywords
    'begin', 'end', 'fork', 'join', 'join_any', 'join_none', 'case', 'endcase',
    'casex', 'endcasex', 'casez', 'endcasez', 'if', 'else', 'for', 'while',
    'repeat', 'forever', 'return', 'break', 'continue', 'disable', 'specify', 'endspecify'
}

def split_by_char_at_depth_0(s, split_char):
    """
    Splits a string by split_char only when the split_char is at depth 0
    (i.e., not enclosed in parentheses, brackets, or braces).
    """
    parts = []
    current_part = []
    depth = 0
    in_string = False
    escape = False
    
    for char in s:
        if in_string:
            if escape:
                escape = False
            elif char == '\\':
                escape = True
            elif char == '"':
                in_string = False
            current_part.append(char)
            continue
        elif char == '"':
            in_string = True
            current_part.append(char)
            continue
            
        if char in '([{':
            depth += 1
            current_part.append(char)
        elif char in ')]}':
            depth = max(0, depth - 1)
            current_part.append(char)
        elif depth == 0 and char == split_char:
            parts.append(''.join(current_part))
            current_part = []
        else:
            current_part.append(char)
            
    if current_part:
        parts.append(''.join(current_part))
        
    return parts

def tokenize_depth_0(s):
    """
    Tokenizes a statement, treating parentheses/brackets groups at depth 0 as a single token.
    Splits words by whitespace, and separates special characters like '#', ',', ';'.
    """
    tokens = []
    current_token = []
    depth = 0
    in_string = False
    escape = False
    
    i = 0
    n = len(s)
    
    while i < n:
        char = s[i]
        
        if in_string:
            if escape:
                escape = False
            elif char == '\\':
                escape = True
            elif char == '"':
                in_string = False
            i += 1
            continue
        elif char == '"':
            in_string = True
            i += 1
            continue
            
        if char in '([{':
            if depth == 0:
                if current_token:
                    tokens.append(''.join(current_token))
                    current_token = []
            depth += 1
            current_token.append(char)
        elif char in ')]}':
            depth = max(0, depth - 1)
            current_token.append(char)
            if depth == 0:
                tokens.append(''.join(current_token))
                current_token = []
        elif depth > 0:
            current_token.append(char)
        else:
            # depth == 0
            if char.isspace():
                if current_token:
                    tokens.append(''.join(current_token))
                    current_token = []
            elif char in '#,;':
                if current_token:
                    tokens.append(''.join(current_token))
                    current_token = []
                tokens.append(char)
            else:
                current_token.append(char)
        i += 1
        
    if current_token:
        tokens.append(''.join(current_token))
        
    cleaned_tokens = []
    for t in tokens:
        t_strip = t.strip()
        if t_strip:
            cleaned_tokens.append(t_strip)
            
    return cleaned_tokens

def parse_verilog_file(file_path):
    """
    Parses a single Verilog/SystemVerilog file and extracts module definitions
    and their internal instantiations.
    """
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading file {file_path}: {e}")
        return []
        
    # Strip block comments /* ... */
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    # Strip line comments // ...
    content = re.sub(r'//.*', '', content)
    # Strip compiler directives (like `timescale, `include, `define, etc.)
    # We only strip lines starting with backtick followed by a compiler directive keyword
    content = re.sub(r'^\s*`(timescale|include|define|undef|ifdef|ifndef|else|elsif|endif|default_nettype|celldefine|endcelldefine)\b.*', '', content, flags=re.MULTILINE)
    # Remove any remaining backtick character to convert macros to normal identifiers
    content = content.replace('`', '')
    # Strip attribute specifications (* ... *)
    content = re.sub(r'\(\*.*?\*\)', '', content, flags=re.DOTALL)
    
    modules = []
    # Pattern to find module ... endmodule
    pattern = r'\bmodule\s+([a-zA-Z_]\w*)(.*?)\bendmodule\b'
    for match in re.finditer(pattern, content, re.DOTALL):
        module_name = match.group(1)
        module_body = match.group(2)
        modules.append((module_name, module_body))
        
    return modules

def extract_instantiations(module_body):
    """
    Extracts module instantiations from a module body using robust custom tokenization.
    Filters out assignment statements, function calls, and expressions.
    """
    instantiations = []
    statements = split_by_char_at_depth_0(module_body, ';')
    
    # Operators that should never be present at the top level of a module instantiation
    REJECT_OPERATORS = {'=', '<=', '+=', '-=', '*=', '/=', '==', '!=', '&&', '||', '<', '>', '?', ':'}
    
    for stmt in statements:
        stmt = stmt.strip()
        if not stmt:
            continue
            
        parts = split_by_char_at_depth_0(stmt, ',')
        inherited_module_name = None
        
        for part in parts:
            part = part.strip()
            if not part:
                continue
                
            tokens = tokenize_depth_0(part)
            if not tokens:
                continue
                
            # If there is any top-level assignment or comparison operator, reject it immediately
            if any(tok in REJECT_OPERATORS for tok in tokens):
                continue
                
            # Filter parameter overrides e.g. # ( ... )
            cleaned_tokens = []
            skip_next = False
            for idx, tok in enumerate(tokens):
                if skip_next:
                    skip_next = False
                    continue
                if tok == '#':
                    if idx + 1 < len(tokens) and tokens[idx+1].startswith('('):
                        skip_next = True
                    continue
                cleaned_tokens.append(tok)
                
            if not cleaned_tokens:
                continue
                
            # Instantiations must end with port list parenthesis group e.g. ( ... )
            if not cleaned_tokens[-1].startswith('('):
                continue
                
            prefix_tokens = cleaned_tokens[:-1]
            if not prefix_tokens:
                continue
                
            if len(prefix_tokens) >= 2:
                module_name = prefix_tokens[0]
                instance_name = prefix_tokens[-1]
                
                # Strip array bounds from instance name if any (e.g. u_inst[3:0] -> u_inst)
                if '[' in instance_name:
                    instance_name = instance_name.split('[')[0].strip()
                
                if module_name in EXCLUDE_KEYWORDS:
                    continue
                if not re.match(r'^[a-zA-Z_]\w*$', instance_name):
                    continue
                if not re.match(r'^[a-zA-Z_]\w*$', module_name):
                    continue
                    
                instantiations.append((module_name, instance_name))
                inherited_module_name = module_name
            elif len(prefix_tokens) == 1:
                instance_name = prefix_tokens[0]
                if '[' in instance_name:
                    instance_name = instance_name.split('[')[0].strip()
                if inherited_module_name and re.match(r'^[a-zA-Z_]\w*$', instance_name):
                    instantiations.append((inherited_module_name, instance_name))
                    
    return instantiations

def resolve_path(path_str, filelist_dir):
    """
    Resolves relative/absolute file path based on CWD or the filelist folder.
    Supports environment variables (e.g. $PRJ_ROOT/rtl/top.v).
    """
    path_str = path_str.strip('\'" \t\n\r')
    path_str = os.path.expandvars(path_str)
    path_str = path_str.replace('\\', '/')
    
    if os.path.isabs(path_str):
        if os.path.exists(path_str):
            return os.path.abspath(path_str)
            
    cwd_path = os.path.abspath(path_str)
    if os.path.exists(cwd_path):
        return cwd_path
        
    if filelist_dir:
        fl_path = os.path.abspath(os.path.join(filelist_dir, path_str))
        if os.path.exists(fl_path):
            return fl_path
            
    if filelist_dir:
        return os.path.abspath(os.path.join(filelist_dir, path_str))
    return os.path.abspath(path_str)

def parse_filelist(filelist_path):
    """
    Parses a filelist file and extracts all valid .v and .sv file paths.
    Supports environment variables and strips inline comments (// and #).
    """
    filelist_dir = os.path.dirname(os.path.abspath(filelist_path))
    files = []
    
    with open(filelist_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
                
            # Strip inline comments
            if '//' in line:
                line = line.split('//')[0].strip()
            if '#' in line:
                line = line.split('#')[0].strip()
                
            if not line:
                continue
                
            # Skip compiler directives / options
            if line.startswith('+') or line.startswith('-'):
                continue
                
            resolved = resolve_path(line, filelist_dir)
            if os.path.exists(resolved):
                if resolved.lower().endswith(('.v', '.sv')):
                    files.append(resolved)
            else:
                print(f"Warning: File from filelist not found: {line} (resolved as {resolved})")
                
    return files

def find_files_in_dir(dir_path):
    """
    Recursively scans a directory for all .v and .sv files.
    """
    files = []
    for root, _, filenames in os.walk(dir_path):
        for f in filenames:
            if f.lower().endswith(('.v', '.sv')):
                files.append(os.path.abspath(os.path.join(root, f)))
    return files

def generate_tree_lines(module_name, instance_name, module_instantiations, defined_modules, prefix="", is_last=True, visited=None):
    """
    Recursively generates unicode tree-drawing lines for a module hierarchy.
    """
    if visited is None:
        visited = set()
        
    line = prefix
    line += "└── " if is_last else "├── "
    
    label = module_name
    if module_name not in defined_modules:
        label += " [External/Missing]"
        
    if instance_name:
        label += f" ({instance_name})"
        
    lines = [line + label]
    
    if module_name in visited:
        lines[-1] += " [Circular Dependency Warning!]"
        return lines
        
    children = module_instantiations.get(module_name, [])
    if children:
        new_visited = visited | {module_name}
        new_prefix = prefix + ("    " if is_last else "│   ")
        for i, (child_mod, child_inst) in enumerate(children):
            child_is_last = (i == len(children) - 1)
            child_lines = generate_tree_lines(
                child_mod, child_inst, module_instantiations, defined_modules,
                prefix=new_prefix, is_last=child_is_last, visited=new_visited
            )
            lines.extend(child_lines)
            
    return lines

def generate_tree_lines_root(root_module, module_instantiations, defined_modules):
    """
    Generates hierarchy lines starting from a top-level module (root).
    """
    label = root_module
    if root_module not in defined_modules:
        label += " [External/Missing]"
        
    lines = [label]
    children = module_instantiations.get(root_module, [])
    visited = {root_module}
    
    for i, (child_mod, child_inst) in enumerate(children):
        is_last = (i == len(children) - 1)
        child_lines = generate_tree_lines(
            child_mod, child_inst, module_instantiations, defined_modules,
            prefix="", is_last=is_last, visited=visited
        )
        lines.extend(child_lines)
    return lines

def main():
    parser = argparse.ArgumentParser(description="Verilog/SystemVerilog Module Hierarchy Analyzer")
    parser.add_argument("input_path", help="Path to a filelist (.f, .flist, .txt) or an RTL directory")
    parser.add_argument("-o", "--output", help="Output file path (default: hierarchy_output.txt)")
    
    args = parser.parse_args()
    
    input_path = os.path.abspath(args.input_path)
    if not os.path.exists(input_path):
        print(f"Error: Input path '{input_path}' does not exist.")
        sys.exit(1)
        
    # 1. Determine files to parse
    if os.path.isdir(input_path):
        print(f"Scanning directory recursively: {input_path}")
        files = find_files_in_dir(input_path)
    else:
        print(f"Parsing filelist: {input_path}")
        files = parse_filelist(input_path)
        
    if not files:
        print("Error: No Verilog/SystemVerilog (.v or .sv) files found to analyze.")
        sys.exit(1)
        
    print(f"Found {len(files)} files to analyze.")
    
    # 2. Parse all files
    # defined_modules: map of module_name -> file_path
    defined_modules = {}
    # module_instantiations: map of parent_module -> list of (child_module, instance_name)
    module_instantiations = {}
    
    # Track name discrepancies: list of (module_name, file_name, file_path)
    name_discrepancies = []
    
    for file_path in files:
        modules = parse_verilog_file(file_path)
        filename = os.path.basename(file_path)
        filename_no_ext = os.path.splitext(filename)[0]
        
        for module_name, module_body in modules:
            if module_name in defined_modules:
                print(f"Warning: Module '{module_name}' redefined in:\n  1. {defined_modules[module_name]}\n  2. {file_path}\n(Using second definition)")
            
            defined_modules[module_name] = file_path
            
            # Check name discrepancy
            if module_name != filename_no_ext:
                # Store relative paths for better display
                rel_path = os.path.relpath(file_path, start=os.path.dirname(input_path) if os.path.isdir(input_path) else os.path.dirname(os.path.abspath(input_path)))
                name_discrepancies.append((module_name, filename, rel_path))
                
            # Extract instantiations
            insts = extract_instantiations(module_body)
            module_instantiations[module_name] = insts
            
    # 3. Analyze hierarchy and find top-levels
    # Find all modules that are instantiated anywhere
    instantiated_modules = set()
    for insts in module_instantiations.values():
        for child_mod, _ in insts:
            instantiated_modules.add(child_mod)
            
    # Top-level modules are those defined but never instantiated
    defined_set = set(defined_modules.keys())
    top_levels = sorted(list(defined_set - instantiated_modules))
    
    # Separate top-levels into active trees (have children) and isolated modules (no children)
    active_tops = []
    isolated_modules = []
    for top in top_levels:
        if module_instantiations.get(top):
            active_tops.append(top)
        else:
            isolated_modules.append(top)
            
    # 4. Generate report output
    output_lines = []
    output_lines.append("=" * 80)
    output_lines.append(" RTL MODULE HIERARCHY REPORT")
    output_lines.append("=" * 80)
    output_lines.append(f"Input Source: {input_path}")
    output_lines.append(f"Total Files Analyzed: {len(files)}")
    output_lines.append(f"Total Modules Defined: {len(defined_set)}")
    output_lines.append("-" * 80 + "\n")
    
    # 4.1 Draw Active Module Trees
    if active_tops:
        output_lines.append("### Active Module Hierarchy Trees ###\n")
        for top in active_tops:
            tree_lines = generate_tree_lines_root(top, module_instantiations, defined_modules)
            output_lines.extend(tree_lines)
            output_lines.append("")
    else:
        output_lines.append("### Active Module Hierarchy Trees ###")
        output_lines.append("None found.\n")
        
    # 4.2 Draw Isolated Modules
    if isolated_modules:
        output_lines.append("### Isolated Modules (Top-Level with No Child Instantiations) ###\n")
        for mod in isolated_modules:
            file_path = defined_modules[mod]
            rel_path = os.path.relpath(file_path, start=os.path.dirname(input_path) if os.path.isdir(input_path) else os.path.dirname(os.path.abspath(input_path)))
            output_lines.append(f"  {mod}  (Defined in: {rel_path})")
        output_lines.append("")
        
    # 4.3 Draw External / Missing Modules
    all_external = instantiated_modules - defined_set
    if all_external:
        output_lines.append("### External / Missing Modules (Instantiated but not defined) ###\n")
        for ext in sorted(list(all_external)):
            output_lines.append(f"  {ext} [External/Missing]")
        output_lines.append("")
        
    # 4.4 Discrepancy Chart
    output_lines.append("=" * 80)
    output_lines.append(" MODULE AND FILENAME DISCREPANCY CHART")
    output_lines.append("=" * 80)
    if name_discrepancies:
        output_lines.append("The following modules are defined in files whose names differ from the module name:")
        output_lines.append("")
        
        # Calculate table column widths
        col1_w = max(len("Module Name"), max(len(d[0]) for d in name_discrepancies)) + 2
        col2_w = max(len("File Name"), max(len(d[1]) for d in name_discrepancies)) + 2
        col3_w = max(len("File Path"), max(len(d[2]) for d in name_discrepancies)) + 2
        
        # Draw table
        header = f"| {'Module Name'.ljust(col1_w)} | {'File Name'.ljust(col2_w)} | {'File Path'.ljust(col3_w)} |"
        separator = f"| {'-' * col1_w} | {'-' * col2_w} | {'-' * col3_w} |"
        output_lines.append(header)
        output_lines.append(separator)
        
        for mod_name, fname, fpath in sorted(name_discrepancies, key=lambda x: x[0]):
            row = f"| {mod_name.ljust(col1_w)} | {fname.ljust(col2_w)} | {fpath.ljust(col3_w)} |"
            output_lines.append(row)
    else:
        output_lines.append("No discrepancies found. All module names match their respective filenames.")
    output_lines.append("")
    
    # 5. Write to output file
    if args.output:
        out_filepath = os.path.abspath(args.output)
    else:
        # Default to hierarchy_output.txt in the current working directory where the script is run
        out_filepath = os.path.abspath("hierarchy_output.txt")
            
    try:
        # Ensure parent folder exists
        os.makedirs(os.path.dirname(out_filepath), exist_ok=True)
        with open(out_filepath, 'w', encoding='utf-8') as out_f:
            out_f.write('\n'.join(output_lines))
        print(f"\nSuccess! Hierarchy analysis report successfully saved to:\n  {out_filepath}\n")
    except Exception as e:
        print(f"Error writing report to {out_filepath}: {e}")
        
if __name__ == "__main__":
    main()
