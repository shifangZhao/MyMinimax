import '../domain/keyword_config.dart';

class KeywordFilter {
  FilterConfig parse(String content) {
    if (content.trim().isEmpty) return FilterConfig.empty();

    final wordGroups = <WordGroup>[];
    final filterWords = <MatcherWord>[];
    final globalFilters = <String>[];
    String currentSection = 'WORD_GROUPS';

    // Split by double newlines to get groups
    final blocks = content.split(RegExp(r'\n\n+'));
    for (final block in blocks) {
      final lines = block
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      if (lines.isEmpty) continue;

      // Check for section marker
      if (lines[0].startsWith('[') && lines[0].endsWith(']')) {
        final sectionName = lines[0].substring(1, lines[0].length - 1).toUpperCase();
        if (sectionName == 'GLOBAL_FILTER' || sectionName == 'WORD_GROUPS') {
          currentSection = sectionName;
          lines.removeAt(0);
        }
      }

      if (currentSection == 'GLOBAL_FILTER') {
        for (final line in lines) {
          if (!line.startsWith('!') && !line.startsWith('+') && !line.startsWith('@')) {
            globalFilters.add(line);
          }
        }
        continue;
      }

      // WORD_GROUPS processing
      final words = [...lines];
      String? groupAlias;

      if (words.isNotEmpty && words[0].startsWith('[') && words[0].endsWith(']')) {
        groupAlias = words[0].substring(1, words[0].length - 1);
        words.removeAt(0);
      }

      final requiredWords = <MatcherWord>[];
      final normalWords = <MatcherWord>[];
      int maxCount = 0;

      for (final word in words) {
        if (word.startsWith('@')) {
          final n = int.tryParse(word.substring(1));
          if (n != null && n > 0) maxCount = n;
        } else if (word.startsWith('!')) {
          filterWords.add(_parseWord(word.substring(1)));
        } else if (word.startsWith('+')) {
          requiredWords.add(_parseWord(word.substring(1)));
        } else {
          normalWords.add(_parseWord(word));
        }
      }

      if (requiredWords.isNotEmpty || normalWords.isNotEmpty) {
        final allWords = [...normalWords, ...requiredWords];
        final displayName = groupAlias ??
            allWords.map((w) => w.displayName ?? w.word).join(' / ');
        wordGroups.add(WordGroup(
          requiredWords: requiredWords,
          normalWords: normalWords,
          displayName: displayName,
          maxCount: maxCount,
        ));
      }
    }

    return FilterConfig(
      wordGroups: wordGroups,
      filterWords: filterWords,
      globalFilters: globalFilters,
    );
  }

  MatcherWord _parseWord(String raw) {
    String word = raw;
    String? displayName;

    // Check for alias: word => displayName (flexible whitespace, matching Python \s*=>\s*)
    final aliasMatch = RegExp(r'\s*=>\s*').firstMatch(word);
    if (aliasMatch != null) {
      displayName = word.substring(aliasMatch.end).trim();
      word = word.substring(0, aliasMatch.start).trim();
    }

    // Check for regex: /pattern/flags
    if (word.startsWith('/') && word.length > 2) {
      final lastSlash = word.lastIndexOf('/');
      if (lastSlash > 0) {
        final patternStr = word.substring(1, lastSlash);
        try {
          final pattern = RegExp(patternStr, caseSensitive: false);
          return MatcherWord(word, isRegex: true, pattern: pattern, displayName: displayName);
        } catch (_) {
          // Invalid regex, treat as plain text
        }
      }
    }

    return MatcherWord(word, displayName: displayName);
  }

  List<Map<String, dynamic>> apply(
    List<Map<String, dynamic>> items,
    FilterConfig config,
  ) {
    if (config.isEmpty) return items.toList();

    final results = <String, List<Map<String, dynamic>>>{};
    final matched = <Map<String, dynamic>>[];

    for (final item in items) {
      final title = item['title'] as String? ?? '';
      if (!config.matches(title)) continue;

      final group = config.findMatchingGroup(title);
      final key = group?.displayName ?? 'other';
      results.putIfAbsent(key, () => []);
      if (group == null || group.maxCount == 0 || results[key]!.length < group.maxCount) {
        results[key]!.add(item);
        matched.add(item);
      }
    }
    return matched;
  }
}
