#!/usr/bin/env python3
"""
calc_decinfo.py
Parse config.v, recursively resolve all `define macro numeric values,
and generate a Markdown report with grouped tables.

Usage:
    python calc_decinfo.py [config.v path] [output report path]

Defaults:
    config.v  = ./config.v  (same directory as this script)
    report    = ./decinfo_report.md
"""

import re
import sys
import os

# ─── Parsing ───────────────────────────────────────────────────────────────

def parse_defines(filepath):
    """
    Parse all non-commented `define lines from config.v.
    Returns an ordered list of (name, raw_expr, line_number) and a dict {name: raw_expr}.
    """
    define_pat = re.compile(
        r"^\s*`define\s+(\w+)\s+(.*?)\s*(?://.*)?$"
    )
    ordered = []   # [(name, raw_expr, lineno), ...]
    macros  = {}   # {name: raw_expr}

    with open(filepath, 'r', encoding='utf-8') as f:
        for lineno, line in enumerate(f, 1):
            stripped = line.strip()
            # Skip blank lines
            if not stripped:
                continue
            # Skip pure comment lines
            if stripped.startswith('//'):
                continue
            m = define_pat.match(stripped)
            if m:
                name = m.group(1)
                expr = m.group(2).strip()
                # Remove trailing inline comment
                # Be careful with : in range expressions
                # Only strip comments that start with //
                comment_pos = expr.find('//')
                if comment_pos >= 0:
                    expr = expr[:comment_pos].strip()
                ordered.append((name, expr, lineno))
                macros[name] = expr

    return ordered, macros


# ─── Expression Evaluation ────────────────────────────────────────────────

def resolve_expr(expr, macros, resolved_cache, _depth=0):
    """
    Recursively resolve a macro expression to its numeric value.
    Returns:
        int   - for purely numeric expressions
        str   - for range expressions like "MSB:LSB" -> "7:3"
        None  - if cannot resolve (e.g. non-numeric defines)
    """
    if _depth > 100:
        return None  # prevent infinite recursion

    # Check cache
    if expr in resolved_cache:
        return resolved_cache[expr]

    # Handle range expression:  `XXX_MSB :`XXX_LSB  or  `XXX_MSB:`XXX_LSB
    range_pat = re.compile(r"^`(\w+)\s*:\s*`(\w+)$")
    rm = range_pat.match(expr.strip())
    if rm:
        msb_name = rm.group(1)
        lsb_name = rm.group(2)
        msb_val = resolve_name(msb_name, macros, resolved_cache, _depth + 1)
        lsb_val = resolve_name(lsb_name, macros, resolved_cache, _depth + 1)
        if msb_val is not None and lsb_val is not None:
            result = f"{msb_val}:{lsb_val}"
            resolved_cache[expr] = result
            return result
        return None

    # Handle Verilog sized literal like  3'd0, 3'd1, etc.
    sized_pat = re.compile(r"^`?(\w+)'d(\d+)$")
    sm = sized_pat.match(expr.strip())
    if sm:
        val = int(sm.group(2))
        resolved_cache[expr] = val
        return val

    # Try to substitute all `MACRO references and evaluate
    def sub_macro(m):
        name = m.group(1)
        val = resolve_name(name, macros, resolved_cache, _depth + 1)
        if val is not None and isinstance(val, int):
            return str(val)
        return f"_UNRESOLVED_{name}_"

    # Replace `MACRO_NAME with resolved values
    substituted = re.sub(r"`(\w+)", sub_macro, expr)

    # Check if any unresolved remain
    if '_UNRESOLVED_' in substituted:
        return None

    # Try to evaluate as Python arithmetic
    try:
        # Only allow safe chars: digits, +, -, *, (, ), spaces
        if re.match(r'^[\d\s\+\-\*\(\)]+$', substituted):
            val = eval(substituted)
            resolved_cache[expr] = int(val)
            return int(val)
    except Exception:
        pass

    # Plain integer
    try:
        val = int(expr)
        resolved_cache[expr] = val
        return val
    except ValueError:
        pass

    return None


def resolve_name(name, macros, resolved_cache, _depth=0):
    """Resolve a macro name to its numeric value."""
    cache_key = f"__name__{name}"
    if cache_key in resolved_cache:
        return resolved_cache[cache_key]

    if name not in macros:
        return None

    val = resolve_expr(macros[name], macros, resolved_cache, _depth)
    if val is not None:
        resolved_cache[cache_key] = val
    return val


# ─── Report Generation ────────────────────────────────────────────────────

def classify_group(name):
    """Classify a macro name into its group for reporting."""
    if name.startswith('DECINFO_CSR_') or name == 'DECINFO_BUS_CSR_WIDTH':
        return 'CSR'
    if name.startswith('DECINFO_BRU_') or name == 'DECINFO_BUS_BRU_WIDTH':
        return 'BRU'
    if name.startswith('DECINFO_LSU_') or name == 'DECINFO_BUS_LSU_WIDTH':
        return 'LSU'
    if name.startswith('DECINFO_ALU_') or name == 'DECINFO_BUS_ALU_WIDTH':
        return 'ALU'
    if name.startswith('DECINFO_GRP') or name == 'DECINFO_SUBDECINFO_LSB':
        return 'Common'
    if name == 'DECINFO_BUS_WIDTH':
        return 'Total'
    return 'Other'

GROUP_ORDER = ['Common', 'ALU', 'LSU', 'BRU', 'CSR', 'Total', 'Other']
GROUP_TITLES = {
    'Common': 'Common / GRP Segment',
    'ALU':    'ALU Group',
    'LSU':    'LSU Group',
    'BRU':    'BRU Group',
    'CSR':    'CSR Group',
    'Total':  'Total Bus Width',
    'Other':  'Other Macros',
}


def generate_report(ordered, macros, resolved_cache, output_path):
    """Generate a Markdown report file."""

    # Group macros, only DECINFO-related ones
    groups = {g: [] for g in GROUP_ORDER}
    for name, raw_expr, lineno in ordered:
        if not name.startswith('DECINFO'):
            continue
        grp = classify_group(name)
        val = resolve_name(name, macros, resolved_cache)
        groups[grp].append((name, raw_expr, lineno, val))

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('# DECINFO Macro Resolved Values Report\n\n')
        f.write(f'Source: `config.v`\n\n')
        f.write('---\n\n')

        for grp in GROUP_ORDER:
            items = groups[grp]
            if not items:
                continue

            f.write(f'## {GROUP_TITLES[grp]}\n\n')

            # Separate into: LSB/MSB (scalar) entries and Range entries
            scalar_items = []
            range_items  = []
            for name, raw_expr, lineno, val in items:
                if isinstance(val, str) and ':' in val:
                    range_items.append((name, raw_expr, lineno, val))
                else:
                    scalar_items.append((name, raw_expr, lineno, val))

            # ── Scalar Table (LSB / MSB / WIDTH) ──
            if scalar_items:
                f.write('| # | Macro Name | Expression | Value |\n')
                f.write('|---|-----------|------------|-------|\n')
                for i, (name, raw_expr, lineno, val) in enumerate(scalar_items, 1):
                    display_val = str(val) if val is not None else '?'
                    # Truncate long expressions for readability
                    display_expr = raw_expr if len(raw_expr) <= 45 else raw_expr[:42] + '...'
                    f.write(f'| {i} | `{name}` | `{display_expr}` | **{display_val}** |\n')
                f.write('\n')

            # ── Range Table (bit-field summary) ──
            if range_items:
                f.write('**Bit-field Ranges:**\n\n')
                f.write('| Field | Bit Range [MSB:LSB] | Width |\n')
                f.write('|-------|--------------------:|------:|\n')
                for name, raw_expr, lineno, val in range_items:
                    if isinstance(val, str) and ':' in val:
                        parts = val.split(':')
                        try:
                            msb = int(parts[0])
                            lsb = int(parts[1])
                            width = msb - lsb + 1
                            f.write(f'| `{name}` | [{msb}:{lsb}] | {width} |\n')
                        except ValueError:
                            f.write(f'| `{name}` | {val} | ? |\n')
                    else:
                        f.write(f'| `{name}` | {val} | ? |\n')
                f.write('\n')

            f.write('---\n\n')

        # ── Summary Table ──
        f.write('## Summary: Sub-bus Widths\n\n')
        f.write('| Sub-bus | Width Macro | Total Bits |\n')
        f.write('|---------|-----------|:----------:|\n')
        for bus_name in ['ALU', 'LSU', 'BRU', 'CSR']:
            macro_name = f'DECINFO_BUS_{bus_name}_WIDTH'
            val = resolve_name(macro_name, macros, resolved_cache)
            display_val = str(val) if val is not None else '?'
            f.write(f'| {bus_name} | `{macro_name}` | **{display_val}** |\n')
        total_val = resolve_name('DECINFO_BUS_WIDTH', macros, resolved_cache)
        f.write(f'| **TOTAL** | `DECINFO_BUS_WIDTH` | **{total_val if total_val else "?"}** |\n')
        f.write('\n')

    print(f'Report generated: {output_path}')


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))

    config_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(script_dir, 'config.v')
    output_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(script_dir, 'decinfo_report.md')

    if not os.path.isfile(config_path):
        print(f'Error: config file not found: {config_path}')
        sys.exit(1)

    print(f'Parsing: {config_path}')
    ordered, macros = parse_defines(config_path)
    print(f'Found {len(ordered)} `define macros')

    resolved_cache = {}
    # Pre-resolve all
    for name, raw_expr, lineno in ordered:
        resolve_name(name, macros, resolved_cache)

    generate_report(ordered, macros, resolved_cache, output_path)


if __name__ == '__main__':
    main()
