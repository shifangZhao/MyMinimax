/// 99 UX guidelines from ui-ux-pro-max/ux-guidelines.csv
class UxRules {
  UxRules._();

  static const all = [
  UxRule('Navigation', 'Smooth Scroll', 'Use scroll-behavior: smooth on html element', 'Jump directly without transition', 'html { scroll-behavior: smooth; }', '<a href=\'#section\'> without CSS', 'High'),
  UxRule('Navigation', 'Sticky Navigation', 'Add padding-top to body equal to nav height', 'Let nav overlap first section content', 'pt-20 (if nav is h-20)', 'No padding compensation', 'Medium'),
  UxRule('Navigation', 'Active State', 'Highlight active nav item with color/underline', 'No visual feedback on current location', 'text-primary border-b-2', 'All links same style', 'Medium'),
  UxRule('Navigation', 'Back Button', 'Preserve navigation history properly', 'Break browser/app back button behavior', 'history.pushState()', 'location.replace()', 'High'),
  UxRule('Navigation', 'Deep Linking', 'Update URL on state/view changes', 'Static URLs for dynamic content', 'Use query params or hash', 'Single URL for all states', 'Medium'),
  UxRule('Navigation', 'Breadcrumbs', 'Use for sites with 3+ levels of depth', 'Use for flat single-level sites', 'Home > Category > Product', 'Only on deep nested pages', 'Low'),
  UxRule('Animation', 'Excessive Motion', 'Animate 1-2 key elements per view maximum', 'Animate everything that moves', 'Single hero animation', 'animate-bounce on 5+ elements', 'High'),
  UxRule('Animation', 'Duration Timing', 'Use 150-300ms for micro-interactions', 'Use animations longer than 500ms for UI', 'transition-all duration-200', 'duration-1000', 'Medium'),
  UxRule('Animation', 'Reduced Motion', 'Check prefers-reduced-motion media query', 'Ignore accessibility motion settings', '@media (prefers-reduced-motion: reduce)', 'No motion query check', 'High'),
  UxRule('Animation', 'Loading States', 'Use skeleton screens or spinners', 'Leave UI frozen with no feedback', 'animate-pulse skeleton', 'Blank screen while loading', 'High'),
  UxRule('Animation', 'Hover vs Tap', 'Use click/tap for primary interactions', 'Rely only on hover for important actions', 'onClick handler', 'onMouseEnter only', 'High'),
  UxRule('Animation', 'Continuous Animation', 'Use for loading indicators only', 'Use for decorative elements', 'animate-spin on loader', 'animate-bounce on icons', 'Medium'),
  UxRule('Animation', 'Transform Performance', 'Use transform and opacity for animations', 'Animate width/height/top/left properties', 'transform: translateY()', 'top: 10px animation', 'Medium'),
  UxRule('Animation', 'Easing Functions', 'Use ease-out for entering ease-in for exiting', 'Use linear for UI transitions', 'ease-out', 'linear', 'Low'),
  UxRule('Layout', 'Z-Index Management', 'Define z-index scale system (10 20 30 50)', 'Use arbitrary large z-index values', 'z-10 z-20 z-50', 'z-[9999]', 'High'),
  UxRule('Layout', 'Overflow Hidden', 'Test all content fits within containers', 'Blindly apply overflow-hidden', 'overflow-auto with scroll', 'overflow-hidden truncating content', 'Medium'),
  UxRule('Layout', 'Fixed Positioning', 'Account for safe areas and other fixed elements', 'Stack multiple fixed elements carelessly', 'Fixed nav + fixed bottom with gap', 'Multiple overlapping fixed elements', 'Medium'),
  UxRule('Layout', 'Stacking Context', 'Understand what creates new stacking context', 'Expect z-index to work across contexts', 'Parent with z-index isolates children', 'z-index: 9999 not working', 'Medium'),
  UxRule('Layout', 'Content Jumping', 'Reserve space for async content', 'Let images/content push layout around', 'aspect-ratio or fixed height', 'No dimensions on images', 'High'),
  UxRule('Layout', 'Viewport Units', 'Use dvh or account for mobile browser chrome', 'Use 100vh for full-screen mobile layouts', 'min-h-dvh or min-h-screen', 'h-screen on mobile', 'Medium'),
  UxRule('Layout', 'Container Width', 'Limit max-width for text content (65-75ch)', 'Let text span full viewport width', 'max-w-prose or max-w-3xl', 'Full width paragraphs', 'Medium'),
  UxRule('Touch', 'Touch Target Size', 'Minimum 44x44px touch targets', 'Tiny clickable areas', 'min-h-[44px] min-w-[44px]', 'w-6 h-6 buttons', 'High'),
  UxRule('Touch', 'Touch Spacing', 'Minimum 8px gap between touch targets', 'Tightly packed clickable elements', 'gap-2 between buttons', 'gap-0 or gap-1', 'Medium'),
  UxRule('Touch', 'Gesture Conflicts', 'Avoid horizontal swipe on main content', 'Override system gestures', 'Vertical scroll primary', 'Horizontal swipe carousel only', 'Medium'),
  UxRule('Touch', 'Tap Delay', 'Use touch-action CSS or fastclick', 'Default mobile tap handling', 'touch-action: manipulation', 'No touch optimization', 'Medium'),
  UxRule('Touch', 'Pull to Refresh', 'Disable where not needed', 'Enable by default everywhere', 'overscroll-behavior: contain', 'Default overscroll', 'Low'),
  UxRule('Touch', 'Haptic Feedback', 'Use for confirmations and important actions', 'Overuse vibration feedback', 'navigator.vibrate(10)', 'Vibrate on every tap', 'Low'),
  UxRule('Interaction', 'Focus States', 'Use visible focus rings on interactive elements', 'Remove focus outline without replacement', 'focus:ring-2 focus:ring-blue-500', 'outline-none without alternative', 'High'),
  UxRule('Interaction', 'Hover States', 'Change cursor and add subtle visual change', 'No hover feedback on clickable elements', 'hover:bg-gray-100 cursor-pointer', 'No hover style', 'Medium'),
  UxRule('Interaction', 'Active States', 'Add pressed/active state visual change', 'No feedback during interaction', 'active:scale-95', 'No active state', 'Medium'),
  UxRule('Interaction', 'Disabled States', 'Reduce opacity and change cursor', 'Confuse disabled with normal state', 'opacity-50 cursor-not-allowed', 'Same style as enabled', 'Medium'),
  UxRule('Interaction', 'Loading Buttons', 'Disable button and show loading state', 'Allow multiple clicks during processing', 'disabled={loading} spinner', 'Button clickable while loading', 'High'),
  UxRule('Interaction', 'Error Feedback', 'Show clear error messages near problem', 'Silent failures with no feedback', 'Red border + error message', 'No indication of error', 'High'),
  UxRule('Interaction', 'Success Feedback', 'Show success message or visual change', 'No confirmation of completed action', 'Toast notification or checkmark', 'Action completes silently', 'Medium'),
  UxRule('Interaction', 'Confirmation Dialogs', 'Confirm before delete/irreversible actions', 'Delete without confirmation', 'Are you sure modal', 'Direct delete on click', 'High'),
  UxRule('Accessibility', 'Color Contrast', 'Minimum 4.5:1 ratio for normal text', 'Low contrast text', '#333 on white (7:1)', '#999 on white (2.8:1)', 'High'),
  UxRule('Accessibility', 'Color Only', 'Use icons/text in addition to color', 'Red/green only for error/success', 'Red text + error icon', 'Red border only for error', 'High'),
  UxRule('Accessibility', 'Alt Text', 'Descriptive alt text for meaningful images', 'Empty or missing alt attributes', 'alt=\'Dog playing in park\'', 'alt=\'\' for content images', 'High'),
  UxRule('Accessibility', 'Heading Hierarchy', 'Use sequential heading levels h1-h6', 'Skip heading levels or misuse for styling', 'h1 then h2 then h3', 'h1 then h4', 'Medium'),
  UxRule('Accessibility', 'ARIA Labels', 'Add aria-label for icon-only buttons', 'Icon buttons without labels', 'aria-label=\'Close menu\'', '<button><Icon/></button>', 'High'),
  UxRule('Accessibility', 'Keyboard Navigation', 'Tab order matches visual order', 'Keyboard traps or illogical tab order', 'tabIndex for custom order', 'Unreachable elements', 'High'),
  UxRule('Accessibility', 'Screen Reader', 'Use semantic HTML and ARIA properly', 'Div soup with no semantics', '<nav> <main> <article>', '<div> for everything', 'Medium'),
  UxRule('Accessibility', 'Form Labels', 'Use label with for attribute or wrap input', 'Placeholder-only inputs', '<label for=\'email\'>', 'placeholder=\'Email\' only', 'High'),
  UxRule('Accessibility', 'Error Messages', 'Use aria-live or role=alert for errors', 'Visual-only error indication', 'role=\'alert\'', 'Red border only', 'High'),
  UxRule('Accessibility', 'Skip Links', 'Provide skip to main content link', 'No skip link on nav-heavy pages', 'Skip to main content link', '100 tabs to reach content', 'Medium'),
  UxRule('Performance', 'Image Optimization', 'Use appropriate size and format (WebP)', 'Unoptimized full-size images', 'srcset with multiple sizes', '4000px image for 400px display', 'High'),
  UxRule('Performance', 'Lazy Loading', 'Lazy load below-fold images and content', 'Load everything upfront', 'loading=\'lazy\'', 'All images eager load', 'Medium'),
  UxRule('Performance', 'Code Splitting', 'Split code by route/feature', 'Single large bundle', 'dynamic import()', 'All code in main bundle', 'Medium'),
  UxRule('Performance', 'Caching', 'Set appropriate cache headers', 'No caching strategy', 'Cache-Control headers', 'Every request hits server', 'Medium'),
  UxRule('Performance', 'Font Loading', 'Use font-display swap or optional', 'Invisible text during font load', 'font-display: swap', 'FOIT (Flash of Invisible Text)', 'Medium'),
  UxRule('Performance', 'Third Party Scripts', 'Load non-critical scripts async/defer', 'Synchronous third-party scripts', 'async or defer attribute', '<script src=\'...\'> in head', 'Medium'),
  UxRule('Performance', 'Bundle Size', 'Monitor and minimize bundle size', 'Ignore bundle size growth', 'Bundle analyzer', 'No size monitoring', 'Medium'),
  UxRule('Performance', 'Render Blocking', 'Inline critical CSS defer non-critical', 'Large blocking CSS files', 'Critical CSS inline', 'All CSS in head', 'Medium'),
  UxRule('Forms', 'Input Labels', 'Always show label above or beside input', 'Placeholder as only label', '<label>Email</label><input>', 'placeholder=\'Email\' only', 'High'),
  UxRule('Forms', 'Error Placement', 'Show error below related input', 'Single error message at top of form', 'Error under each field', 'All errors at form top', 'Medium'),
  UxRule('Forms', 'Inline Validation', 'Validate on blur for most fields', 'Validate only on submit', 'onBlur validation', 'Submit-only validation', 'Medium'),
  UxRule('Forms', 'Input Types', 'Use email tel number url etc', 'Text input for everything', 'type=\'email\'', 'type=\'text\' for email', 'Medium'),
  UxRule('Forms', 'Autofill Support', 'Use autocomplete attribute properly', 'Block or ignore autofill', 'autocomplete=\'email\'', 'autocomplete=\'off\' everywhere', 'Medium'),
  UxRule('Forms', 'Required Indicators', 'Use asterisk or (required) text', 'No indication of required fields', '* required indicator', 'Guess which are required', 'Medium'),
  UxRule('Forms', 'Password Visibility', 'Toggle to show/hide password', 'No visibility toggle', 'Show/hide password button', 'Password always hidden', 'Medium'),
  UxRule('Forms', 'Submit Feedback', 'Show loading then success/error state', 'No feedback after submit', 'Loading -> Success message', 'Button click with no response', 'High'),
  UxRule('Forms', 'Input Affordance', 'Use distinct input styling', 'Inputs that look like plain text', 'Border/background on inputs', 'Borderless inputs', 'Medium'),
  UxRule('Forms', 'Mobile Keyboards', 'Use inputmode attribute', 'Default keyboard for all inputs', 'inputmode=\'numeric\'', 'Text keyboard for numbers', 'Medium'),
  UxRule('Responsive', 'Mobile First', 'Start with mobile styles then add breakpoints', 'Desktop-first causing mobile issues', 'Default mobile + md: lg: xl:', 'Desktop default + max-width queries', 'Medium'),
  UxRule('Responsive', 'Breakpoint Testing', 'Test at 320 375 414 768 1024 1440', 'Only test on your device', 'Multiple device testing', 'Single device development', 'Medium'),
  UxRule('Responsive', 'Touch Friendly', 'Increase touch targets on mobile', 'Same tiny buttons on mobile', 'Larger buttons on mobile', 'Desktop-sized targets on mobile', 'High'),
  UxRule('Responsive', 'Readable Font Size', 'Minimum 16px body text on mobile', 'Tiny text on mobile', 'text-base or larger', 'text-xs for body text', 'High'),
  UxRule('Responsive', 'Viewport Meta', 'Use width=device-width initial-scale=1', 'Missing or incorrect viewport', '<meta name=\'viewport\'...>', 'No viewport meta tag', 'High'),
  UxRule('Responsive', 'Horizontal Scroll', 'Ensure content fits viewport width', 'Content wider than viewport', 'max-w-full overflow-x-hidden', 'Horizontal scrollbar on mobile', 'High'),
  UxRule('Responsive', 'Image Scaling', 'Use max-width: 100% on images', 'Fixed width images overflow', 'max-w-full h-auto', 'width=\'800\' fixed', 'Medium'),
  UxRule('Responsive', 'Table Handling', 'Use horizontal scroll or card layout', 'Wide tables breaking layout', 'overflow-x-auto wrapper', 'Table overflows viewport', 'Medium'),
  UxRule('Typography', 'Line Height', 'Use 1.5-1.75 for body text', 'Cramped or excessive line height', 'leading-relaxed (1.625)', 'leading-none (1)', 'Medium'),
  UxRule('Typography', 'Line Length', 'Limit to 65-75 characters per line', 'Full-width text on large screens', 'max-w-prose', 'Full viewport width text', 'Medium'),
  UxRule('Typography', 'Font Size Scale', 'Use consistent modular scale', 'Random font sizes', 'Type scale (12 14 16 18 24 32)', 'Arbitrary sizes', 'Medium'),
  UxRule('Typography', 'Font Loading', 'Reserve space with fallback font', 'Layout shift when fonts load', 'font-display: swap + similar fallback', 'No fallback font', 'Medium'),
  UxRule('Typography', 'Contrast Readability', 'Use darker text on light backgrounds', 'Gray text on gray background', 'text-gray-900 on white', 'text-gray-400 on gray-100', 'High'),
  UxRule('Typography', 'Heading Clarity', 'Clear size/weight difference', 'Headings similar to body text', 'Bold + larger size', 'Same size as body', 'Medium'),
  UxRule('Feedback', 'Loading Indicators', 'Show spinner/skeleton for operations > 300ms', 'No feedback during loading', 'Skeleton or spinner', 'Frozen UI', 'High'),
  UxRule('Feedback', 'Empty States', 'Show helpful message and action', 'Blank empty screens', 'No items yet. Create one!', 'Empty white space', 'Medium'),
  UxRule('Feedback', 'Error Recovery', 'Provide clear next steps', 'Error without recovery path', 'Try again button + help link', 'Error message only', 'Medium'),
  UxRule('Feedback', 'Progress Indicators', 'Step indicators or progress bar', 'No indication of progress', 'Step 2 of 4 indicator', 'No step information', 'Medium'),
  UxRule('Feedback', 'Toast Notifications', 'Auto-dismiss after 3-5 seconds', 'Toasts that never disappear', 'Auto-dismiss toast', 'Persistent toast', 'Medium'),
  UxRule('Feedback', 'Confirmation Messages', 'Brief success message', 'Silent success', 'Saved successfully toast', 'No confirmation', 'Medium'),
  UxRule('Content', 'Truncation', 'Truncate with ellipsis and expand option', 'Overflow or broken layout', 'line-clamp-2 with expand', 'Overflow or cut off', 'Medium'),
  UxRule('Content', 'Date Formatting', 'Use relative or locale-aware dates', 'Ambiguous date formats', '2 hours ago or locale format', '01/02/03', 'Low'),
  UxRule('Content', 'Number Formatting', 'Use thousand separators or abbreviations', 'Long unformatted numbers', '1.2K or 1,234', '1234567', 'Low'),
  UxRule('Content', 'Placeholder Content', 'Use realistic sample data', 'Lorem ipsum everywhere', 'Real sample content', 'Lorem ipsum', 'Low'),
  UxRule('Onboarding', 'User Freedom', 'Provide Skip and Back buttons', 'Force linear unskippable tour', 'Skip Tutorial button', 'Locked overlay until finished', 'Medium'),
  UxRule('Search', 'Autocomplete', 'Show predictions as user types', 'Require full type and enter', 'Debounced fetch + dropdown', 'No suggestions', 'Medium'),
  UxRule('Search', 'No Results', 'Show \'No results\' with suggestions', 'Blank screen or \'0 results\'', 'Try searching for X instead', 'No results found.', 'Medium'),
  UxRule('Data Entry', 'Bulk Actions', 'Allow multi-select and bulk edit', 'Single row actions only', 'Checkbox column + Action bar', 'Repeated actions per row', 'Low'),
  UxRule('AI Interaction', 'Disclaimer', 'Clearly label AI generated content', 'Present AI as human', 'AI Assistant label', 'Fake human name without label', 'High'),
  UxRule('AI Interaction', 'Streaming', 'Stream text response token by token', 'Show loading spinner for 10s+', 'Typewriter effect', 'Spinner until 100% complete', 'Medium'),
  UxRule('Spatial UI', 'Gaze Hover', 'Scale/highlight element on look', 'Static element until pinch', 'hoverEffect()', 'onTap only', 'High'),
  UxRule('Spatial UI', 'Depth Layering', 'Use glass material and z-offset', 'Flat opaque panels blocking view', '.glassBackgroundEffect()', 'bg-white', 'Medium'),
  UxRule('Sustainability', 'Auto-Play Video', 'Click-to-play or pause when off-screen', 'Auto-play high-res video loops', 'playsInline muted preload=\'none\'', 'autoplay loop', 'Medium'),
  UxRule('Sustainability', 'Asset Weight', 'Compress and lazy load 3D models', 'Load 50MB textures', 'Draco compression', 'Raw .obj files', 'Medium'),
  UxRule('AI Interaction', 'Feedback Loop', 'Thumps up/down or \'Regenerate\'', 'Static output only', 'Feedback component', 'Read-only text', 'Low'),
  UxRule('Accessibility', 'Motion Sensitivity', 'Respect prefers-reduced-motion', 'Force scroll effects', '@media (prefers-reduced-motion)', 'ScrollTrigger.create()', 'High')
  ];

  static String buildChecklist() {
    final buf = StringBuffer();
    final cats = <String, List<UxRule>>{};
    for (final r in all) { cats.putIfAbsent(r.cat, () => []).add(r); }
    buf.writeln('## Pre-Delivery UX Checklist');
    for (final e in cats.entries) {
      buf.writeln('\n### ${e.key}');
      for (final r in e.value) {
        buf.writeln('- [${r.sev == "High" ? "x" : " "}] ${r.issue}: ${r.do_}');
      }
    }
    return buf.toString();
  }

  static String get promptChecklist {
    final buf = StringBuffer();
    buf.writeln('\n## UX MUST-FOLLOW RULES');
    for (final r in all.where((r) => r.sev == 'High')) {
      buf.writeln('${r.sev}: ${r.issue} — ${r.do_} (NOT: ${r.dont})');
    }
    buf.writeln('\n## UX SHOULD-FOLLOW RULES');
    for (final r in all.where((r) => r.sev == 'Medium')) {
      buf.writeln('${r.sev}: ${r.issue} — ${r.do_}');
    }
    return buf.toString();
  }
}

class UxRule {
  const UxRule(this.cat, this.issue, this.do_, this.dont, this.good, this.bad, this.sev);
  final String cat, issue, do_, dont, good, bad, sev;
}
