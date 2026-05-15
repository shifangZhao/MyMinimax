import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/i18n/i18n_provider.dart';
import 'features/memory/data/foreground_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局错误处理：防止未捕获异常导致白屏崩溃
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (!kDebugMode) {
      debugPrint('[FlutterError] ${details.exception}');
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[PlatformDispatcher] $error\n$stack');
    return true;
  };

  // 预加载 i18n 翻译文件
  final i18n = await I18nService.load();

  // 初始化前台保活服务
  ForegroundService.init();

  // 全局溢出兜底：生产环境不红屏，显示灰色占位
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('[OverflowFallback] ${details.exception}');
    return Container(
      color: const Color(0x1A000000),
      child: const Center(
        child: Icon(Icons.broken_image_outlined, size: 20, color: Color(0x40000000)),
      ),
    );
  };

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(
    ProviderScope(
      overrides: [
        i18nProvider.overrideWith((ref) => I18nNotifier.withService(i18n)),
      ],
      child: const AgentApp(),
    ),
  );

  // 延迟启动前台服务，避免阻塞 UI 初始化
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ForegroundService.start();
  });
}
