class BrowserConstants {
  static const String homeUrl = 'https://cn.bing.com';
  static const int maxContentSize = 100 * 1024;
  static const int maxScreenshotDim = 1920;
  static const int screenshotQuality = 70;
  static const Duration defaultWaitTimeout = Duration(seconds: 3);
  static const Duration maxWaitTimeout = Duration(seconds: 10);
  static const int maxTabs = 20;

  /// JavaScript that extracts design tokens from the current page.
  /// Returns JSON with colors, typography, spacing, components, layout, interactions.
  /// Run this after the page has fully loaded (S PA frameworks may need extra settle time).
  static const String designExtractionScript = r'''
(function() {
  var result = {};

  // If you want to isolate a specific hero/section, pass ?extract=SELECTOR in the URL query.
  // Otherwise the script scans the full page body.
  var scope = document.body;
  var q = new URLSearchParams(location.search).get('extract');
  if (q) { var el = document.querySelector(q); if (el) scope = el; }

  function cs(el) { return getComputedStyle(el); }

  // ---- helpers ----
  function firstOf(selector) { return scope.querySelector(selector); }
  function allOf(selector) { return Array.from(scope.querySelectorAll(selector)); }

  // ---- 1. Color palette ----
  var palette = {};
  function pick(el, name) {
    if (!el) return;
    var s = cs(el);
    if (s.backgroundColor && s.backgroundColor !== 'rgba(0, 0, 0, 0)') palette[name+'Bg'] = s.backgroundColor;
    if (s.color && s.color !== 'rgb(0, 0, 0)') palette[name+'Fg'] = s.color;
  }
  pick(document.body, 'body');
  pick(firstOf('h1,h2,h3'), 'heading');
  pick(firstOf('a'), 'link');
  pick(firstOf('button,a[class*="btn"],a[class*="button"]'), 'button');
  pick(firstOf('header,nav,[class*="nav"]'), 'nav');
  pick(firstOf('footer'), 'footer');

  // Accent / primary — pick the most saturated non-grayscale color on the page
  var allEls = scope.querySelectorAll('*');
  var candidates = [];
  for (var i = 0; i < Math.min(allEls.length, 500); i++) {
    var s = cs(allEls[i]);
    var bg = s.backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)') continue;
    var m = bg.match(/[\d.]+/g);
    if (!m || m.length < 3) continue;
    var r = parseFloat(m[0]), g = parseFloat(m[1]), b = parseFloat(m[2]);
    var maxC = Math.max(r,g,b), minC = Math.min(r,g,b);
    var sat = maxC === 0 ? 0 : (maxC - minC) / maxC;
    if (sat > 0.3) candidates.push({color: bg, sat: sat, freq: 1});
  }
  candidates.sort(function(a,b) { return b.sat - a.sat; });
  if (candidates.length > 0) palette.accent = candidates[0].color;

  // Dark/light mode detection
  var bodyBg = cs(document.body).backgroundColor;
  var m = bodyBg.match(/[\d.]+/g);
  if (m && m.length >= 3) {
    var lum = 0.299 * parseFloat(m[0]) + 0.587 * parseFloat(m[1]) + 0.114 * parseFloat(m[2]);
    palette.mode = lum < 128 ? 'dark' : 'light';
  }
  result.colors = palette;

  // ---- 2. Typography ----
  var fonts = [];
  var seenFonts = {};
  var headings = allOf('h1,h2,h3,h4,h5,h6');
  if (headings.length === 0) headings = allOf('[class*="title"],[class*="heading"]');
  for (var j = 0; j < headings.length; j++) {
    var s = cs(headings[j]);
    var fam = s.fontFamily.split(',')[0].replace(/["']/g,'').trim();
    if (!seenFonts[fam]) { seenFonts[fam] = true; fonts.push({family: fam, size: s.fontSize, weight: s.fontWeight, role: 'heading'}); }
  }
  var bodyFont = cs(document.body).fontFamily.split(',')[0].replace(/["']/g,'').trim();
  if (!seenFonts[bodyFont]) {
    seenFonts[bodyFont] = true;
    fonts.push({family: bodyFont, size: cs(document.body).fontSize, weight: cs(document.body).fontWeight, role: 'body'});
  }
  result.fonts = fonts;

  // ---- 3. Spacing & sizing patterns ----
  var sections = allOf('section,[class*="section"],[class*="container"] > *');
  if (sections.length === 0) sections = Array.from(scope.children);
  var paddings = [], gaps = [];
  for (var k = 0; k < Math.min(sections.length, 20); k++) {
    var s = cs(sections[k]);
    if (s.paddingTop && s.paddingTop !== '0px') paddings.push(s.paddingTop);
    if (s.paddingLeft && s.paddingLeft !== '0px') paddings.push(s.paddingLeft);
    if (s.gap && s.gap !== '0px' && s.gap !== 'normal') gaps.push(s.gap);
  }

  // Max-width of main content
  var mainWidth = 'none';
  var mainEl = firstOf('main,[class*="main"],[class*="content"]') || scope;
  if (mainEl) mainWidth = cs(mainEl).maxWidth;

  result.spacing = {
    sectionPadY: [...new Set(paddings.filter(function(p) { return p.endsWith('px'); }))].sort(function(a,b){ return parseFloat(b)-parseFloat(a); }).slice(0,3),
    gaps: [...new Set(gaps)].slice(0,5),
    maxWidth: mainWidth
  };

  // ---- 4. Borders & shadows ----
  var radii = [], shadows = [];
  for (var l = 0; l < Math.min(allEls.length, 300); l++) {
    var s = cs(allEls[l]);
    var r = s.borderRadius;
    if (r && r !== '0px' && r !== '0px 0px 0px 0px') radii.push(r.split(' ')[0]);
    var sh = s.boxShadow;
    if (sh && sh !== 'none') shadows.push(sh);
  }
  result.borders = {
    radii: [...new Set(radii)].slice(0,8),
    shadows: [...new Set(shadows)].slice(0,6)
  };

  // ---- 5. Component patterns ----
  var components = {};

  // Button
  var btnEl = firstOf('button,a[class*="btn"],a[class*="button"],[class*="cta"] a,[class*="cta"] button');
  if (btnEl) {
    var bs = cs(btnEl);
    components.button = {
      padding: bs.padding, fontSize: bs.fontSize, fontWeight: bs.fontWeight,
      borderRadius: bs.borderRadius, backgroundColor: bs.backgroundColor,
      color: bs.color, border: bs.border, boxShadow: bs.boxShadow,
      transition: bs.transition
    };
  }

  // Card
  var cardEl = firstOf('[class*="card"],article,li[class*="item"]');
  if (cardEl) {
    var s = cs(cardEl);
    components.card = {
      padding: s.padding, borderRadius: s.borderRadius,
      backgroundColor: s.backgroundColor, boxShadow: s.boxShadow,
      border: s.border, transition: s.transition
    };
  }

  // Nav / header
  var navEl = firstOf('header,nav,[class*="nav"],[class*="header"]');
  if (navEl) {
    var ns = cs(navEl);
    components.nav = {
      height: ns.height, padding: ns.padding,
      backgroundColor: ns.backgroundColor, backdropFilter: ns.backdropFilter,
      position: ns.position, boxShadow: ns.boxShadow,
      borderBottom: ns.borderBottom, zIndex: ns.zIndex
    };
  }
  result.components = components;

  // ---- 6. Layout structure ----
  result.layout = {
    sections: sections.length || scope.children.length,
    // Count columns in a grid-ish container
    gridColumns: (function() {
      var grid = firstOf('[class*="grid"],[class*="cards"],[class*="list"]');
      if (!grid) return 1;
      var gs = cs(grid);
      if (gs.gridTemplateColumns && gs.gridTemplateColumns !== 'none') {
        return gs.gridTemplateColumns.split(' ').length;
      }
      return Math.max(1, Math.floor(grid.children.length / 2));
    })(),
    stickyElements: allOf('[style*="position:sticky"],[style*="position: fixed"]').length +
                    allOf('*').filter(function(el) { var p = cs(el).position; return p === 'sticky' || p === 'fixed'; }).length
  };

  // ---- 7. Interactions & animations ----
  var interactions = [];
  // Check for smooth scroll
  var htmlScroll = cs(document.documentElement).scrollBehavior;
  if (htmlScroll === 'smooth') interactions.push({type: 'smoothScroll'});
  // Check for Lenis
  if (document.querySelector('.lenis') || typeof window.Lenis !== 'undefined') interactions.push({type: 'lenis'});
  // Scroll-snap
  var snapEl = document.querySelector('[style*="scroll-snap"]');
  if (!snapEl) snapEl = allOf('*').find(function(el) { return cs(el).scrollSnapType !== 'none'; });
  if (snapEl) interactions.push({type: 'scrollSnap', target: snapEl.tagName + (snapEl.className ? '.'+snapEl.className.split(' ')[0] : '')});

  // Animated elements on scroll
  var animated = allOf('[class*="anim"],[class*="fade"],[class*="reveal"],[data-aos]');
  if (animated.length > 0) interactions.push({type: 'scrollReveal', count: animated.length});

  // Check for nav shrink (sticky header that may change on scroll)
  if (navEl && (cs(navEl).position === 'sticky' || cs(navEl).position === 'fixed')) {
    interactions.push({type: 'stickyNav', target: navEl.tagName});
  }

  // Carousels / sliders
  var carousel = firstOf('[class*="carousel"],[class*="slider"],[class*="swiper"]');
  if (carousel) interactions.push({type: 'carousel', target: carousel.className.split(' ')[0]});

  result.interactions = interactions;

  // ---- 8. Buttons: collect variants ----
  var btnEls = allOf('button,a[class*="btn"],a[class*="button"],[role="button"]');
  var btnStyles = [];
  var seenStyles = {};
  for (var n = 0; n < Math.min(btnEls.length, 15); n++) {
    var bcs = cs(btnEls[n]);
    var key = bcs.backgroundColor + '|' + bcs.borderRadius + '|' + bcs.padding;
    if (!seenStyles[key] && bcs.backgroundColor !== 'rgba(0, 0, 0, 0)') {
      seenStyles[key] = true;
      btnStyles.push({bg: bcs.backgroundColor, color: bcs.color, radius: bcs.borderRadius, padding: bcs.padding, fontSize: bcs.fontSize, fontWeight: bcs.fontWeight});
    }
  }
  if (btnStyles.length > 0) result.buttonVariants = btnStyles;

  // ---- 9. Input fields ----
  var inputEl = firstOf('input[type="text"],input[type="email"],input[type="search"],input:not([type])');
  if (inputEl) {
    var ins = cs(inputEl);
    var inputBorder = ins.border || ins.borderBottom || '';
    var isBorderless = ins.borderBottom && (ins.borderLeft === '0px' || ins.border === '0px');
    components.input = {
      height: ins.height, padding: ins.padding, fontSize: ins.fontSize,
      borderRadius: ins.borderRadius, backgroundColor: ins.backgroundColor,
      border: inputBorder, borderBottom: ins.borderBottom,
      strategy: isBorderless ? 'borderless-bottom' :
                (ins.backgroundColor !== 'rgba(0, 0, 0, 0)' && ins.backgroundColor !== 'rgb(255, 255, 255)' ? 'filled' : 'full-border')
    };
    // Try to detect focus ring
    var focusStyle = ins.outline || ins.boxShadow || '';
    if (focusStyle) components.input.focusRing = focusStyle;
  }

  // ---- 10. Badges / tags ----
  var badgeEl = firstOf('[class*="badge"],[class*="tag"],[class*="pill"],mark,span[class*="label"]');
  if (badgeEl) {
    var bs = cs(badgeEl);
    components.badge = {
      padding: bs.padding, fontSize: bs.fontSize, fontWeight: bs.fontWeight,
      borderRadius: bs.borderRadius, backgroundColor: bs.backgroundColor,
      color: bs.color, textTransform: bs.textTransform
    };
  }

  // ---- 11. Hover-state sampling (on first button) ----
  if (btnEl) {
    var hs = window.getComputedStyle(btnEl, ':hover');
    // We can't actually get :hover styles from JS — but we can note the transition property
    var trans = cs(btnEl).transition;
    if (trans && trans !== 'all 0s ease 0s') {
      components.buttonHoverTransition = trans;
    }
  }

  // ---- 12. Typography details ----
  var bodyStyle = cs(document.body);
  result.typography = {
    bodyFontSize: bodyStyle.fontSize,
    bodyLineHeight: bodyStyle.lineHeight,
    bodyLetterSpacing: bodyStyle.letterSpacing,
    headingLineHeight: headings.length > 0 ? cs(headings[0]).lineHeight : '1.2',
    headingLetterSpacing: headings.length > 0 ? cs(headings[0]).letterSpacing : 'normal',
  };

  return JSON.stringify(result, null, 2);
})()
''';
}
