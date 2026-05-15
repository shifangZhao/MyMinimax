import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class UapisTrendsException implements Exception {
  UapisTrendsException(this.platformId, this.message);
  final String platformId;
  final String message;

  @override
  String toString() => 'UapisTrends error [$platformId]: $message';
}

class UapisTrendsClient {

  UapisTrendsClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Accept': 'application/json',
          },
        ));
  static const _baseUrl = 'https://uapis.cn/api/v1/misc/hotboard';

  final Dio _dio;

  /// Fetch a platform's current hot list (default mode).
  /// Returns typed record with type, update_time, optional snapshot_time, and list items.
  Future<({
    String type,
    String updateTime,
    int? snapshotTime,
    List<Map<String, dynamic>> list,
  })> fetchPlatform(
    String platformId, {
    int? timeMs,
    int limit = 200,
  }) async {
    final params = <String, dynamic>{'type': platformId};
    if (timeMs != null) params['time'] = timeMs;
    if (limit > 0) params['limit'] = limit;

    final response = await _dio.get(_baseUrl, queryParameters: params);
    final data = response.data as Map<String, dynamic>;

    final list = (data['list'] as List?) ?? [];
    final items = list.map((item) {
      final m = item as Map<String, dynamic>;
      return {
        'title': (m['title'] as String?)?.trim() ?? '',
        'url': m['url'] as String? ?? '',
        'rank': m['index'] as int? ?? 0,
        'hotValue': (m['hot_value'] as String?) ?? '',
        'extra': m['extra'] as Map<String, dynamic>? ?? const <String, dynamic>{},
        'cover': m['cover'] as String? ?? '',
      };
    }).where((item) => (item['title'] as String).isNotEmpty).toList();

    return (
      type: data['type'] as String? ?? platformId,
      updateTime: data['update_time'] as String? ?? '',
      snapshotTime: data['snapshot_time'] as int?,
      list: items,
    );
  }

  /// Search mode: keyword + optional time range.
  Future<({
    String type,
    String keyword,
    int count,
    List<Map<String, dynamic>> results,
  })> searchPlatform(
    String platformId, {
    required String keyword,
    int? timeStart,
    int? timeEnd,
    int limit = 200,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final params = <String, dynamic>{
      'type': platformId,
      'keyword': keyword,
      'time_start': timeStart ?? (nowMs - 86400000), // default: 24h ago
      'time_end': timeEnd ?? nowMs,
    };
    if (limit > 0) params['limit'] = limit;

    final response = await _dio.get(_baseUrl, queryParameters: params);
    final data = response.data as Map<String, dynamic>;

    final results = (data['results'] as List?) ?? [];
    final items = results.map((item) {
      final m = item as Map<String, dynamic>;
      return {
        'title': (m['title'] as String?)?.trim() ?? '',
        'url': m['url'] as String? ?? '',
        'rank': 0, // search mode has no rank
        'hotValue': (m['hot_value'] as String?) ?? '',
        'extra': const <String, dynamic>{},
        'cover': '',
      };
    }).where((item) => (item['title'] as String).isNotEmpty).toList();

    return (
      type: data['type'] as String? ?? platformId,
      keyword: data['keyword'] as String? ?? keyword,
      count: data['count'] as int? ?? items.length,
      results: items,
    );
  }

  /// Fetch all platforms with concurrency control and 429 retry.
  /// Returns per-platform results and a list of platform IDs that failed.
  Future<({
    Map<String, List<Map<String, dynamic>>> results,
    List<String> failed,
  })> fetchAll(
    List<String> platformIds, {
    int intervalMs = 800, // delay between chunks
  }) async {
    final results = <String, List<Map<String, dynamic>>>{};
    final failed = <String>[];
    const maxRetries = 2;
    const concurrency = 2;

    Future<({
      String id,
      bool ok,
      List<Map<String, dynamic>>? data,
      Object? err,
    })> fetchOne(String id) async {
      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          final r = await fetchPlatform(id);
          return (id: id, ok: true, data: r.list, err: null);
        } on DioException catch (e) {
          final statusCode = e.response?.statusCode;
          if (statusCode == 429 && attempt < maxRetries) {
            final delayMs = (500 * (1 << attempt)).clamp(500, 4000);
            debugPrint('[UapisTrends] $id 429 rate-limited, retry in ${delayMs}ms (attempt ${attempt + 1})');
            await Future.delayed(Duration(milliseconds: delayMs));
            continue;
          }
          return (id: id, ok: false, data: null, err: e);
        } catch (e) {
          print('[uapis] error: \$e');
          return (id: id, ok: false, data: null, err: e);
        }
      }
      return (id: id, ok: false, data: null, err: 'max retries exceeded');
    }

    for (int i = 0; i < platformIds.length; i += concurrency) {
      final chunk = platformIds.skip(i).take(concurrency).toList();
      final chunkResults = await Future.wait(chunk.map(fetchOne));
      for (final r in chunkResults) {
        if (r.ok) {
          results[r.id] = r.data!;
        } else {
          failed.add(r.id);
          debugPrint('[UapisTrends] ${r.id} failed: ${r.err}');
        }
      }
      if (i + concurrency < platformIds.length) {
        await Future.delayed(Duration(milliseconds: intervalMs));
      }
    }
    return (results: results, failed: failed);
  }
}
