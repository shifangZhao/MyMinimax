import 'package:flutter/foundation.dart';
import '../../../core/storage/database_helper.dart';
import '../domain/models.dart';
import '../domain/keyword_config.dart';
import 'uapis_trends_client.dart';
import 'keyword_filter.dart';

/// Report mode matching original TrendRadar: daily / incremental / current
enum ReportMode {
  /// All titles crawled today (full daily summary)
  daily,

  /// Only newly appeared titles since last crawl batch
  incremental,

  /// Only titles from the latest crawl batch
  current,
}

class CrawlResult {

  const CrawlResult({
    required this.crawlTime,
    required this.totalFetched,
    required this.totalFiltered,
    required this.newsItems, required this.failedPlatforms, this.newTitlesCount = 0,
    this.mergedNews = const [],
    this.mode = ReportMode.daily,
  });
  final int crawlTime;
  final int totalFetched;
  final int totalFiltered;
  final int newTitlesCount;
  final List<TrendingNews> newsItems;
  final List<MergedNews> mergedNews;
  final List<String> failedPlatforms;
  final ReportMode mode;
}

class TrendsRepository {

  TrendsRepository()
      : _client = UapisTrendsClient(),
        _db = DatabaseHelper(),
        _keywordFilter = KeywordFilter();
  final UapisTrendsClient _client;
  final DatabaseHelper _db;
  final KeywordFilter _keywordFilter;

  /// Get today start timestamp (midnight local time in ms)
  static int todayStartMs() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    return midnight.millisecondsSinceEpoch;
  }

  Future<CrawlResult> crawlAndFilter({
    required List<String> platformIds,
    required FilterConfig filterConfig,
    int intervalMs = 800,
    ReportMode mode = ReportMode.daily,
  }) async {
    final crawlTime = DateTime.now().millisecondsSinceEpoch;

    final (:results, :failed) = await _client.fetchAll(
      platformIds,
      intervalMs: intervalMs,
    );

    // Build raw list, dedup within each platform
    final allNews = <TrendingNews>[];
    for (final entry in results.entries) {
      final seen = <String>{};
      for (final item in entry.value) {
        final title = item['title'] as String;
        if (seen.contains(title)) continue;
        seen.add(title);
        allNews.add(TrendingNews(
          title: title,
          platformId: entry.key,
          rank: item['rank'] as int,
          url: item['url'] as String? ?? '',
          mobileUrl: '',
          hotValue: item['hotValue'] as String? ?? '',
          extra: item['extra'] as Map<String, dynamic>?,
          cover: item['cover'] as String? ?? '',
          firstCrawlTime: crawlTime,
          lastCrawlTime: crawlTime,
          crawlCount: 1,
        ));
      }
    }

    // Ensure platforms exist BEFORE storing news (FK constraint) — batch
    final platforms = <({String id, String name, String category})>[];
    for (final pid in platformIds) {
      final platform = TrendPlatform.byId(pid);
      if (platform != null) {
        platforms.add((id: pid, name: platform.nameZh, category: platform.category.name));
      }
    }
    await _db.batchUpsertTrendPlatforms(platforms);

    // Detect new titles BEFORE storing — compare against DB history
    final todayStart = todayStartMs();
    final newTitleSet = await _detectNewTitles(allNews, todayStart);

    // Store news and record rank history (batch)
    await _storeNewsWithHistory(allNews, crawlTime);
    final recordId = await _db.insertTrendCrawlRecord(crawlTime, allNews.length);

    // Batch insert crawl source statuses
    final statusEntries = <({int recordId, String platformId, String status})>[
      for (final entry in results.entries)
        (recordId: recordId, platformId: entry.key, status: 'success'),
      for (final pid in failed)
        (recordId: recordId, platformId: pid, status: 'failed'),
    ];
    await _db.batchInsertTrendCrawlSourceStatuses(statusEntries);

    // Load with rank history for weight calculation
    final enrichedNews = await _enrichWithRankHistory(allNews);

    // Apply keyword filter
    final filtered = _keywordFilter.apply(
      enrichedNews.map((n) => {
        'title': n.title,
        'news': n,
        'isNew': newTitleSet.contains('${n.title}|${n.platformId}'),
      }).toList(),
      filterConfig,
    );
    var filteredNews = filtered.map((f) => f['news'] as TrendingNews).toList();

    // Apply mode-specific filtering
    filteredNews = _applyReportMode(filteredNews, mode, newTitleSet);

    // Sort by weight score descending
    filteredNews.sort((a, b) => b.weightScore.compareTo(a.weightScore));

    // Cross-platform dedup & merge
    final merged = dedupAndMerge(filteredNews);

    return CrawlResult(
      crawlTime: crawlTime,
      totalFetched: allNews.length,
      totalFiltered: filteredNews.length,
      newTitlesCount: newTitleSet.length,
      newsItems: filteredNews,
      mergedNews: merged,
      failedPlatforms: failed,
      mode: mode,
    );
  }

  /// Apply report mode filtering to the filtered news list
  /// Uses pre-store newTitleSet for accurate new-title detection
  List<TrendingNews> _applyReportMode(
    List<TrendingNews> news,
    ReportMode mode,
    Set<String> newTitleSet,
  ) {
    switch (mode) {
      case ReportMode.daily:
        return news;

      case ReportMode.incremental:
        // Only genuinely new titles (detected before DB upsert)
        return news.where((n) => newTitleSet.contains('${n.title}|${n.platformId}')).toList();

      case ReportMode.current:
        // All titles from this crawl batch pass through (already filtered by crawl context)
        return news;
    }
  }

  /// Detect which titles are newly appeared in this crawl vs all prior crawls today
  /// MUST be called BEFORE _storeNewsWithHistory to compare against existing DB state
  Future<Set<String>> _detectNewTitles(
    List<TrendingNews> currentNews,
    int todayStart,
  ) async {
    final existingMap = await _db.getTodayNewsFirstTime(todayStart);

    if (existingMap.isEmpty) {
      // First crawl today → all titles are new
      return currentNews.map((n) => '${n.title}|${n.platformId}').toSet();
    }

    final newKeys = <String>{};
    for (final news in currentNews) {
      final key = '${news.title}|${news.platformId}';
      final sourceTitles = existingMap[news.platformId];
      if (sourceTitles == null || !sourceTitles.containsKey(news.title)) {
        // Title not in today's history → genuinely new
        newKeys.add(key);
      }
    }
    return newKeys;
  }

  /// Cross-platform title dedup: groups similar titles across platforms into merged entries.
  /// Uses normalized exact match first, then fuzzy matching for near-duplicate titles.
  List<MergedNews> dedupAndMerge(List<TrendingNews> items) {
    if (items.isEmpty) return [];

    // 1) Group by normalized exact match
    final groups = <String, List<TrendingNews>>{};
    final keys = <String, String>{}; // normalized → canonical key
    for (final item in items) {
      final norm = normalizeTitle(item.title);
      final existingKey = keys[norm];
      if (existingKey != null) {
        groups[existingKey]!.add(item);
      } else {
        keys[norm] = item.title;
        groups[item.title] = [item];
      }
    }

    // 2) Merge groups whose canonical titles are fuzzy-similar
    // Pre-normalize all keys to avoid redundant regex in the O(n²) loop
    final groupKeys = groups.keys.toList();
    final normMap = <String, String>{for (final k in groupKeys) k: normalizeTitle(k)};
    final merged = <String>{};
    final mergedGroups = <String, List<TrendingNews>>{};

    for (int i = 0; i < groupKeys.length; i++) {
      if (merged.contains(groupKeys[i])) continue;
      final base = groupKeys[i];
      final combined = <TrendingNews>[...groups[base]!];
      merged.add(base);

      for (int j = i + 1; j < groupKeys.length; j++) {
        if (merged.contains(groupKeys[j])) continue;
        if (_titlesSimilarFast(normMap[base]!, normMap[groupKeys[j]]!)) {
          combined.addAll(groups[groupKeys[j]]!);
          merged.add(groupKeys[j]);
        }
      }
      mergedGroups[base] = combined;
    }

    // 3) Build MergedNews from merged groups
    final result = <MergedNews>[];
    for (final entry in mergedGroups.entries) {
      final sources = entry.value;
      final avgWeight = sources.fold(0.0, (s, n) => s + n.weightScore) / sources.length;
      result.add(MergedNews(
        title: sources.first.title,
        sources: sources,
        weightScore: avgWeight,
        platformCount: sources.map((s) => s.platformId).toSet().length,
      ));
    }
    result.sort((a, b) => b.weightScore.compareTo(a.weightScore));
    return result;
  }

  /// Compact regex for punctuation stripping. Uses \x22 for " and \x27 for '
  /// to avoid Dart string delimiter issues.
  static final _stripRe = RegExp(
      r'[\s，。！？、；：《》（）【】,.!?;:\x22\x27\[\](){}|/@#$%^&*=+~\x60_-]+');
  static String normalizeTitle(String t) {
    return t.replaceAll(_stripRe, '').trim().toLowerCase();
  }

  /// Fast pre-filtered variant: expects already-normalized strings.
  /// Uses character bigram overlap as a cheap gate before the expensive LCS.
  static bool _titlesSimilarFast(String na, String nb) {
    if (na == nb) return true;
    if (na.isEmpty || nb.isEmpty) return false;

    // Substring containment with 60% length-ratio guard (fast path)
    if (na.contains(nb) || nb.contains(na)) {
      final shorter = na.length < nb.length ? na.length : nb.length;
      final longer = na.length > nb.length ? na.length : nb.length;
      return shorter * 10 >= longer * 6;
    }

    // Bigram pre-filter: if bigram overlap < 50%, LCS can't reach 80%
    if (!_bigramPass(na, nb)) return false;

    final lcsLen = lcsLength(na, nb);
    final maxLen = na.length > nb.length ? na.length : nb.length;
    return lcsLen * 10 >= maxLen * 8;
  }

  /// Returns true if bigram Jaccard ≥ 0.5 — LCS ≥ 80% character overlap
  /// requires substantial bigram overlap. This filters ~90% of unrelated pairs
  /// before the expensive O(nm) LCS.
  static bool _bigramPass(String a, String b) {
    if (a.length < 2 || b.length < 2) return true; // too short, let LCS decide
    final aBigrams = <String>{};
    for (int i = 0; i < a.length - 1; i++) {
      aBigrams.add(a.substring(i, i + 2));
    }
    int overlap = 0;
    final seen = <String>{};
    for (int i = 0; i < b.length - 1; i++) {
      final bg = b.substring(i, i + 2);
      if (aBigrams.contains(bg) && seen.add(bg)) {
        overlap++;
      }
    }
    // Jaccard: intersection / union. union ≈ aBigrams.length + bBigrams - overlap.
    final bBigramCount = b.length - 1;
    final union = aBigrams.length + bBigramCount - overlap;
    return union > 0 && overlap * 2 >= union; // overlap/union >= 0.5
  }

  /// Two titles are "similar" if: one contains the other (with a 60% length
  /// ratio floor), or they share ≥80% character overlap via LCS.
  static bool titlesAreSimilar(String a, String b) {
    final na = normalizeTitle(a);
    final nb = normalizeTitle(b);
    if (na == nb) return true;
    if (na.isEmpty || nb.isEmpty) return false;

    // Substring containment with length-ratio guard.
    // Integer comparison avoids IEEE 754 edge cases (e.g. 6/10 != 0.6 exactly).
    if (na.contains(nb) || nb.contains(na)) {
      final shorter = na.length < nb.length ? na.length : nb.length;
      final longer = na.length > nb.length ? na.length : nb.length;
      return shorter * 10 >= longer * 6;
    }

    // Character-overlap ratio via longest-common-subsequence
    final lcsLen = lcsLength(na, nb);
    final maxLen = na.length > nb.length ? na.length : nb.length;
    return lcsLen * 10 >= maxLen * 8;
  }

  static int lcsLength(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    // Keep only the previous row for O(min(m,n)) space
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    var prev = List.filled(shorter.length + 1, 0);
    for (int i = 1; i <= longer.length; i++) {
      final curr = List.filled(shorter.length + 1, 0);
      for (int j = 1; j <= shorter.length; j++) {
        if (longer[i - 1] == shorter[j - 1]) {
          curr[j] = prev[j - 1] + 1;
        } else {
          curr[j] = prev[j] > curr[j - 1] ? prev[j] : curr[j - 1];
        }
      }
      prev = curr;
    }
    return prev[shorter.length];
  }

  Future<void> _storeNewsWithHistory(List<TrendingNews> news, int crawlTime) async {
    // Batch upsert all news items — single transaction, one fsync
    await _db.batchUpsertTrendNewsItems(news.map((item) => (
      title: item.title,
      platformId: item.platformId,
      rank: item.rank,
      url: item.url,
      mobileUrl: item.mobileUrl,
      hotValue: item.hotValue,
      extra: item.extra != null && item.extra!.isNotEmpty ? item.extra.toString() : '',
      cover: item.cover,
      firstCrawlTime: item.firstCrawlTime,
      lastCrawlTime: item.lastCrawlTime,
      crawlCount: item.crawlCount,
    )).toList());

    // Targeted ID lookup by exact (title, platform_id) pairs
    final keys = news.map((n) => (title: n.title, platformId: n.platformId)).toList();
    final idMap = await _db.getTrendNewsItemIdsByKeys(keys);

    // Batch insert rank history — single INSERT with multiple VALUES rows
    final rankEntries = <({int newsItemId, int rank, int crawlTime})>[];
    for (final item in news) {
      final key = '${item.title}|${item.platformId}';
      final newsId = idMap[key];
      if (newsId != null) {
        rankEntries.add((newsItemId: newsId, rank: item.rank, crawlTime: crawlTime));
      }
    }
    await _db.batchInsertTrendRankHistory(rankEntries);
  }

  Future<List<TrendingNews>> _enrichWithRankHistory(List<TrendingNews> news) async {
    final keys = news.map((n) => (title: n.title, platformId: n.platformId)).toList();
    final idMap = await _db.getTrendNewsItemIdsByKeys(keys);
    final ids = idMap.values.toList();
    final rankMap = ids.isNotEmpty ? await _db.getTrendRankHistoryBatch(ids) : <int, List<int>>{};

    return news.map((n) {
      final key = '${n.title}|${n.platformId}';
      final id = idMap[key];
      final ranks = id != null ? (rankMap[id] ?? <int>[]) : <int>[];
      return TrendingNews(
        id: id,
        title: n.title,
        platformId: n.platformId,
        rank: n.rank,
        url: n.url,
        mobileUrl: n.mobileUrl,
        firstCrawlTime: n.firstCrawlTime,
        lastCrawlTime: n.lastCrawlTime,
        crawlCount: ranks.length + 1,
        ranks: ranks,
      );
    }).toList();
  }

  Future<List<TrendingNews>> loadCachedNews({
    String? platformId,
    int limit = 100,
  }) async {
    final rows = await _db.getTrendNewsItems(
      platformId: platformId,
      limit: limit,
    );
    return rows.map((r) => TrendingNews.fromMap(r)).toList();
  }

  Future<int?> getLastCrawlTime() async {
    final record = await _db.getLatestTrendCrawlRecord();
    return record != null ? record['crawl_time'] as int : null;
  }

  Future<void> cleanOldNews(int retentionMs) async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - retentionMs;
    await _db.deleteOldTrendNews(cutoff);
  }

  /// Search via the remote API (server-side keyword search across time range).
  Future<List<TrendingNews>> searchRemote({
    required List<String> platformIds,
    required String keyword,
    int? timeStart,
    int? timeEnd,
    int limit = 50,
  }) async {
    final all = <TrendingNews>[];
    const concurrency = 2;

    Future<void> searchOne(String id) async {
      try {
        final r = await _client.searchPlatform(
          id,
          keyword: keyword,
          timeStart: timeStart,
          timeEnd: timeEnd,
          limit: limit,
        );
        for (final item in r.results) {
          all.add(TrendingNews(
            title: item['title'] as String? ?? '',
            platformId: id,
            rank: 0,
            url: item['url'] as String? ?? '',
            hotValue: item['hotValue'] as String? ?? '',
            firstCrawlTime: 0,
            lastCrawlTime: 0,
          ));
        }
      } catch (e) {
        debugPrint('[TrendsRepo] searchRemote platform $id error: $e');
      }
    }

    for (int i = 0; i < platformIds.length; i += concurrency) {
      final chunk = platformIds.skip(i).take(concurrency).toList();
      await Future.wait(chunk.map(searchOne));
    }
    return all;
  }

  /// Time-machine mode: crawl historical snapshot at a given timestamp.
  /// Does NOT persist to DB (historical data should not pollute current cache).
  Future<CrawlResult> crawlHistory({
    required List<String> platformIds,
    required int timestampMs,
    int limit = 100,
  }) async {
    final crawlTime = DateTime.now().millisecondsSinceEpoch;
    final allNews = <TrendingNews>[];
    final failed = <String>[];
    const concurrency = 2;

    Future<void> fetchOne(String id) async {
      try {
        final r = await _client.fetchPlatform(id, timeMs: timestampMs, limit: limit);
        for (final item in r.list) {
          allNews.add(TrendingNews(
            title: item['title'] as String? ?? '',
            platformId: id,
            rank: item['rank'] as int? ?? 0,
            url: item['url'] as String? ?? '',
            hotValue: item['hotValue'] as String? ?? '',
            firstCrawlTime: crawlTime,
            lastCrawlTime: crawlTime,
            crawlCount: 1,
          ));
        }
      } catch (e) {
        debugPrint('[TrendsRepo] crawlHistory platform $id error: $e');
        failed.add(id);
      }
    }

    for (int i = 0; i < platformIds.length; i += concurrency) {
      final chunk = platformIds.skip(i).take(concurrency).toList();
      await Future.wait(chunk.map(fetchOne));
    }

    allNews.sort((a, b) => b.weightScore.compareTo(a.weightScore));
    final merged = dedupAndMerge(allNews);

    return CrawlResult(
      crawlTime: crawlTime,
      totalFetched: allNews.length,
      totalFiltered: allNews.length,
      newTitlesCount: 0,
      newsItems: allNews,
      mergedNews: merged,
      failedPlatforms: failed,
      mode: ReportMode.current,
    );
  }

  Future<List<TrendingNews>> getLatestNews({
    List<String>? platformIds,
    int limit = 100,
  }) async {
    if (platformIds != null && platformIds.isNotEmpty) {
      final all = <TrendingNews>[];
      for (final pid in platformIds) {
        all.addAll(await loadCachedNews(platformId: pid, limit: limit));
      }
      all.sort((a, b) => a.rank.compareTo(b.rank));
      return all;
    }
    return loadCachedNews(limit: limit);
  }

  Future<List<TrendingNews>> searchNews({
    required List<String> keywords,
    List<String>? platformIds,
    int limit = 50,
  }) async {
    final all = await getLatestNews(platformIds: platformIds, limit: 200);
    if (keywords.isEmpty) return all.take(limit).toList();

    final normal = keywords
        .where((k) => !k.startsWith('!') && !k.startsWith('+'))
        .toList();
    final required = keywords
        .where((k) => k.startsWith('+'))
        .map((k) => k.substring(1))
        .toList();
    final excluded = keywords
        .where((k) => k.startsWith('!'))
        .map((k) => k.substring(1))
        .toList();

    final matched = all.where((n) {
      final t = n.title.toLowerCase();
      for (final e in excluded) {
        if (t.contains(e.toLowerCase())) return false;
      }
      for (final r in required) {
        if (!t.contains(r.toLowerCase())) return false;
      }
      if (normal.isEmpty) return required.isNotEmpty;
      for (final k in normal) {
        if (t.contains(k.toLowerCase())) return true;
      }
      return false;
    }).toList();

    return matched.take(limit).toList();
  }

  /// Detect new titles from DB history (for use without re-crawling)
  Future<Set<String>> detectNewTitlesFromHistory(
    List<String> platformIds,
    int crawlTime,
  ) async {
    final todayStart = todayStartMs();
    final existingMap = await _db.getTodayNewsFirstTime(todayStart);

    if (existingMap.isEmpty) return {};

    final latestCrawlTime = await _db.getLatestCrawlTimeToday(todayStart);
    if (latestCrawlTime == null) return {};

    // Titles whose first_time >= latestCrawlTime are from the latest batch
    // Their absence from earlier batches = they're new
    final newsRows = await _db.getTrendNewsItems(limit: 500);
    final newKeys = <String>{};
    for (final row in newsRows) {
      final firstTime = row['first_crawl_time'] as int?;
      if (firstTime != null && firstTime >= latestCrawlTime) {
        final pid = row['platform_id'] as String;
        final title = row['title'] as String;
        if (platformIds.isEmpty || platformIds.contains(pid)) {
          newKeys.add('$title|$pid');
        }
      }
    }
    return newKeys;
  }
}
