import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 地图截图缓存上限。Agent 通过 set_map_cache_limit 工具调整。
final mapCacheLimitProvider = StateProvider<int>((ref) => 3);

/// 地图截图请求触发器。ToolExecutor 写入请求时间戳，MapPage 监听并执行截图。
final mapScreenshotRequestProvider = StateProvider<String?>((ref) => null);
