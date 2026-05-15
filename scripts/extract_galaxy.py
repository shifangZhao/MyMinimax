"""Extract all galaxy-main UI elements → JSON → Dart."""
import os, re, json, glob
from collections import Counter

SRC = r"E:\CODEPROJECT\开源项目\galaxy-main"
DST = r"E:\CODEPROJECT\My minimax\lib\core\design\tokens"

categories = [
    'Buttons', 'Cards', 'loaders', 'Toggle-switches', 'Inputs', 'Forms',
    'Checkboxes', 'Patterns', 'Radio-buttons', 'Tooltips', 'Notifications'
]

def extract_css_values(css):
    """Extract key CSS properties from a CSS string."""
    props = {}
    # Extract colors (hex, rgb, hsl)
    colors = re.findall(r'#[0-9a-fA-F]{3,8}', css)
    if colors:
        props['colors'] = list(set(c.lower() for c in colors))[:10]

    # Extract border-radius
    radii = re.findall(r'border-radius:\s*([^;]+)', css)
    if radii:
        props['radii'] = list(set(r.strip() for r in radii))[:5]

    # Extract box-shadow
    shadows = re.findall(r'box-shadow:\s*([^;]+)', css)
    if shadows:
        props['shadows'] = [s.strip()[:120] for s in shadows[:3]]

    # Extract transition
    trans = re.findall(r'transition:\s*([^;]+)', css)
    if trans:
        props['transitions'] = list(set(t.strip()[:80] for t in trans))[:3]

    # Detect key techniques
    css_lower = css.lower()
    techniques = []
    if 'backdrop-filter' in css_lower or 'blur(' in css_lower:
        techniques.append('glassmorphism')
    if 'cubic-bezier' in css_lower:
        techniques.append('cubic-bezier')
    if 'transform:' in css_lower and ('rotate' in css_lower or 'skew' in css_lower or 'scale' in css_lower):
        techniques.append('3d-transform')
    if 'box-shadow' in css_lower and ('0 0' in css_lower or '0px 0px' in css_lower) and ('px' in css_lower):
        techniques.append('glow-shadow')
    if 'border-radius:\s*0' in css_lower or 'border-radius:\s*0px' in css_lower:
        techniques.append('sharp-corners')
    if 'text-shadow' in css_lower:
        techniques.append('text-shadow')
    if 'gradient' in css_lower:
        techniques.append('gradient')
    if '@keyframes' in css_lower:
        techniques.append('animation')
    if 'filter:' in css_lower and 'blur' not in css_lower:
        techniques.append('filter-effect')
    if 'clip-path' in css_lower:
        techniques.append('clip-path')
    if 'mask-' in css_lower:
        techniques.append('css-mask')
    if 'perspective' in css_lower:
        techniques.append('perspective')
    if 'uppercase' in css_lower or 'text-transform' in css_lower:
        techniques.append('typography-transform')
    props['techniques'] = techniques

    # Extract font-family
    fonts = re.findall(r'font-family:\s*([^;]+)', css)
    if fonts:
        props['fonts'] = list(set(f.strip().replace('"','').replace("'",'')[:60] for f in fonts))[:3]

    return props


def extract_html_techniques(html):
    """Detect techniques from HTML structure."""
    techs = []
    if '<details>' in html:
        techs.append('details-accordion')
    if '<input' in html and 'type="checkbox"' in html:
        techs.append('checkbox-input')
    if '<svg' in html:
        techs.append('svg-icon')
    if '::before' in html or '::after' in html:
        techs.append('pseudo-elements')
    return techs


all_components = []
tag_counter = Counter()
technique_counter = Counter()
category_counts = Counter()

for cat in categories:
    cat_dir = os.path.join(SRC, cat)
    if not os.path.isdir(cat_dir):
        continue
    files = glob.glob(os.path.join(cat_dir, '*.html'))
    category_counts[cat] = len(files)

    for fpath in files:
        try:
            with open(fpath, encoding='utf-8') as f:
                content = f.read()
        except:
            continue

        # Extract author and tags from CSS comment
        author = ''
        tags = []
        css_match = re.search(r'/\*\s*From Uiverse\.io by\s+(\S+)\s*-\s*Tags:\s*(.*?)\s*\*/', content)
        if css_match:
            author = css_match.group(1)
            tags = [t.strip().lower() for t in css_match.group(2).split(',') if t.strip()]
        else:
            # Try HTML comment
            html_match = re.search(r'<!--\s*From Uiverse\.io by\s+(\S+).*?Tags:\s*(.*?)\s*-->', content)
            if html_match:
                author = html_match.group(1)
                tags = [t.strip().lower() for t in html_match.group(2).split(',') if t.strip()]

        for t in tags:
            tag_counter[t] += 1

        # Extract CSS
        style_match = re.search(r'<style>(.*?)</style>', content, re.DOTALL)
        css = style_match.group(1) if style_match else ''

        # Extract HTML (everything before <style>)
        html = content.split('<style>')[0].strip() if '<style>' in content else content

        # Remove HTML comments from markup
        html = re.sub(r'<!--.*?-->', '', html, flags=re.DOTALL).strip()

        css_props = extract_css_values(css)
        html_techs = extract_html_techniques(content)

        all_techs = css_props.get('techniques', []) + html_techs
        for t in all_techs:
            technique_counter[t] += 1

        fname = os.path.basename(fpath)

        all_components.append({
            'id': fname.replace('.html', ''),
            'cat': cat,
            'author': author,
            'tags': tags,
            'html': html[:2000],  # Cap at 2000 chars
            'css': css[:3000],     # Cap at 3000 chars
            'colors': css_props.get('colors', []),
            'radii': css_props.get('radii', []),
            'shadows': css_props.get('shadows', []),
            'techniques': all_techs,
        })

print(f"Parsed {len(all_components)} components from {sum(category_counts.values())} files")
print(f"Categories: {dict(category_counts)}")
print(f"Top 30 tags: {tag_counter.most_common(30)}")
print(f"Top 20 techniques: {technique_counter.most_common(20)}")

# Write JSON
json_path = os.path.join(DST, 'galaxy_components.json')
with open(json_path, 'w', encoding='utf-8') as f:
    json.dump({
        'components': all_components,
        'tag_counts': dict(tag_counter.most_common()),
        'technique_counts': dict(technique_counter.most_common()),
        'category_counts': dict(category_counts),
    }, f, ensure_ascii=False, separators=(',', ':'))
print(f"Written: {json_path} ({os.path.getsize(json_path):,} bytes)")
