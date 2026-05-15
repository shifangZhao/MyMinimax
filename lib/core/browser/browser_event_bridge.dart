const String browserStateReportJs = r'''
(function() {
  const report = () => {
    try {
      window.flutter_inappwebview.callHandler('browserStateReport', {
        title: document.title,
        url: window.location.href,
        scrollY: window.scrollY,
      });
    } catch(e) {}
  };
  let lastUrl = location.href;
  setInterval(() => {
    if (location.href !== lastUrl) { lastUrl = location.href; report(); }
  }, 500);
  let ticking = false;
  window.addEventListener('scroll', () => {
    if (!ticking) {
      requestAnimationFrame(() => { report(); ticking = false; });
      ticking = true;
    }
  }, {passive: true});
  report();
})();
''';
