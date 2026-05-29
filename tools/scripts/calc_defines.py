#!/usr/bin/env python3
"""
calc_defines.py  (v2 - generic)
Parse any Verilog/SystemVerilog file, recursively resolve all `define macro
values, and output a sequential Markdown table — a direct "translation" of
every macro from top to bottom.

Features:
  - Auto-follows `include directives (relative to source file directory)
  - Handles Verilog sized literals  (e.g. 3'd0, 32'hFF)
  - Handles recursive macro references via `MACRO_NAME
  - Handles range expressions  (e.g. `MSB : `LSB  ->  "7 : 3")
  - Skips commented-out `define lines

Usage:
    python calc_defines.py                          # interactive prompt
    python calc_defines.py  <file>                  # output to <file_stem>_defines.md
    python calc_defines.py  <file>  <output.md>     # explicit output path
"""

import re, sys, os

# ─── Parsing ───────────────────────────────────────────────────────────────

DEFINE_PAT = re.compile(r"^\s*`define\s+(\w+)(?:\s+(.*?))?\s*$")
INCLUDE_PAT = re.compile(r'^\s*`include\s+"([^"]+)"')
COMMENT_TRAIL = re.compile(r'//.*$')


def strip_inline_comment(expr):
    """Remove trailing // comment, but be careful not to break the expression."""
    # Find '//' that is NOT inside parentheses (simple heuristic)
    depth = 0
    for i, ch in enumerate(expr):
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif expr[i:i+2] == '//' and depth == 0:
            return expr[:i].rstrip()
    return expr


def parse_file(filepath, visited=None):
    """
    Parse `define and `include from a single file.
    Returns ordered list of (name, raw_expr, source_file, lineno).
    Populates macros dict {name: raw_expr}.
    """
    if visited is None:
        visited = set()

    filepath = os.path.abspath(filepath)
    if filepath in visited:
        return [], {}
    visited.add(filepath)

    basedir = os.path.dirname(filepath)
    basename = os.path.basename(filepath)
    ordered = []
    macros = {}

    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        for lineno, raw_line in enumerate(f, 1):
            line = raw_line.rstrip('\r\n')
            stripped = line.strip()

            # Skip pure comment lines
            if stripped.startswith('//'):
                continue

            # Follow `include
            im = INCLUDE_PAT.match(stripped)
            if im:
                inc_name = im.group(1)
                inc_path = os.path.join(basedir, inc_name)
                if os.path.isfile(inc_path):
                    inc_ordered, inc_macros = parse_file(inc_path, visited)
                    ordered.extend(inc_ordered)
                    macros.update(inc_macros)
                continue

            # Match `define
            dm = DEFINE_PAT.match(stripped)
            if dm:
                name = dm.group(1)
                expr = (dm.group(2) or '').strip()
                expr = strip_inline_comment(expr)
                ordered.append((name, expr, basename, lineno))
                macros[name] = expr

    return ordered, macros


# ─── Expression Evaluation ────────────────────────────────────────────────

# Verilog sized literal:  <width>'<base><value>
SIZED_LIT_PAT = re.compile(r"^`?(\w+)?'([bdho])([0-9a-fA-F_]+)$", re.I)


def try_parse_literal(token):
    """Try to parse a plain integer or Verilog sized literal. Returns int or None."""
    token = token.strip()
    # Plain integer
    try:
        return int(token)
    except ValueError:
        pass
    # Hex  0xFF
    if token.startswith('0x') or token.startswith('0X'):
        try:
            return int(token, 16)
        except ValueError:
            pass
    # Verilog sized literal  e.g. 3'd0, 32'hFF, 8'b1010
    m = SIZED_LIT_PAT.match(token)
    if m:
        base_ch = m.group(2).lower()
        val_str = m.group(3).replace('_', '')
        base = {'b': 2, 'o': 8, 'd': 10, 'h': 16}[base_ch]
        try:
            return int(val_str, base)
        except ValueError:
            pass
    return None


def resolve_expr(expr, macros, cache, _depth=0):
    """
    Recursively resolve a macro expression.
    Returns int, range-string "MSB:LSB", or None.
    """
    if _depth > 200:
        return None
    if expr in cache:
        return cache[expr]
    if not expr:
        cache[expr] = None
        return None

    # ── Range expression:  `A_MSB : `B_LSB  or  `A_MSB:`B_LSB ──
    range_pat = re.compile(r"^`(\w+)\s*:\s*`(\w+)$")
    rm = range_pat.match(expr.strip())
    if rm:
        msb = resolve_name(rm.group(1), macros, cache, _depth+1)
        lsb = resolve_name(rm.group(2), macros, cache, _depth+1)
        if isinstance(msb, int) and isinstance(lsb, int):
            result = f"{msb}:{lsb}"
            cache[expr] = result
            return result
        return None

    # ── Verilog sized literal with macro width: `WIDTH'dVAL ──
    sized_macro_pat = re.compile(r"^`(\w+)'([bdho])([0-9a-fA-F_]+)$", re.I)
    sm = sized_macro_pat.match(expr.strip())
    if sm:
        base_ch = sm.group(2).lower()
        val_str = sm.group(3).replace('_', '')
        base = {'b': 2, 'o': 8, 'd': 10, 'h': 16}[base_ch]
        try:
            val = int(val_str, base)
            cache[expr] = val
            return val
        except ValueError:
            pass

    # ── Plain literal ──
    lit = try_parse_literal(expr)
    if lit is not None:
        cache[expr] = lit
        return lit

    # ── Substitute all `MACRO references ──
    unresolved = []
    def sub_macro(m):
        name = m.group(1)
        val = resolve_name(name, macros, cache, _depth+1)
        if isinstance(val, int):
            return str(val)
        unresolved.append(name)
        return f"__UNRESOLVED__"

    substituted = re.sub(r"`(\w+)", sub_macro, expr)

    if unresolved:
        cache[expr] = None
        return None

    # ── Evaluate arithmetic ──
    try:
        safe = substituted.replace('\t', ' ')
        if re.match(r'^[\d\s\+\-\*\/\(\)]+$', safe):
            val = int(eval(safe))
            cache[expr] = val
            return val
    except Exception:
        pass

    cache[expr] = None
    return None


def resolve_name(name, macros, cache, _depth=0):
    ckey = f"@@{name}"
    if ckey in cache:
        return cache[ckey]
    if name not in macros:
        return None
    val = resolve_expr(macros[name], macros, cache, _depth)
    if val is not None:
        cache[ckey] = val
    return val


# ─── Report ───────────────────────────────────────────────────────────────

def format_value(val):
    """Format resolved value for display."""
    if val is None:
        return '—'
    if isinstance(val, str):
        return val            # range string like "7:3"
    return str(val)


def generate_report(ordered, macros, output_path, source_files):
    cache = {}
    # Pre-resolve all
    for name, expr, src, ln in ordered:
        resolve_name(name, macros, cache)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('# `define Macro Resolved Values\n\n')
        f.write(f'Source file(s): {", ".join(f"`{s}`" for s in source_files)}\n\n')
        f.write('---\n\n')

        f.write('| # | Line | Macro Name | Expression | Resolved |\n')
        f.write('|--:|-----:|-----------|------------|:--------:|\n')

        for i, (name, expr, src, ln) in enumerate(ordered, 1):
            val = resolve_name(name, macros, cache)
            disp_expr = expr if len(expr) <= 50 else expr[:47] + '...'
            disp_val = format_value(val)
            # Show source file only if multiple files
            line_col = f'{src}:{ln}' if len(source_files) > 1 else str(ln)
            f.write(f'| {i} | {line_col} | `{name}` | `{disp_expr}` | **{disp_val}** |\n')

        f.write(f'\n*Total: {len(ordered)} macros*\n')

    print(f'\nReport generated: {output_path}')
    print(f'  {len(ordered)} macros resolved.\n')


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) >= 2:
        input_path = sys.argv[1]
    else:
        input_path = input('Enter file path (e.g. config.v): ').strip().strip('"')

    if not os.path.isfile(input_path):
        print(f'Error: file not found: {input_path}')
        sys.exit(1)

    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        stem = os.path.splitext(input_path)[0]
        output_path = f'{stem}_defines.md'

    print(f'Parsing: {input_path}')
    ordered, macros = parse_file(input_path)
    source_files = sorted(set(src for _, _, src, _ in ordered))
    print(f'Found {len(ordered)} `define macros from {len(source_files)} file(s): {", ".join(source_files)}')

    generate_report(ordered, macros, output_path, source_files)


if __name__ == '__main__':
    main()
