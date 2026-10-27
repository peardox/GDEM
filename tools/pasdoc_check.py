"""Heuristic PasDoc checker for the GDEM units.

Usage, from the repository root:

    python3 tools/pasdoc_check.py

which checks GDEMFetch, TileMaker and common together, or name the
folders to check:

    python3 tools/pasdoc_check.py GDEMFetch common

It reads every .pas file in each folder and the folders inside it (lib and
ui), and each program's .dpr. Names declared in any of them count for
@link, so a program's comments can link to the units in common. It
reports, per unit:
  - a missing @abstract unit comment before `unit X;`
  - interface declarations with no comment immediately before them
  - unbalanced parentheses inside @tag(...) in comments
  - @link(...) targets that are not declared anywhere in the project
  - fields declared after a method or property in the same section of a
    class, which Delphi rejects (E2169)
  - a unit in lib, or in common, that uses FMX or a unit in any ui folder:
    those must stay free of the user interface, so other programs can
    reuse them

It does not parse Pascal fully, so it can miss things PasDoc would warn
about, but it has no dependencies beyond Python 3. Prints
"No problems found" when it finds nothing.
"""
import re, sys, pathlib

roots = [pathlib.Path(a) for a in sys.argv[1:]] or [
    pathlib.Path(p) for p in ('GDEMFetch', 'TileMaker', 'common') if pathlib.Path(p).is_dir()]
files = []
for root in roots:
    files += sorted(root.rglob('*.pas')) + sorted(root.glob('*.dpr'))


def label(path):
    """The file's path as given on the command line, for messages."""
    return path.as_posix()

DECL_KW = re.compile(r'^\s*(class\s+)?(procedure|function|constructor|destructor|property|operator)\b', re.I)
TYPE_DECL = re.compile(r'^\s*([A-Za-z_]\w*)(<[^>]*>)?\s*=\s*(?!\s*$)', re.I)
FIELD = re.compile(r'^\s*(class\s+var\s+)?([A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*)\s*:\s*[^=]', re.I)
ENUM_VAL = re.compile(r'^\s*([A-Za-z_]\w*)\s*[,)]')
SECTION = re.compile(r'^\s*(type|const|var|resourcestring|private|protected|public|published|strict\s+private|strict\s+protected)\s*$', re.I)

declared = set()
problems = []

def strip_strings(line):
    return re.sub(r"'[^']*'", "''", line)

texts = {}
for f in files:
    texts[f] = f.read_text(encoding='utf-8-sig')
    for m in re.finditer(r'\b([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*=\s*(?:class|record|interface|\(|reference|array|set|type|\d|\'|-|\$|[A-Za-z])', texts[f]):
        declared.add(m.group(1).lower())
    for m in re.finditer(r'\b(?:procedure|function|constructor|destructor|property)\s+(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)', texts[f], re.I):
        declared.add(m.group(1).lower())
    for m in re.finditer(r'^\s*([A-Za-z_]\w*)\s*:', texts[f], re.M):
        declared.add(m.group(1).lower())
    for m in re.finditer(r'^\s*([A-Za-z_]\w*)\s*[,)]\s*$', texts[f], re.M):
        declared.add(m.group(1).lower())
    declared.add(f.stem.lower())

KNOWN_EXTERNAL = {'eoperationcancelled'}

for f in files:
    text = texts[f]
    lines = text.split('\n')
    # unit comment
    m = re.search(r'^(unit|program)\s+\w+;', text, re.M)
    if m:
        before = text[:m.start()].rstrip()
        if not before.endswith('}') or '@abstract' not in before[-4000:]:
            problems.append(f'{label(f)}: unit/program comment without @abstract')
    # comments: tag balance and links
    for cm in re.finditer(r'\{(?!\$)(.*?)\}', text, re.S):
        body = cm.group(1)
        lineno = text[:cm.start()].count('\n') + 1
        for tm in re.finditer(r'@(\w+)\(', body):
            depth, i = 1, tm.end()
            while i < len(body) and depth:
                if body[i] == '(':
                    depth += 1
                elif body[i] == ')':
                    depth -= 1
                i += 1
            if depth:
                problems.append(f'{label(f)}:{lineno}: unbalanced @{tm.group(1)}(')
        for lm in re.finditer(r'@link\(([^)\s]+)', body):
            target = lm.group(1).split('.')[-1].lower()
            if target not in declared and target not in KNOWN_EXTERNAL:
                problems.append(f'{label(f)}:{lineno}: @link({lm.group(1)}) not found')
    if f.suffix == '.dpr':
        continue
    # interface declarations need a comment before them
    try:
        start = next(i for i, l in enumerate(lines) if re.match(r'^\s*interface\s*$', l))
        end = next(i for i, l in enumerate(lines) if re.match(r'^\s*implementation\s*$', l))
    except StopIteration:
        continue
    in_comment = False
    in_uses = False
    paren_depth = 0
    in_class = False
    seen_member = False
    for i in range(start + 1, end):
        raw = lines[i]
        line = strip_strings(raw)
        s = line.strip()
        # track multi-line { } comments
        if in_comment:
            if '}' in s:
                in_comment = False
            continue
        if s.startswith('{') and not s.startswith('{$'):
            if '}' not in s:
                in_comment = True
            continue
        if not s or s.startswith('//') or s.startswith('{$'):
            continue
        if re.match(r'^uses\b', s, re.I):
            in_uses = not s.endswith(';')
            continue
        if in_uses:
            if s.endswith(';'):
                in_uses = False
            continue
        if re.match(r'^[A-Za-z_]\w*(<[^>]*>)?\s*=\s*class\b(?!.*;\s*$)', s, re.I) \
                and not re.search(r'=\s*class\s+of\b', s, re.I):
            in_class, seen_member = True, False
        if SECTION.match(s):
            seen_member = False
            continue
        if re.match(r'^end\s*;', s, re.I) or s in ('end;', 'end'):
            in_class = False
            continue
        # continuation lines (parameters, wrapped expressions)
        if paren_depth > 0:
            paren_depth += s.count('(') - s.count(')')
            continue
        is_decl = bool(DECL_KW.match(s) or TYPE_DECL.match(s) or FIELD.match(s)
                       or (ENUM_VAL.match(s) and not re.match(r'^\s*\w+\s*:', s)))
        if not is_decl:
            continue
        if in_class and paren_depth == 0:
            if DECL_KW.match(s):
                seen_member = True
            elif FIELD.match(s) and seen_member:
                problems.append(f'{label(f)}:{i+1}: field after a method or property '
                                f'(Delphi E2169): {s[:60]}')
        # previous non-blank line, skipping compiler directives
        j = i - 1
        while j > start and (not lines[j].strip() or lines[j].strip().startswith('{$')
                             or re.match(r'^\[.*\]$', lines[j].strip())):
            j -= 1
        prev = lines[j].strip()
        documented = prev.endswith('}') or prev.startswith('//') or prev.endswith('*)')
        if not documented:
            problems.append(f'{label(f)}:{i+1}: undocumented: {s[:70]}')
        paren_depth = s.count('(') - s.count(')')
        if paren_depth < 0:
            paren_depth = 0

# lib must not depend on the user interface
ui_units = {p.stem.lower() for root in roots for p in root.rglob('*.pas')
            if p.parent.name == 'ui'}
no_ui_files = [f for f in files if f.suffix == '.pas' and
               (f.parent.name == 'lib' or f.parent.name == 'common')]
for f in no_ui_files:
    code = re.sub(r'\{(?!\$).*?\}', ' ', texts[f], flags=re.S)
    code = re.sub(r'\(\*.*?\*\)', ' ', code, flags=re.S)
    code = re.sub(r'//[^\n]*', ' ', code)
    code = re.sub(r"'[^']*'", "''", code)
    for clause in re.finditer(r'\buses\b(.*?);', code, re.S | re.I):
        for name in re.sub(r'\{\$.*?\}', ' ', clause.group(1)).split(','):
            name = name.strip().split()[0] if name.strip() else ''
            if name.lower().startswith('fmx.') or name.lower() in ui_units:
                problems.append(f'{label(f)}: {f.parent.name} unit uses {name}, which belongs to the '
                                f'user interface')

print('\n'.join(problems) if problems else 'No problems found')
