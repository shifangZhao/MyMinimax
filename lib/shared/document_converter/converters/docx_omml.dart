/// Office Math Markup Language (OMML) to LaTeX converter.
/// Ported from markitdown's oMath2Latex implementation.
///
/// Converts OMML XML elements found in DOCX word/document.xml
/// into LaTeX math notation: oMathPara → $$...$$, oMath → $...$.
library;

import 'package:xml/xml.dart';

const _ommlNs = 'http://schemas.openxmlformats.org/officeDocument/2006/math';

// ─── LaTeX symbol dictionaries ────────────────────────────────────────────

const _latexEscapeChars = ['{', '}', '_', '^', '#', '&', r'$', '%', '~'];

/// Unicode math italic characters → ASCII fallback
const _mathItalicToAscii = {
  '\u{1d434}': 'A', '\u{1d435}': 'B', '\u{1d436}': 'C', '\u{1d437}': 'D',
  '\u{1d438}': 'E', '\u{1d439}': 'F', '\u{1d43a}': 'G', '\u{1d43b}': 'H',
  '\u{1d43c}': 'I', '\u{1d43d}': 'J', '\u{1d43e}': 'K', '\u{1d43f}': 'L',
  '\u{1d440}': 'M', '\u{1d441}': 'N', '\u{1d442}': 'O', '\u{1d443}': 'P',
  '\u{1d444}': 'Q', '\u{1d445}': 'R', '\u{1d446}': 'S', '\u{1d447}': 'T',
  '\u{1d448}': 'U', '\u{1d449}': 'V', '\u{1d44a}': 'W', '\u{1d44b}': 'X',
  '\u{1d44c}': 'Y', '\u{1d44d}': 'Z',
  '\u{1d44e}': 'a', '\u{1d44f}': 'b', '\u{1d450}': 'c', '\u{1d451}': 'd',
  '\u{1d452}': 'e', '\u{1d453}': 'f', '\u{1d454}': 'g',
  '\u{1d456}': 'i', '\u{1d457}': 'j', '\u{1d458}': 'k', '\u{1d459}': 'l',
  '\u{1d45a}': 'm', '\u{1d45b}': 'n', '\u{1d45c}': 'o', '\u{1d45d}': 'p',
  '\u{1d45e}': 'q', '\u{1d45f}': 'r', '\u{1d460}': 's', '\u{1d461}': 't',
  '\u{1d462}': 'u', '\u{1d463}': 'v', '\u{1d464}': 'w', '\u{1d465}': 'x',
  '\u{1d466}': 'y', '\u{1d467}': 'z',
};

const _symbolMap = {
  'α': r'\alpha', 'β': r'\beta', 'γ': r'\gamma',
  'δ': r'\delta', 'ε': r'\epsilon', 'ζ': r'\zeta',
  'η': r'\eta', 'θ': r'\theta', 'ι': r'\iota',
  'κ': r'\kappa', 'λ': r'\lambda', 'μ': r'\mu',
  'ν': r'\nu', 'ξ': r'\xi', 'π': r'\pi',
  'ρ': r'\rho', 'σ': r'\sigma', 'τ': r'\tau',
  'υ': r'\upsilon', 'φ': r'\phi', 'χ': r'\chi',
  'ψ': r'\psi', 'ω': r'\omega',
  '→': r'\rightarrow', '←': r'\leftarrow',
  '≤': r'\leq', '≥': r'\geq', '≠': r'\neq',
  '∞': r'\infty', '±': r'\pm', '∓': r'\mp',
  '×': r'\times', '÷': r'\div',
  '∈': r'\in', '∉': r'\notin',
  '∪': r'\cup', '∩': r'\cap',
  '⊂': r'\subset', '⊃': r'\supset',
  '∀': r'\forall', '∃': r'\exists',
  '∇': r'\nabla', '∂': r'\partial',
  '⋅': r'\cdot', '∘': r'\circ',
};

const _bigOperators = {
  '∑': r'\sum', '∏': r'\prod', '∐': r'\coprod',
  '∫': r'\int', '∮': r'\oint',
  '⋀': r'\bigwedge', '⋁': r'\bigvee',
  '⋂': r'\bigcap', '⋃': r'\bigcup',
  '⨀': r'\bigodot', '⨁': r'\bigoplus', '⨂': r'\bigotimes',
};

const _funcNames = {
  'sin': r'\sin', 'cos': r'\cos', 'tan': r'\tan',
  'arcsin': r'\arcsin', 'arccos': r'\arccos', 'arctan': r'\arctan',
  'sinh': r'\sinh', 'cosh': r'\cosh', 'tanh': r'\tanh',
  'sec': r'\sec', 'csc': r'\csc', 'cot': r'\cot',
  'ln': r'\ln', 'log': r'\log', 'exp': r'\exp',
  'min': r'\min', 'max': r'\max', 'lim': r'\lim',
  'det': r'\det', 'gcd': r'\gcd',
};

String _escapeLatex(String s) {
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final c = s[i];
    if (_latexEscapeChars.contains(c) && (i == 0 || s[i - 1] != '\\')) {
      buf.write('\\$c');
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}

String _mapSymbol(String s) {
  return _symbolMap[s] ?? _mathItalicToAscii[s] ?? s;
}

// ─── OMML → LaTeX converter ───────────────────────────────────────────────

class _OmmLContext { // *Pr elements keyed by localName

  _OmmLContext(this.element) : children = [] {
    for (final node in element.children) {
      if (node is! XmlElement) continue;
      if (node.name.namespaceUri != _ommlNs) continue;
      final local = node.localName;
      if (local.endsWith('Pr')) {
        props[local] = node;
      } else {
        children.add(node);
      }
    }
  }
  final XmlElement element;
  final List<XmlNode> children; // child elements (non-text, non-Pr)
  final Map<String, XmlElement> props = {};

  String? getPropVal(String prName, String attrLocal) {
    return props[prName]?.getAttribute('m:$attrLocal') ??
           props[prName]?.getAttribute('{$_ommlNs}$attrLocal');
  }
}

/// Convert a single oMath element to LaTeX.
String omathToLatex(XmlElement omath) {
  final buf = StringBuffer();
  for (final child in omath.childElements) {
    if (child.name.namespaceUri != _ommlNs) continue;
    buf.write(_convertElement(child));
  }
  return buf.toString().trim();
}

/// Pre-process DOCX XML content, replacing oMathPara and oMath elements
/// with LaTeX wrapped in w:r/w:t elements.
/// - oMathPara (block equations) → $$...$$
/// - oMath (inline equations) → $...$
String preProcessMath(String xmlContent) {
  var doc = XmlDocument.parse(xmlContent);

  // Replace oMathPara (block equations)
  for (final para in doc.findAllElements('m:oMathPara').toList()) {
    final parts = <String>[];
    for (final om in para.findAllElements('m:oMath')) {
      parts.add('\$\$${omathToLatex(om)}\$\$');
    }
    // Replace the oMathPara element with a w:p containing w:r/w:t nodes
    final replacement = XmlDocument.parse(
      '<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '${parts.map((p) => '<w:r><w:t xml:space="preserve">$p</w:t></w:r>').join('')}'
      '</w:p>',
    ).rootElement;
    final parent = para.parentElement;
    if (parent != null) {
      final idx = parent.children.indexOf(para);
      if (idx >= 0) {
        parent.children.removeAt(idx);
        parent.children.insert(idx, replacement);
      }
    }
  }

  // Replace standalone oMath (inline equations)
  for (final om in doc.findAllElements('m:oMath').toList()) {
    final latex = omathToLatex(om);
    final replacement = XmlDocument.parse(
      '<w:r xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:t xml:space="preserve">\$\$latex\$\$</w:t>'
      '</w:r>',
    ).rootElement;
    final parent = om.parentElement;
    if (parent != null) {
      final idx = parent.children.indexOf(om);
      if (idx >= 0) {
        parent.children.removeAt(idx);
        parent.children.insert(idx, replacement);
      }
    }
  }

  return doc.toXmlString();
}

/// Convert a single OMML element to LaTeX string.
String _convertElement(XmlElement el) {
  final local = el.localName;
  final ctx = _OmmLContext(el);

  switch (local) {
    // ─── Text run ───
    case 'r':
      final texts = <String>[];
      for (final t in el.findElements('m:t')) {
        var s = t.innerText;
        s = _mapSymbol(s);
        texts.add(s);
      }
      final joined = texts.join(' ');
      return joined.isNotEmpty ? _escapeLatex(joined) : '';

    // ─── Subscript / Superscript ───
    case 'sub':
      return '_{${_children(ctx)}}';
    case 'sup':
      return '^{${_children(ctx)}}';
    case 'sSub':
      return '${_childByTag(el, 'e')}_{${_childByTag(el, 'sub')}}';
    case 'sSup':
      return '${_childByTag(el, 'e')}^{${_childByTag(el, 'sup')}}';
    case 'sSubSup':
      return '${_childByTag(el, 'e')}_{${_childByTag(el, 'sub')}}^{${_childByTag(el, 'sup')}}';

    // ─── Fraction ───
    case 'f':
      final num = _childByTag(el, 'num');
      final den = _childByTag(el, 'den');
      final fType = ctx.getPropVal('fPr', 'type') ?? 'bar';
      switch (fType) {
        case 'skw':
          return '^{$num}\\!/\\!_{$den}';
        case 'noBar':
          return '\\genfrac{}{}{0pt}{}{$num}{$den}';
        case 'lin':
          return '$num/$den';
        default:
          return '\\frac{$num}{$den}';
      }

    // ─── Radical ───
    case 'rad':
      final deg = _childByTag(el, 'deg');
      final e = _childByTag(el, 'e');
      if (deg.isNotEmpty) {
        return '\\sqrt[$deg]{$e}';
      }
      return '\\sqrt{$e}';

    // ─── Accent ───
    case 'acc':
      final chr = ctx.getPropVal('accPr', 'chr') ?? '̂';
      final e = _childByTag(el, 'e');
      final latex = _accentMap[chr] ?? r'\hat';
      return '$latex{$e}';

    // ─── Bar (over/underline) ───
    case 'bar':
      final pos = ctx.getPropVal('barPr', 'pos') ?? 'top';
      final e = _childByTag(el, 'e');
      return pos == 'bot' ? '\\underline{$e}' : '\\overline{$e}';

    // ─── Delimiter ───
    case 'd':
      final beg = ctx.getPropVal('dPr', 'begChr') ?? '(';
      final end = ctx.getPropVal('dPr', 'endChr') ?? ')';
      final e = _childByTag(el, 'e');
      final left = beg.isEmpty ? '.' : _escapeLatex(beg);
      final right = end.isEmpty ? '.' : _escapeLatex(end);
      return '\\left$left $e \\right$right';

    // ─── Function ───
    case 'func':
      final fName = _childByTag(el, 'fName');
      final e = _childByTag(el, 'e');
      final funcName = fName.replaceAll(RegExp(r'\s+'), '');
      final latexFunc = _funcNames[funcName] ?? '\\operatorname{$funcName}';
      if (e.isNotEmpty && e != funcName) {
        return '$latexFunc\\left($e\\right)';
      }
      return latexFunc;

    // ─── N-ary (sum, product, integral) ───
    case 'nary':
      final chr = ctx.getPropVal('naryPr', 'chr');
      final bo = chr != null ? (_bigOperators[chr] ?? _mapSymbol(chr)) : r'\sum';
      final sub = _childByTag(el, 'sub');
      final sup = _childByTag(el, 'sup');
      final e = _childByTag(el, 'e');
      var result = bo;
      if (sub.isNotEmpty) result += '_{$sub}';
      if (sup.isNotEmpty) result += '^{$sup}';
      if (e.isNotEmpty && e != sub && e != sup) result += ' $e';
      return result;

    // ─── Lower/Upper limits ───
    case 'limLow':
      final e = _childByTag(el, 'e');
      final lim = _childByTag(el, 'lim');
      return '\\lim_{$lim} $e';
    case 'limUpp':
      final e = _childByTag(el, 'e');
      final lim = _childByTag(el, 'lim');
      return '\\overset{$lim}{$e}';

    // ─── Matrix ───
    case 'm':
      final rows = <String>[];
      for (final mr in el.findElements('m:mr')) {
        final cells = <String>[];
        for (final e in mr.findElements('m:e')) {
          cells.add(_children(_OmmLContext(e)));
        }
        rows.add(cells.join(' & '));
      }
      return '\\begin{matrix}${rows.join(' \\\\ ')}end{matrix}';

    // ─── Array (equation array) ───
    case 'eqArr':
      final items = <String>[];
      for (final e in el.findElements('m:e')) {
        items.add(_children(_OmmLContext(e)));
      }
      return '\\begin{array}{c}${items.join(' \\\\ ')}end{array}';

    // ─── Group character ───
    case 'groupChr':
      final chr = ctx.getPropVal('groupChrPr', 'chr');
      final e = _childByTag(el, 'e');
      if (chr != null) {
        return '$chr{$e}';
      }
      return e;

    // ─── Box ───
    case 'box':
      // <m:box> wraps content, renders as-is or with box character
      return _children(ctx);

    // ─── Border Box (LaTeX \boxed) ───
    case 'borderBox':
      return '\\boxed{${_children(ctx)}}';

    // ─── Phantom ───
    case 'phant':
      final show = ctx.getPropVal('phantPr', 'show') ?? '0';
      final body = _children(ctx);
      switch (show) {
        case '1': // hide only horizontal spacing (vertical phantom)
          return '\\vphantom{$body}';
        case '2': // hide only vertical spacing (horizontal phantom)
          return '\\hphantom{$body}';
        default: // hide everything
          return '\\phantom{$body}';
      }

    // ─── Pre-Sub-Superscript ───
    case 'sPre':
      // {}_{preSub}^{preSup}{base}
      final preSub = _childByTag(el, 'sub');
      final preSup = _childByTag(el, 'sup');
      final e = _childByTag(el, 'e');
      final parts = <String>[];
      if (preSub.isNotEmpty) parts.add('_{$preSub}');
      if (preSup.isNotEmpty) parts.add('^{$preSup}');
      var result = parts.join('');
      var base = e.isNotEmpty ? e : _children(ctx);
      // If no explicit 'e' child, rest of children are the base
      if (e.isEmpty) {
        final others = <String>[];
        for (final child in ctx.children) {
          if (child is XmlElement && child.localName != 'sub' && child.localName != 'sup') {
            others.add(_convertElement(child));
          }
        }
        base = others.join(' ');
      }
      return base.isNotEmpty ? '$result{$base}' : result;

    // ─── Math Style ───
    case 'sty':
      // sStyPr contains the style definition (display/inline/cramped)
      // We process children but style info isn't directly representable in LaTeX
      final style = ctx.getPropVal('sStyPr', 'val') ?? 'p';
      // For display style (D), we can wrap in \displaystyle but generally
      // the surrounding context ($$ vs $) handles this
      return _children(ctx);

    // ─── Pass-through / direct children ───
    case 'e':
    case 'num':
    case 'den':
    case 'deg':
    case 'fName':
    case 'lim':
      return _children(ctx);

    // ─── Pre-Sub-Superscript (not fully supported) ───
    case 'sPre':
      return _children(ctx);

    default:
      // Try to process children
      final result = _children(ctx);
      if (result.isNotEmpty) return result;
      return el.innerText;
  }
}

/// Get the LaTeX for a specific child tag, or empty string if not present.
String _childByTag(XmlElement parent, String tag) {
  for (final child in parent.childElements) {
    if (child.name.namespaceUri == _ommlNs && child.localName == tag) {
      return _convertElement(child);
    }
  }
  return '';
}

/// Convert all non-Pr children of an element to LaTeX.
String _children(_OmmLContext ctx) {
  final parts = <String>[];
  for (final child in ctx.children) {
    if (child is XmlElement) {
      final converted = _convertElement(child);
      if (converted.isNotEmpty) parts.add(converted);
    }
  }
  return parts.join(' ');
}

/// Accent character to LaTeX command map.
const _accentMap = {
  '̀': r'\grave',
  '́': r'\acute',
  '̂': r'\hat',
  '̃': r'\tilde',
  '̄': r'\bar',
  '̆': r'\breve',
  '̇': r'\dot',
  '̈': r'\ddot',
  '̌': r'\check',
  '⃗': r'\vec',
};
