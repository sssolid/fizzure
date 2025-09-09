#!/usr/bin/env python3
import re, sys, os, argparse
from pathlib import Path

FUNC_GLOBAL     = re.compile(r'(?m)^\s*function\s+([A-Za-z_]\w*)\s*\(([^)]*)\)')
FUNC_TABLE_DOT  = re.compile(r'(?m)^\s*function\s+([A-Za-z_]\w*)\.(\w+)\s*\(([^)]*)\)')
FUNC_TABLE_COL  = re.compile(r'(?m)^\s*function\s+([A-Za-z_]\w*):(\w+)\s*\(([^)]*)\)')
ASSIGN_GLOBAL   = re.compile(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*function\s*\(([^)]*)\)')
ASSIGN_TABLE    = re.compile(r'(?m)^\s*([A-Za-z_]\w*)\.(\w+)\s*=\s*function\s*\(([^)]*)\)')

LONG_COMMENT    = re.compile(r'--\[(=*)\[(.|\n)*?\]\1\]', re.M)
LINE_COMMENT    = re.compile(r'--.*')

def strip_comments(src: str) -> str:
    src = re.sub(LONG_COMMENT, '', src)
    src = re.sub(LINE_COMMENT, '', src)
    return src

def params_to_stub(p: str) -> str:
    p = p.strip()
    if not p or p == '...' or p.lower() == 'self' or p == '_':
        return '...'
    # keep names but don’t try to type them
    return p

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inputs', nargs='+', help='Folders to scan (e.g., FrameXML GlueXML)')
    ap.add_argument('-o', '--out', required=True, help='Output stub file')
    args = ap.parse_args()

    globals_set = {}     # foo -> paramstr
    tables_dot   = {}    # T.name -> paramstr
    tables_col   = {}    # T:name -> paramstr
    table_names  = set() # T

    files = []
    for inp in args.inputs:
        p = Path(inp)
        if p.is_dir():
            for f in p.rglob('*.lua'):
                files.append(f)
        elif p.is_file() and p.suffix == '.lua':
            files.append(p)

    for f in files:
        try:
            txt = f.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            continue
        txt = strip_comments(txt)

        # Skip local functions by rejecting "local function ..." lines
        # (we only capture patterns that don't include 'local')
        for m in FUNC_TABLE_COL.finditer(txt):
            tbl, name, ps = m.groups()
            table_names.add(tbl)
            key = f'{tbl}:{name}'
            tables_col.setdefault(key, params_to_stub(ps))

        for m in FUNC_TABLE_DOT.finditer(txt):
            tbl, name, ps = m.groups()
            table_names.add(tbl)
            key = f'{tbl}.{name}'
            tables_dot.setdefault(key, params_to_stub(ps))

        for m in FUNC_GLOBAL.finditer(txt):
            fn, ps = m.groups()
            # reject "local function ..." by checking previous chars
            start = m.start()
            prefix = txt[max(0, start-20):start]
            if re.search(r'local\s*$', prefix):
                continue
            globals_set.setdefault(fn, params_to_stub(ps))

        for m in ASSIGN_TABLE.finditer(txt):
            tbl, name, ps = m.groups()
            table_names.add(tbl)
            key = f'{tbl}.{name}'
            tables_dot.setdefault(key, params_to_stub(ps))

        for m in ASSIGN_GLOBAL.finditer(txt):
            fn, ps = m.groups()
            # reject "local x = function(...)"
            start = m.start()
            prefix = txt[max(0, start-20):start]
            if re.search(r'local\s*$', prefix):
                continue
            globals_set.setdefault(fn, params_to_stub(ps))

    out = []
    out.append('---@meta\n')
    # declare tables seen in method definitions so LuaLS knows they exist
    for t in sorted(table_names):
        out.append(f'---@class {t}\n{t} = {t}\n')

    # global functions
    for name in sorted(globals_set.keys()):
        ps = globals_set[name]
        out.append(f'function {name}({ps}) end\n')

    # T.foo(...) (dot)
    for key in sorted(tables_dot.keys()):
        t, n = key.split('.', 1)
        ps = tables_dot[key]
        out.append(f'function {t}.{n}({ps}) end\n')

    # T:foo(...) (colon) -> include self
    for key in sorted(tables_col.keys()):
        t, n = key.split(':', 1)
        ps = tables_col[key]
        if ps.strip() in ('', '...'):
            out.append(f'function {t}:{n}(...) end\n')
        else:
            out.append(f'function {t}:{n}({ps}) end\n')

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(''.join(out), encoding='utf-8')
    print(f'Wrote {args.out} with {len(globals_set)} globals, {len(tables_dot)} dot-methods, {len(tables_col)} colon-methods.')

if __name__ == '__main__':
    main()
