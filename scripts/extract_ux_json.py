"""Extract CSV data as JSON arrays for Dart embedding."""
import csv, json, os, sys, re

SRC = r"E:\CODEPROJECT\开源项目\ui-ux-pro-max-skill-main\src\ui-ux-pro-max\data"
DST = r"E:\CODEPROJECT\My minimax\lib\core\design\tokens"

def read_csv(filename):
    with open(os.path.join(SRC, filename), encoding='utf-8') as f:
        return list(csv.DictReader(f))

# 1. Product router
rows = read_csv('ui-reasoning.csv')
with open(os.path.join(DST, 'product_router.json'), 'w', encoding='utf-8') as f:
    json.dump([{
        'category': r['UI_Category'],
        'pattern': r['Recommended_Pattern'],
        'styles': r['Style_Priority'],
        'color': r['Color_Mood'],
        'typo': r['Typography_Mood'],
        'effects': r['Key_Effects'],
        'anti': r['Anti_Patterns'],
        'severity': r['Severity'],
    } for r in rows], f, ensure_ascii=False, indent=2)

# 2. UX rules
rows = read_csv('ux-guidelines.csv')
with open(os.path.join(DST, 'ux_rules.json'), 'w', encoding='utf-8') as f:
    json.dump([{
        'cat': r['Category'],
        'issue': r['Issue'],
        'platform': r['Platform'],
        'desc': r['Description'],
        'do': r['Do'],
        'dont': r["Don't"],
        'good': r['Code Example Good'],
        'bad': r['Code Example Bad'],
        'severity': r['Severity'],
    } for r in rows], f, ensure_ascii=False, indent=2)

# 3. Font pairings
rows = read_csv('typography.csv')
with open(os.path.join(DST, 'font_pairings.json'), 'w', encoding='utf-8') as f:
    json.dump([{
        'name': r['Font Pairing Name'],
        'category': r['Category'],
        'heading': r['Heading Font'],
        'body': r['Body Font'],
        'mood': r['Mood/Style Keywords'],
        'bestFor': r['Best For'],
        'import': r['CSS Import'],
        'notes': r['Notes'],
    } for r in rows], f, ensure_ascii=False, indent=2)

# 4. Landing patterns
rows = read_csv('landing.csv')
with open(os.path.join(DST, 'landing_patterns.json'), 'w', encoding='utf-8') as f:
    json.dump([{
        'name': r['Pattern Name'],
        'keywords': r['Keywords'],
        'sections': r['Section Order'],
        'cta': r['Primary CTA Placement'],
        'color': r['Color Strategy'],
        'effects': r['Recommended Effects'],
        'conversion': r['Conversion Optimization'],
    } for r in rows], f, ensure_ascii=False, indent=2)

# 5. Style specs — parse the block-structured design.csv
with open(os.path.join(SRC, 'design.csv'), encoding='utf-8') as f:
    content = f.read()

# Split into blocks by style name headers (lines starting with Capital letter followed by lowercase)
blocks = []
current = []
for line in content.split('\n'):
    if re.match(r'^[A-Z][a-z].*(?:（|\().*(?:）|\))', line) and current:
        blocks.append('\n'.join(current))
        current = [line]
    else:
        current.append(line)
if current:
    blocks.append('\n'.join(current))

specs = []
for block in blocks:
    lines = block.strip().split('\n')
    if not lines: continue
    name = lines[0].strip()
    name_en = re.sub(r'（.*?）|\(.*?\)', '', name).strip()
    desc = ''
    best_for = []
    for i, line in enumerate(lines[1:10], 1):
        s = line.strip()
        if re.match(r'^\d+\.', s):
            best_for.append(s)
        elif s and not desc and not s.startswith('<'):
            desc = s
            break
    spec = '\n'.join(lines[1:])
    specs.append({
        'name': name_en,
        'fullName': name,
        'desc': desc,
        'bestFor': ' | '.join(best_for),
        'spec': spec,
    })

with open(os.path.join(DST, 'style_specs.json'), 'w', encoding='utf-8') as f:
    json.dump(specs, f, ensure_ascii=False, indent=2)

print(f"Extracted: {len(specs)} style specs")
print("All JSON files written to tokens/")
