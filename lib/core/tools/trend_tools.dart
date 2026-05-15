import 'dart:convert';
import 'tool_registry.dart';
import '../../features/tools/domain/tool.dart';
import '../../features/trends/domain/models.dart' show TrendingNews, TrendPlatform;
import '../../features/trends/data/trends_repository.dart';
import '../../features/trends/data/keyword_filter.dart';
import 'tool_module.dart';
import 'tool_groups.dart';

class TrendTools implements ToolModule {
  static final TrendTools module = TrendTools._();
  TrendTools._();

  // ---- ToolModule interface ----
  @override
  String get name => 'trend';

  @override
  bool get isDynamic => false;

  @override
  Map<String, ToolGroup> get groupAssignments => {
    'getTrendingTopics': ToolGroup.trend,
    'searchTrendingTopics': ToolGroup.trend,
    'getHistoricalTrends': ToolGroup.trend,
    'analyzeTopic': ToolGroup.trend,
  };

  static final TrendsRepository _repo = TrendsRepository();

  /// 构建热搜平台ID速查表，供系统提示词使用。
  static String buildPlatformTable() {
    final buf = StringBuffer();
    buf.writeln('【热搜平台ID速查表 — 所有趋势工具可用的 platformIds】');
    buf.writeln('用法：根据用户问题在下面表格中选择最相关的平台。不需要限定时省略 platformIds 即可，系统会自动查默认平台。');
    buf.writeln();

    // 按类别分组
    final groups = <String, List<TrendPlatform>>{};
    for (final p in TrendPlatform.all) {
      final cat = p.category.name;
      groups.putIfAbsent(cat, () => []).add(p);
    }
    final catNames = {
      'news': '新闻资讯', 'tech': '科技/开发者', 'entertainment': '娱乐/生活',
      'community': '社区/论坛', 'game': '游戏', 'music': '音乐/阅读', 'other': '其他',
    };

    for (final entry in groups.entries) {
      final catZh = catNames[entry.key] ?? entry.key;
      final ids = entry.value.map((p) => '${p.id}(${p.nameZh})').join(', ');
      buf.writeln('  $catZh：$ids');
    }

    buf.writeln();
    buf.writeln('默认实时热搜查：weibo, baidu, zhihu, douyin, toutiao, bilibili, hupu, 36kr, tieba, kuaishou');
    return buf.toString();
  }

  // In-memory cache: avoid redundant crawls within a short window.
  static String? _cachedOutput;
  static List<String>? _cachedPlatformIds;
  static int? _cachedLimit;
  static int _cacheTime = 0;
  static const _cacheTtlMs = 60000; // 60 seconds

  @override
  List<ToolDefinition> get definitions => [
    ToolDefinition(
      name: 'getTrendingTopics',
      description: '【实时热搜】从30+平台抓取当前实时热搜榜单。\n'
          '\n'
          '返回格式：第一行是文字摘要（共X条、最热话题标题、爬取成功率），第二行是JSON数组：\n'
          '{"i":[{"t":"标题","p":"平台名#排名 平台名#排名","n":覆盖平台数,"w":"权重分","u":"链接"},...]}\n'
          '\n'
          '字段含义：t=title标题, p=platforms出现的平台及排名, n=跨平台数量, w=weight热度权重, u=topUrl原文链接\n'
          '\n'
          '使用场景：用户想看"今天热搜""最近有什么热点""微博上在讨论什么"→ 用此工具。\n'
          '仅限实时数据。查过去某天的历史热搜请用 getHistoricalTrends。\n'
          '\n'
          '结果为空≠出错：如果最近已爬取过，会返回缓存结果。如果所有平台网络超时，返回 success=false 并提示用 webSearch。',
      category: ToolCategory.search,
      baseRisk: 0.02,
      tags: ['network', 'trends'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'platformIds': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '平台ID。从系统提示词「热搜平台ID速查表」取 id。不传用默认。传 "all" 查全部。',
          },
          'limit': {
            'type': 'integer',
            'description': '返回条数上限，默认50，最大200。',
          },
        },
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'searchTrendingTopics',
      description: '【热搜关键词搜索】在热搜数据中搜索指定关键词。\n'
          '\n'
          '两种模式自动切换：\n'
          '1) 普通关键词（如"AI"、"华为"）→ 调用远程API搜索，支持 timeStart/timeEnd 查历史范围\n'
          '2) DSL关键词（+必含、!排除、/正则/）→ 在本地缓存中过滤，速度快\n'
          '\n'
          '返回格式：文字摘要 + JSON数组 {"i":[{"t":"标题","p":"平台名","w":"热度值","u":"链接"},...]}\n'
          '\n'
          '空结果处理："关键词"xx"暂无匹配热搜" → 说明该词当前/历史范围内确实无匹配，不代表工具出错。\n'
          '可换同义词重试，或先用 getTrendingTopics 看当前有哪些热门话题再搜索。\n'
          '\n'
          '典型用法：用户问"最近AI有什么新闻"→ searchTrendingTopics(keywords:["AI"]); '
          '用户问"有没有关于华为的热搜"→ searchTrendingTopics(keywords:["华为"])。',
      category: ToolCategory.search,
      baseRisk: 0.02,
      tags: ['network', 'trends'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'keywords': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '要搜索的关键词列表。可传单个字符串如 "AI"。普通词走远程搜索，支持历史时间范围。'
                '+前缀=必须包含, !前缀=排除, /regex/=正则匹配。',
          },
          'platformIds': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '限定平台。从系统提示词「热搜平台ID速查表」取 id。不传搜全部。',
          },
          'timeStart': {
            'type': 'integer',
            'description': '搜索起始毫秒时间戳。仅在普通关键词模式下生效。例如查昨天热搜：时间戳为24小时前。',
          },
          'timeEnd': {
            'type': 'integer',
            'description': '搜索结束毫秒时间戳。仅在普通关键词模式下生效。默认当前时间。',
          },
        },
        'required': ['keywords'],
      },
    ),
    ToolDefinition(
      name: 'analyzeTopic',
      description: '【话题深度分析】对某个热搜话题做跨平台覆盖分析。\n'
          '自动在实时热搜缓存中搜索相关新闻，输出：关联新闻数、覆盖平台列表、平台分布统计、相关新闻详情。\n'
          '\n'
          '使用场景：用户追问某个热搜的具体情况，如"这个AI新闻都在哪些平台上了？""具体怎么回事？"\n'
          '只有热搜缓存中有数据时才能分析；缓存依赖于最近调用过 getTrendingTopics 或 searchTrendingTopics。\n'
          '如果缓存为空（刚启动），先调用 getTrendingTopics 获取实时热点。',
      category: ToolCategory.search,
      baseRisk: 0.05,
      tags: ['network', 'trends', 'ai'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': '热搜话题标题。从 getTrendingTopics 或 searchTrendingTopics 的返回结果中获取的 t 字段值。',
          },
          'url': {
            'type': 'string',
            'description': '新闻原文链接（可选）。从返回结果的 u 字段获取，有链接时分析更精准。',
          },
        },
        'required': ['title'],
      },
    ),
    ToolDefinition(
      name: 'getHistoricalTrends',
      description: '【时光机·历史热搜】查询过去某个时刻的热搜快照。\n'
          '\n'
          '原理：服务端定期保存了各平台的历史热榜快照，传入平台ID + 毫秒时间戳即可回溯。\n'
          '返回格式：文字摘要（时光机快照时间、条数、来源平台数）+ JSON数组\n'
          '{"i":[{"t":"标题","p":"平台#排名","n":覆盖平台数,"w":"权重分","u":"链接"},...]}\n'
          '\n'
          '注意：并不是每个时刻都有快照。返回 success=false 说明该时间点无快照，调整时间重试即可，不是工具出错。\n'
          '\n'
          '用法：把用户提到的日期/时间转成毫秒时间戳，传入 time 参数即可。\n'
          '\n'
          '与 getTrendingTopics 的区别：getTrendingTopics 只能查此时此刻的实时热搜，本工具可以查过去。',
      category: ToolCategory.search,
      baseRisk: 0.02,
      tags: ['network', 'trends'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'platformIds': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '平台ID。从系统提示词「热搜平台ID速查表」取 id。不传用默认。',
          },
          'time': {
            'type': 'integer',
            'description': '毫秒时间戳，指定要查询的历史时刻。把用户提到的日期时间转为毫秒时间戳传入。如果无快照，调整±几小时重试。',
          },
          'limit': {
            'type': 'integer',
            'description': '返回条数上限，默认50，最大200。',
          },
        },
        'required': ['platformIds', 'time'],
      },
    ),
  ];

  static Future<ToolResult> execute(
    String toolName,
    Map<String, dynamic> params,
  ) async {
    try {
      switch (toolName) {
        case 'getTrendingTopics':
          return await _getTrendingTopics(params);
        case 'searchTrendingTopics':
          return await _searchTrendingTopics(params);
        case 'analyzeTopic':
          return await _analyzeTopic(params);
        case 'getHistoricalTrends':
          return await _getHistoricalTrends(params);
        default:
          return ToolResult(
            toolName: toolName,
            success: false,
            output: '',
            error: 'Unknown trend tool: $toolName',
          );
      }
    } catch (e) {
      print('[trend] error: \$e');
      return ToolResult(
        toolName: toolName,
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  static Future<ToolResult> _getTrendingTopics(Map<String, dynamic> params) async {
    final platformIdsRaw = params['platformIds'];
    final limit = params['limit'] as int? ?? 50;
    List<String>? platformIds;

    // Accept both ["all"] (array) and "all" (string) — LLMs aren't always schema-perfect
    if (platformIdsRaw is String && platformIdsRaw == 'all') {
      platformIds = TrendPlatform.allCrawlIds;
    } else if (platformIdsRaw is List && platformIdsRaw.isNotEmpty) {
      platformIds = platformIdsRaw.cast<String>();
      if (platformIds!.length == 1 && platformIds!.first == 'all') {
        platformIds = TrendPlatform.allCrawlIds;
      }
    }

    final finalIds = platformIds ?? TrendPlatform.defaultCrawlIds;

    // 60-second in-memory cache to avoid duplicate crawls
    final now = DateTime.now().millisecondsSinceEpoch;
    final cacheHit = _cachedOutput != null &&
        _cacheTime > 0 &&
        (now - _cacheTime) < _cacheTtlMs &&
        _cachedLimit == limit &&
        _listEquals(_cachedPlatformIds, finalIds);
    if (cacheHit) {
      return ToolResult(
        toolName: 'getTrendingTopics',
        success: true,
        output: _cachedOutput!,
      );
    }

    final filter = KeywordFilter().parse('');

    final result = await _repo.crawlAndFilter(
      platformIds: finalIds,
      filterConfig: filter,
    );

    // Build compact structured output — Agent-friendly, minimal noise
    final items = <Map<String, dynamic>>[];
    String summary = '';
    if (result.mergedNews.isNotEmpty) {
      final top = result.mergedNews.take(limit).toList();
      for (final m in top) {
        final badges = m.platformNames.map((p) {
          final src = m.sources.cast<TrendingNews?>().firstWhere((s) => s!.platformName == p, orElse: () => null);
          return src != null ? '$p#${src.rank}' : p;
        }).join(' ');
        items.add({
          't': m.title,
          'p': badges,
          'n': m.platformCount,
          'w': m.weightScore.toStringAsFixed(1),
          'u': m.topUrl,
        });
      }
      final topItem = top.isNotEmpty ? top.first : null;
      final hotCount = top.where((m) => m.platformCount >= 3).length;
      final successPlatforms = result.newsItems.map((n) => n.platformId).toSet();
      final totalAttempted = successPlatforms.length + result.failedPlatforms.length;
      final statusStr = result.failedPlatforms.isNotEmpty
          ? ' | 爬取：$successPlatforms.length/$totalAttempted 平台成功，失败[${result.failedPlatforms.join('、')}]'
          : '';
      summary = '共${top.length}条，$hotCount条🔥全网热议。'
          '${topItem != null ? "最热「${topItem.title.length > 30 ? "${topItem.title.substring(0, 30)}..." : topItem.title}」权重${topItem.weightScore.toStringAsFixed(1)}" : ""}'
          '$statusStr';
    } else if (result.totalFetched == 0 && result.failedPlatforms.isNotEmpty) {
      final failedStr = result.failedPlatforms.take(5).join(', ');
      final totalAttempted = result.failedPlatforms.length;
      final msg = totalAttempted == finalIds.length
          ? '所有热搜平台当前均无法访问（网络超时）。请改用 webSearch 搜索"热搜"或"今日热点"获取实时热搜。'
          : '热搜爬取失败：$totalAttempted 个平台超时'
              '（$failedStr${result.failedPlatforms.length > 5 ? '等' : ''}）。'
              '请尝试用 webSearch 搜索热搜。';
      return ToolResult(
        toolName: 'getTrendingTopics',
        success: false,
        output: msg,
        error: msg,
      );
    } else {
      final top = result.newsItems.take(limit).toList();
      for (final n in top) {
        items.add({
          't': n.title,
          'p': '${n.platformName}#${n.rank}',
          'n': 1,
          'w': n.weightScore.toStringAsFixed(1),
          'u': n.displayUrl,
        });
      }
      final successPlatforms2 = result.newsItems.map((n) => n.platformId).toSet();
      final statusStr2 = result.failedPlatforms.isNotEmpty
          ? ' | 爬取：${successPlatforms2.length}/${successPlatforms2.length + result.failedPlatforms.length} 平台成功，失败[${result.failedPlatforms.join('、')}]'
          : '';
      summary = '共${top.length}条，来自${successPlatforms2.length}个平台$statusStr2';
    }

    final output = '$summary\n${jsonEncode({'i': items})}';
    _cachedOutput = output;
    _cachedPlatformIds = finalIds;
    _cachedLimit = limit;
    _cacheTime = now;

    return ToolResult(
      toolName: 'getTrendingTopics',
      success: true,
      output: output,
    );
  }

  static bool _listEquals(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _isDslKeyword(String kw) {
    return kw.startsWith('!') || kw.startsWith('+') || (kw.startsWith('/') && kw.endsWith('/'));
  }

  static Future<ToolResult> _searchTrendingTopics(Map<String, dynamic> params) async {
    final keywordsRaw = params['keywords'];
    List<String> keywords;
    if (keywordsRaw is String) {
      keywords = [keywordsRaw];
    } else if (keywordsRaw is List && keywordsRaw.isNotEmpty) {
      keywords = keywordsRaw.cast<String>();
    } else {
      return const ToolResult(
        toolName: 'searchTrendingTopics',
        success: false,
        output: '',
        error: 'keywords 参数不能为空',
      );
    }

    final platformIdsRaw = params['platformIds'];
    List<String>? platformIds;
    if (platformIdsRaw is String) {
      platformIds = [platformIdsRaw];
    } else if (platformIdsRaw is List && platformIdsRaw.isNotEmpty) {
      platformIds = platformIdsRaw.cast<String>();
    }

    // Detect mode: any DSL keyword → client-side; all plain → remote search
    final hasDsl = keywords.any(_isDslKeyword);
    if (!hasDsl) {
      // Remote API search mode
      return await _searchRemote(keywords, platformIds, params);
    }

    // Client-side DSL search (existing logic)
    // Try cache first
    var news = await _repo.searchNews(
      keywords: keywords,
      platformIds: platformIds,
      limit: 30,
    );

    // Empty cache → fresh crawl + re-search
    if (news.isEmpty) {
      final finalIds = platformIds ?? TrendPlatform.defaultCrawlIds;
      final filter = KeywordFilter().parse('');
      final crawlResult = await _repo.crawlAndFilter(platformIds: finalIds, filterConfig: filter);
      if (crawlResult.totalFetched == 0 && crawlResult.failedPlatforms.isNotEmpty) {
        return const ToolResult(
          toolName: 'searchTrendingTopics',
          success: false,
          output: '热搜数据源当前不可用（所有平台网络超时）。请改用 webSearch。',
          error: '热搜数据源不可用',
        );
      }
      news = await _repo.searchNews(
        keywords: keywords,
        platformIds: platformIds,
        limit: 30,
      );
    }

    // Compact format
    final items = news.map((n) => {
      't': n.title,
      'p': '${n.platformName}#${n.rank}',
      'n': 1,
      'w': n.weightScore.toStringAsFixed(1),
      'u': n.displayUrl,
    }).toList();

    final kwStr = keywords.join('、');
    final summary = news.isEmpty
        ? '关键词"$kwStr"暂无匹配热搜'
        : '"$kwStr"匹配${news.length}条';

    return ToolResult(
      toolName: 'searchTrendingTopics',
      success: true,
      output: '$summary\n${jsonEncode({'i': items})}',
    );
  }

  static Future<ToolResult> _searchRemote(
    List<String> keywords,
    List<String>? platformIds,
    Map<String, dynamic> params,
  ) async {
    final keyword = keywords.join(' ');
    final timeStart = params['timeStart'] as int?;
    final timeEnd = params['timeEnd'] as int?;
    final searchIds = platformIds ?? TrendPlatform.defaultCrawlIds;

    final news = await _repo.searchRemote(
      platformIds: searchIds,
      keyword: keyword,
      timeStart: timeStart,
      timeEnd: timeEnd,
      limit: 30,
    );

    if (news.isEmpty) {
      return ToolResult(
        toolName: 'searchTrendingTopics',
        success: true,
        output: '关键词"$keyword"暂无匹配热搜。',
      );
    }

    news.sort((a, b) => b.weightScore.compareTo(a.weightScore));
    final items = news.map((n) => {
      't': n.title,
      'p': n.platformName,
      'w': n.hotValue,
      'u': n.url,
    }).toList();

    return ToolResult(
      toolName: 'searchTrendingTopics',
      success: true,
      output: '"$keyword"匹配${news.length}条\n${jsonEncode({'i': items})}',
    );
  }

  static Future<ToolResult> _analyzeTopic(Map<String, dynamic> params) async {
    final title = params['title'] as String? ?? '';
    final url = params['url'] as String? ?? '';

    if (title.isEmpty) {
      return const ToolResult(
        toolName: 'analyzeTopic',
        success: false,
        output: '',
        error: 'title 参数不能为空',
      );
    }

    // Search for related news across all platforms
    final keywords = title
        .split(RegExp(r'[\s，,。、！？]'))
        .where((k) => k.length > 1)
        .toList();
    final relatedNews = await _repo.searchNews(
      keywords: keywords,
      platformIds: null,
      limit: 20,
    );

    // Gather cross-platform coverage
    final platformSet = <String>{};
    final platformDetails = <String, int>{}; // platform_name → count
    final relatedItems = <Map<String, dynamic>>[];
    for (final n in relatedNews) {
      final pn = n.platformName;
      platformSet.add(pn);
      platformDetails[pn] = (platformDetails[pn] ?? 0) + 1;
      relatedItems.add({
        't': n.title,
        'p': '$pn#${n.rank}',
        'w': n.weightScore.toStringAsFixed(1),
        'u': n.displayUrl,
      });
    }

    // Build structured context output
    final buf = StringBuffer();
    buf.writeln('话题：$title');
    if (url.isNotEmpty) buf.writeln('链接：$url');
    buf.writeln();

    if (relatedNews.isEmpty) {
      buf.writeln('该话题在缓存的热搜数据中未找到直接关联新闻。');
      buf.writeln('平台覆盖：无');
    } else {
      buf.writeln('关联新闻：${relatedNews.length}条');
      buf.writeln('覆盖平台：${platformSet.length}个 (${platformSet.join('、')})');
      buf.writeln();
      buf.writeln('平台分布：');
      for (final e in platformDetails.entries) {
        buf.writeln('  ${e.key}: ${e.value}条');
      }
      buf.writeln();
      buf.writeln('相关新闻列表：');
      buf.writeln(jsonEncode({'items': relatedItems}));
    }

    return ToolResult(
      toolName: 'analyzeTopic',
      success: true,
      output: buf.toString(),
    );
  }

  static Future<ToolResult> _getHistoricalTrends(Map<String, dynamic> params) async {
    final platformIdsRaw = params['platformIds'];
    final timeMs = params['time'] as int?;
    final limit = params['limit'] as int? ?? 50;

    List<String> platformIds;
    if (platformIdsRaw is String) {
      platformIds = [platformIdsRaw];
    } else if (platformIdsRaw is List && platformIdsRaw.isNotEmpty) {
      platformIds = platformIdsRaw.cast<String>();
    } else if (platformIdsRaw is List && platformIdsRaw.isEmpty) {
      platformIds = TrendPlatform.defaultCrawlIds;
    } else {
      // 未传 platformIds，默认查常用平台
      platformIds = TrendPlatform.defaultCrawlIds;
    }

    if (timeMs == null) {
      return const ToolResult(
        toolName: 'getHistoricalTrends',
        success: false,
        output: '',
        error: 'time 参数不能为空（需要毫秒时间戳）',
      );
    }
    final result = await _repo.crawlHistory(
      platformIds: platformIds,
      timestampMs: timeMs,
      limit: limit,
    );

    if (result.totalFetched == 0 && result.failedPlatforms.isNotEmpty) {
      final failedStr = result.failedPlatforms.take(5).join(', ');
      return ToolResult(
        toolName: 'getHistoricalTrends',
        success: false,
        output: '时光机查询失败：${result.failedPlatforms.length} 个平台无历史数据'
            '（$failedStr${result.failedPlatforms.length > 5 ? '等' : ''}）。'
            '该时间点可能无快照，请尝试其他时间。',
        error: '历史快照不可用',
      );
    }

    final timeStr = DateTime.fromMillisecondsSinceEpoch(timeMs).toString().substring(0, 16);
    final items = <Map<String, dynamic>>[];
    final top = result.mergedNews.take(limit).toList();
    for (final m in top) {
      final badges = m.platformNames.map((p) {
        final src = m.sources.cast<TrendingNews?>().firstWhere((s) => s!.platformName == p, orElse: () => null);
        return src != null ? '$p#${src.rank}' : p;
      }).join(' ');
      items.add({
        't': m.title,
        'p': badges,
        'n': m.platformCount,
        'w': m.weightScore.toStringAsFixed(1),
        'u': m.topUrl,
      });
    }

    final successPlatforms = result.newsItems.map((n) => n.platformId).toSet();
    final summary = '时光机快照 $timeStr | 共${top.length}条，'
        '来自${successPlatforms.length}个平台'
        '${result.failedPlatforms.isNotEmpty ? "，失败[${result.failedPlatforms.join('、')}]" : ""}';

    return ToolResult(
      toolName: 'getHistoricalTrends',
      success: true,
      output: '$summary\n${jsonEncode({'i': items})}',
    );
  }
}
