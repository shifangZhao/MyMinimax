class MatcherWord {

  const MatcherWord(this.word, {this.isRegex = false, this.pattern, this.displayName});
  final String word;
  final bool isRegex;
  final RegExp? pattern;
  final String? displayName;

  bool matches(String text) {
    final t = text.toLowerCase();
    if (isRegex) {
      return pattern?.hasMatch(t) ?? false;
    }
    return t.contains(word.toLowerCase());
  }
}

class WordGroup {

  const WordGroup({
    this.requiredWords = const [],
    this.normalWords = const [],
    this.displayName,
    this.maxCount = 0,
  });
  final List<MatcherWord> requiredWords;
  final List<MatcherWord> normalWords;
  final String? displayName;
  final int maxCount;

  bool matches(String title) {
    if (requiredWords.isEmpty && normalWords.isEmpty) return true;
    for (final w in requiredWords) {
      if (!w.matches(title)) return false;
    }
    if (normalWords.isEmpty) return requiredWords.isNotEmpty;
    for (final w in normalWords) {
      if (w.matches(title)) return true;
    }
    return false;
  }
}

class FilterConfig {

  const FilterConfig({
    this.wordGroups = const [],
    this.filterWords = const [],
    this.globalFilters = const [],
  });

  factory FilterConfig.empty() => const FilterConfig();
  final List<WordGroup> wordGroups;
  final List<MatcherWord> filterWords;
  final List<String> globalFilters;

  bool get isEmpty => wordGroups.isEmpty && filterWords.isEmpty && globalFilters.isEmpty;

  bool matches(String title) {
    if (title.isEmpty) return false;
    final t = title.toLowerCase();

    // Global filter: any match = reject
    for (final gf in globalFilters) {
      if (t.contains(gf.toLowerCase())) return false;
    }

    // Group-level filter (!word): any match = reject
    for (final fw in filterWords) {
      if (fw.matches(title)) return false;
    }

    // No groups = show all (after filters pass)
    if (wordGroups.isEmpty) return true;

    // Any group match = accept
    for (final group in wordGroups) {
      if (group.matches(title)) return true;
    }
    return false;
  }

  WordGroup? findMatchingGroup(String title) {
    for (final group in wordGroups) {
      if (group.matches(title)) return group;
    }
    return null;
  }
}
