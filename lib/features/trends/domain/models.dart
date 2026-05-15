import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum PlatformCategory { news, tech, entertainment, game, music, community, other }

class TrendPlatform {

  const TrendPlatform(this.id, this.nameZh, this.nameEn, this.icon,
      {this.category = PlatformCategory.other});
  final String id;
  final String nameZh;
  final String nameEn;
  final IconData icon;
  final PlatformCategory category;

  static const List<TrendPlatform> all = [
    // ── 新闻资讯 ──
    TrendPlatform('toutiao', '今日头条', 'Toutiao', Icons.article, category: PlatformCategory.news),
    TrendPlatform('baidu', '百度热搜', 'Baidu', Icons.search, category: PlatformCategory.news),
    TrendPlatform('thepaper', '澎湃新闻', 'ThePaper', Icons.newspaper, category: PlatformCategory.news),
    TrendPlatform('qq-news', '腾讯新闻', 'QQ News', Icons.article_outlined, category: PlatformCategory.news),
    TrendPlatform('sina', '新浪新闻', 'Sina', Icons.language, category: PlatformCategory.news),
    TrendPlatform('sina-news', '新浪热榜', 'Sina News', Icons.feed, category: PlatformCategory.news),
    TrendPlatform('netease-news', '网易新闻', 'Netease', Icons.article, category: PlatformCategory.news),

    // ── 科技/开发者 ──
    TrendPlatform('zhihu', '知乎热榜', 'Zhihu', Icons.question_answer, category: PlatformCategory.tech),
    TrendPlatform('v2ex', 'V2EX', 'V2EX', Icons.forum, category: PlatformCategory.tech),
    TrendPlatform('52pojie', '吾爱破解', '52pojie', Icons.security, category: PlatformCategory.tech),
    TrendPlatform('hostloc', '全球主机', 'Hostloc', Icons.dns, category: PlatformCategory.tech),
    TrendPlatform('coolapk', '酷安', 'CoolApk', Icons.android, category: PlatformCategory.tech),
    TrendPlatform('juejin', '掘金', 'Juejin', Icons.code, category: PlatformCategory.tech),
    TrendPlatform('csdn', 'CSDN', 'CSDN', Icons.developer_mode, category: PlatformCategory.tech),
    TrendPlatform('51cto', '51CTO', '51CTO', Icons.computer, category: PlatformCategory.tech),
    TrendPlatform('sspai', '少数派', 'SSPAI', Icons.auto_awesome, category: PlatformCategory.tech),
    TrendPlatform('ifanr', '爱范儿', 'iFanr', Icons.phone_iphone, category: PlatformCategory.tech),
    TrendPlatform('ithome', 'IT之家', 'ITHome', Icons.home, category: PlatformCategory.tech),
    TrendPlatform('ithome-xijiayi', 'IT之家喜加一', 'ITHome+', Icons.celebration, category: PlatformCategory.tech),
    TrendPlatform('nodeseek', 'NodeSeek', 'NodeSeek', Icons.travel_explore, category: PlatformCategory.tech),
    TrendPlatform('hellogithub', 'HelloGitHub', 'HelloGitHub', Icons.code_off, category: PlatformCategory.tech),

    // ── 娱乐/生活 ──
    TrendPlatform('weibo', '微博热搜', 'Weibo', Icons.whatshot, category: PlatformCategory.entertainment),
    TrendPlatform('douyin', '抖音热点', 'Douyin', Icons.music_note, category: PlatformCategory.entertainment),
    TrendPlatform('kuaishou', '快手热榜', 'Kuaishou', Icons.play_circle, category: PlatformCategory.entertainment),
    TrendPlatform('bilibili', 'B站热搜', 'Bilibili', Icons.tv, category: PlatformCategory.entertainment),
    TrendPlatform('huxiu', '虎嗅', 'Huxiu', Icons.remove_red_eye, category: PlatformCategory.entertainment),
    TrendPlatform('36kr', '36氪', '36Kr', Icons.bolt, category: PlatformCategory.entertainment),
    TrendPlatform('guokr', '果壳', 'Guokr', Icons.science, category: PlatformCategory.entertainment),

    // ── 社区/论坛 ──
    TrendPlatform('tieba', '百度贴吧', 'Tieba', Icons.chat, category: PlatformCategory.community),
    TrendPlatform('douban-group', '豆瓣小组', 'Douban Group', Icons.groups, category: PlatformCategory.community),
    TrendPlatform('hupu', '虎扑', 'Hupu', Icons.sports_basketball, category: PlatformCategory.community),
    TrendPlatform('ngabbs', 'NGA', 'NGA', Icons.shield, category: PlatformCategory.community),
    TrendPlatform('jianshu', '简书', 'Jianshu', Icons.edit_note, category: PlatformCategory.community),
    TrendPlatform('zhihu-daily', '知乎日报', 'Zhihu Daily', Icons.today, category: PlatformCategory.community),

    // ── 游戏 ──
    TrendPlatform('lol', '英雄联盟', 'LoL', Icons.sports_esports, category: PlatformCategory.game),
    TrendPlatform('genshin', '原神', 'Genshin', Icons.grass, category: PlatformCategory.game),
    TrendPlatform('honkai', '崩坏', 'Honkai', Icons.auto_awesome, category: PlatformCategory.game),
    TrendPlatform('starrail', '星穹铁道', 'Star Rail', Icons.rocket, category: PlatformCategory.game),

    // ── 音乐/阅读 ──
    TrendPlatform('netease-music', '网易云音乐', 'NetEase Music', Icons.headphones, category: PlatformCategory.music),
    TrendPlatform('qq-music', 'QQ音乐', 'QQ Music', Icons.music_note, category: PlatformCategory.music),
    TrendPlatform('weread', '微信读书', 'WeRead', Icons.book, category: PlatformCategory.music),

    // ── 其他 ──
    TrendPlatform('acfun', 'A站', 'AcFun', Icons.live_tv, category: PlatformCategory.other),
    TrendPlatform('douban-movie', '豆瓣电影', 'Douban Movie', Icons.movie, category: PlatformCategory.other),
    TrendPlatform('weatheralarm', '天气预警', 'WeatherAlarm', Icons.warning, category: PlatformCategory.other),
    TrendPlatform('earthquake', '地震信息', 'Earthquake', Icons.landslide, category: PlatformCategory.other),
    TrendPlatform('history', '历史上的今天', 'History', Icons.history, category: PlatformCategory.other),
  ];

  static TrendPlatform? byId(String id) {
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Default crawl targets — only the most impactful platforms (10 of 42).
  /// Full list available via [allCrawlIds] for explicit "查全部平台" requests.
  static List<String> get defaultCrawlIds =>
      ['weibo', 'baidu', 'zhihu', 'douyin', 'toutiao', 'bilibili', 'hupu', '36kr', 'tieba', 'kuaishou'];

  static List<String> get allCrawlIds => all.map((p) => p.id).toList();

}

class TrendingNews extends Equatable {

  const TrendingNews({
    required this.title, required this.platformId, required this.rank, required this.firstCrawlTime, required this.lastCrawlTime, this.id,
    this.url = '',
    this.mobileUrl = '',
    this.crawlCount = 1,
    this.ranks = const [],
    this.hotValue = '',
    this.extra,
    this.cover = '',
  });

  factory TrendingNews.fromMap(Map<String, dynamic> map) {
    return TrendingNews(
      id: map['id'] as int?,
      title: map['title'] as String,
      platformId: map['platform_id'] as String,
      rank: map['rank'] as int,
      url: map['url'] as String? ?? '',
      mobileUrl: map['mobile_url'] as String? ?? '',
      firstCrawlTime: map['first_crawl_time'] as int,
      lastCrawlTime: map['last_crawl_time'] as int,
      crawlCount: map['crawl_count'] as int? ?? 1,
      ranks: const [],
      hotValue: map['hot_value'] as String? ?? '',
      cover: map['cover'] as String? ?? '',
    );
  }
  final int? id;
  final String title;
  final String platformId;
  final int rank;
  final String url;
  final String mobileUrl;
  final int firstCrawlTime;
  final int lastCrawlTime;
  final int crawlCount;
  final List<int> ranks;
  final String hotValue;
  final Map<String, dynamic>? extra;
  final String cover;

  Map<String, dynamic> toMapForDb() {
    return {
      'title': title,
      'platform_id': platformId,
      'rank': rank,
      'url': url,
      'mobile_url': mobileUrl,
      'first_crawl_time': firstCrawlTime,
      'last_crawl_time': lastCrawlTime,
      'crawl_count': crawlCount,
      'hot_value': hotValue,
      'extra': _extraJson,
      'cover': cover,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  String get _extraJson {
    if (extra == null) return '';
    return _jsonEncodeSafe(extra!);
  }

  static String _jsonEncodeSafe(Map<String, dynamic> m) {
    try {
      final str = m.toString();
      if (str == '{}') return '';
      return str;
    } catch (_) {
      return '';
    }
  }

  String get platformName => TrendPlatform.byId(platformId)?.nameZh ?? platformId;
  IconData get platformIcon => TrendPlatform.byId(platformId)?.icon ?? Icons.public;
  String get displayUrl => mobileUrl.isNotEmpty ? mobileUrl : url;

  /// 高排名阈值
  static const highRankThreshold = 5;

  /// 热度值解析为 int（去掉逗号等分隔符）
  int? get hotValueInt {
    if (hotValue.isEmpty) return null;
    return int.tryParse(hotValue.replaceAll(RegExp(r'[,，\s]'), ''));
  }

  /// 综合权重分 (0-100)
  /// 有 hotValue 时：rankWeight(0.4) + hotValueWeight(0.4) + hotnessWeight(0.2)
  /// 无 hotValue 时：rankWeight(0.6) + frequencyWeight(0.3) + hotnessWeight(0.1)
  double get weightScore {
    final allRanks = ranks.isEmpty ? <int>[rank] : ranks.toList();
    if (allRanks.isEmpty) return 0.0;

    double rankTotal = 0;
    int highCount = 0;
    for (final r in allRanks) {
      rankTotal += (11 - r.clamp(1, 10)).toDouble();
      if (r <= highRankThreshold) highCount++;
    }
    final avgRankScore = (rankTotal / allRanks.length) * 10; // 0-100
    final hotnessScore = (highCount / allRanks.length) * 100; // 0-100

    final hv = hotValueInt;
    if (hv != null && hv > 0) {
      // Normalize hot_value via log10: 1e3→30, 1e4→40, 1e5→50, 1e6→60, 1e7→70, 1e8→80
      final hotValueScore = (log(hv) / log(10) / 8 * 100).clamp(0.0, 100.0);
      return avgRankScore * 0.4 + hotValueScore * 0.4 + hotnessScore * 0.2;
    }

    final freqScore = (crawlCount.clamp(1, 10).toDouble()) * 10; // 0-100
    return avgRankScore * 0.6 + freqScore * 0.3 + hotnessScore * 0.1;
  }

  /// 该新闻出现在几个平台上（跨平台热度指标）
  int get crossPlatformCount => 1;

  @override
  List<Object?> get props => [id, title, platformId, rank];
}

/// 跨平台合并后的聚合新闻条目
class MergedNews extends Equatable {

  const MergedNews({
    required this.title,
    required this.sources,
    required this.weightScore,
    required this.platformCount,
  });
  final String title;
  final List<TrendingNews> sources;
  final double weightScore;
  final int platformCount;

  List<String> get platformNames => sources.map((s) => s.platformName).toSet().toList();
  String get topUrl => sources.where((s) => s.url.isNotEmpty).map((s) => s.url).firstOrNull ?? '';
  int get bestRank => sources.map((s) => s.rank).reduce((a, b) => a < b ? a : b);
  int get totalCrawls => sources.fold(0, (sum, s) => sum + s.crawlCount);

  @override
  List<Object?> get props => [title, platformCount, weightScore];
}

class CrawlRecord extends Equatable {

  const CrawlRecord({required this.crawlTime, this.id, this.totalItems = 0});

  factory CrawlRecord.fromMap(Map<String, dynamic> map) {
    return CrawlRecord(
      id: map['id'] as int?,
      crawlTime: map['crawl_time'] as int,
      totalItems: map['total_items'] as int? ?? 0,
    );
  }
  final int? id;
  final int crawlTime;
  final int totalItems;

  @override
  List<Object?> get props => [id, crawlTime];
}
