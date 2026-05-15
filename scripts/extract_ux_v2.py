"""V2: Correctly parse styles.csv (67 metadata) + design.csv (9 deep specs)."""
import csv, json, os, re

SRC = r"E:\CODEPROJECT\开源项目\ui-ux-pro-max-skill-main\src\ui-ux-pro-max\data"
DST = r"E:\CODEPROJECT\My minimax\lib\core\design\tokens"

# --- Parse styles.csv for all 67 style metadata ---
style_meta = []
with open(os.path.join(SRC, 'styles.csv'), encoding='utf-8') as f:
    for r in csv.DictReader(f):
        style_meta.append({
            'name': r['Style Category'],
            'type': r['Type'],
            'keywords': r['Keywords'],
            'primaryColors': r['Primary Colors'],
            'secondaryColors': r['Secondary Colors'],
            'effects': r['Effects & Animation'],
            'bestFor': r['Best For'],
            'dontUseFor': r['Do Not Use For'],
            'darkMode': r['Dark Mode ✓'],
            'performance': r['Performance'],
            'accessibility': r['Accessibility'],
            'complexity': r['Complexity'],
            'aiPrompt': r['AI Prompt Keywords'],
            'cssTech': r['CSS/Technical Keywords'],
            'checklist': r['Implementation Checklist'],
            'designVars': r['Design System Variables'],
        })

# --- Parse design.csv for 9 deep-dive specs ---
with open(os.path.join(SRC, 'design.csv'), encoding='utf-8') as f:
    lines = f.readlines()

# Find real style boundaries: lines matching "EnglishName（中文）" at start
style_boundaries = []
for i, line in enumerate(lines):
    s = line.strip()
    if re.match(r'^[A-Z][a-z]+(?:\s+[a-z]+)*\s*（[^）]+）$', s):
        # Filter out sub-headers that happen to match
        if not re.search(r'(?:Mobile|Touch|Target|Button|Card|Input|Form|Modal|Nav|Icon|Layout|Grid|List|Tab|Menu|Header|Footer)', s):
            style_boundaries.append(i)

deep_specs = []
for idx, start in enumerate(style_boundaries):
    end = style_boundaries[idx + 1] if idx + 1 < len(style_boundaries) else len(lines)
    block = ''.join(lines[start:end]).strip()
    name_line = lines[start].strip()
    name_en = re.sub(r'（.*?）', '', name_line).strip()

    # Parse first few lines for description and best-for
    block_lines = block.split('\n')
    desc = ''
    best_for = []
    for line in block_lines[1:8]:
        s = line.strip()
        if re.match(r'^\d+\.', s):
            best_for.append(s)
        elif s and not desc and not s.startswith('<design') and not s.startswith('Design Style:'):
            desc = s
            break

    deep_specs.append({
        'name': name_en,
        'fullName': name_line,
        'desc': desc,
        'bestFor': ' | '.join(best_for),
        'spec': block,  # Full block including everything
    })

# --- Merge: for each of 67 styles, attach deep spec if available ---
merged = []
for meta in style_meta:
    name = meta['name']
    deep = None
    for d in deep_specs:
        # Match by name similarity
        if d['name'].lower() in name.lower() or name.lower() in d['name'].lower():
            deep = d
            break

    merged.append({
        **meta,
        'deepSpec': deep['spec'] if deep else '',
        'deepFullName': deep['fullName'] if deep else '',
        'deepDesc': deep['desc'] if deep else '',
        'deepBestFor': deep['bestFor'] if deep else '',
    })

# Write JSON
json_path = os.path.join(DST, 'style_library.json')
with open(json_path, 'w', encoding='utf-8') as f:
    json.dump(merged, f, ensure_ascii=False, indent=2)

print(f"styles.csv: {len(style_meta)} metadata entries")
print(f"design.csv: {len(deep_specs)} deep spec blocks: {[d['name'] for d in deep_specs]}")
print(f"Merged: {len(merged)} entries ({sum(1 for m in merged if m['deepSpec'])} with deep specs)")
print(f"Written: {json_path} ({os.path.getsize(json_path)} bytes)")
