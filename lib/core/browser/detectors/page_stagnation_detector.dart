/// Tracks page state changes across agent steps to detect when
/// the page is not responding to actions.
///
/// Uses a lightweight fingerprint (URL + element count + text hash)
/// rather than full DOM comparison. Consecutive identical fingerprints
/// signal that the agent's actions are not producing visible changes.
class PageStagnationDetector {
  String? _previousFingerprint;
  int _consecutiveStagnantPages = 0;

  /// Record the current page state.
  /// Returns the number of consecutive stagnant pages.
  int record(String url, int elementCount, String pageText) {
    final fp = '$url|$elementCount|${pageText.hashCode}';
    if (_previousFingerprint == fp) {
      _consecutiveStagnantPages++;
    } else {
      _consecutiveStagnantPages = 0;
    }
    _previousFingerprint = fp;
    return _consecutiveStagnantPages;
  }

  /// Whether the page has been stagnant for at least [threshold] steps.
  bool isStagnant([int threshold = 3]) =>
      _consecutiveStagnantPages >= threshold;

  /// Get the appropriate nudge message for the current stagnation level.
  String? get nudgeMessage {
    if (_consecutiveStagnantPages >= 5) {
      return 'Page content has not changed across $_consecutiveStagnantPages actions. The page may not be responding. Try a completely different approach or call done.';
    }
    if (_consecutiveStagnantPages >= 3) {
      return 'Page content unchanged for $_consecutiveStagnantPages steps. Are your actions having an effect? Check browser_detect_form_result or refresh elements.';
    }
    return null;
  }

  /// Mark a navigation event — resets stagnation counter since we're
  /// intentionally on a new page.
  void onNavigation() {
    _consecutiveStagnantPages = 0;
    _previousFingerprint = null;
  }

  void reset() {
    _previousFingerprint = null;
    _consecutiveStagnantPages = 0;
  }
}
