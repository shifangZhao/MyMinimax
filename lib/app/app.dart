import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'quantum_splash.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'theme.dart';
import '../core/tools/browser_tools.dart';
import '../core/tools/phone_tools.dart';
import '../core/api/minimax_client.dart';
import '../core/api/time_offset_service.dart';
import '../core/tools/tool_registry.dart';
import '../core/skills/skill.dart';
import '../core/mcp/mcp_loader.dart';
import '../core/mcp/mcp_client.dart';
import '../core/mcp/mcp_registry.dart';
import '../core/skills/skill_loader.dart';
import '../core/saf/saf_client.dart';
import '../shared/utils/cache_cleaner.dart';
import '../core/hooks/hook_pipeline.dart';
// safety_hook.dart 已删除
import '../core/hooks/builtin/retry_decision_hook.dart';
import '../core/hooks/builtin/compaction_warning_hook.dart';
import '../core/hooks/builtin/browser_hooks.dart';
import '../core/hooks/builtin/pii_detect_hook.dart';
import '../core/i18n/i18n_provider.dart';
import '../features/chat/presentation/chat_page.dart';
import '../features/creation/presentation/creation_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/map/presentation/map_page.dart';
import '../features/settings/data/settings_repository.dart';
import '../core/tools/amap_tools.dart' show AmapTools;
import '../core/tools/city_policy_tools.dart' show CityPolicyTools;
import '../core/tools/trend_tools.dart' show TrendTools;
import '../core/tools/mcp_tools.dart' show McpTools;
import '../core/tools/memory_tools.dart' show MemoryTools;
import '../core/tools/orchestrator_tool.dart' show OrchestratorTools;
import '../core/skills/builtin/plan_skill.dart';
import '../core/orchestrator/orchestrator_skill.dart';

export 'theme.dart';
export '../core/api/minimax_client.dart' show MinimaxClient, QuotaInfo;
export '../features/chat/presentation/chat_page.dart' show settingsChangedProvider;

final navigationIndexProvider = StateProvider<int>((ref) => 0);
final keyboardVisibleProvider = StateProvider<bool>((ref) => false);

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final repo = SettingsRepository();
    final mode = await repo.getThemeMode();
    state = mode;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final repo = SettingsRepository();
    await repo.setThemeMode(mode);
    state = mode;
  }
}

final quotaInfoProvider = StateNotifierProvider<QuotaInfoNotifier, QuotaInfo?>((ref) {
  return QuotaInfoNotifier(ref);
});

final userAvatarProvider = StateProvider<String>((ref) => '');
final agentAvatarProvider = StateProvider<String>((ref) => '');

class QuotaInfoNotifier extends StateNotifier<QuotaInfo?> {

  QuotaInfoNotifier(this._ref) : super(null);
  final Ref _ref;
  bool _loaded = false;
  int _retryCount = 0;
  static const _maxRetries = 3;
  Timer? _refreshTimer;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    final settings = SettingsRepository();
    final apiKey = await settings.getApiKey();
    if (apiKey.isEmpty) return;

    await _loadQuotaWithRetry(apiKey);
  }

  Future<void> _loadQuotaWithRetry(String apiKey) async {
    while (_retryCount < _maxRetries) {
      try {
        final client = MinimaxClient(apiKey: apiKey);
        final quota = await client.getQuota();
        state = quota;
        _retryCount = 0;
        _scheduleAutoRefresh(quota);
        return;
      } catch (e) {
        _retryCount++;
        if (_retryCount >= _maxRetries) {
          debugPrint('QuotaInfoNotifier.load failed after $_maxRetries retries: $e');
          return;
        }
        final delay = Duration(seconds: _retryCount * 2);
        await Future.delayed(delay);
      }
    }
  }

  void _scheduleAutoRefresh(QuotaInfo quota) {
    _refreshTimer?.cancel();
    if (quota.models.isEmpty) return;

    // Find the earliest refresh time across all models
    int minRemains = quota.models
        .map((m) => m.remainsTime)
        .where((t) => t > 0)
        .fold<int>(0x7FFFFFFF, (a, b) => a < b ? a : b);

    // If no model reports a positive remainsTime, fall back to 5 minutes
    if (minRemains == 0x7FFFFFFF) minRemains = 300;

    // Add a 5-second buffer to ensure the server side has refreshed
    final delaySeconds = minRemains + 5;
    debugPrint('[Quota] auto-refresh scheduled in ${delaySeconds}s');

    _refreshTimer = Timer(Duration(seconds: delaySeconds), () {
      _loaded = false;
      _retryCount = 0;
      ensureLoaded();
    });
  }

  void setQuota(QuotaInfo quota) {
    state = quota;
    _scheduleAutoRefresh(quota);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

class AgentApp extends ConsumerWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final i18n = ref.watch(i18nProvider);
    final locale = i18n != null ? Locale(i18n.locale) : const Locale('zh');

    return MaterialApp(
      title: 'MiniMax Agent',
      theme: PixelTheme.lightTheme,
      darkTheme: PixelTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      home: const MainPage(),
    );
  }
}

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  static bool _initialized = false;
  final List<StreamSubscription> _mcpWatchers = [];
  Timer? _mcpReloadTimer;
  final List<StreamSubscription> _skillWatchers = [];
  Timer? _skillReloadTimer;
  bool _showSplash = true;
  final Completer<void> _initCompleter = Completer<void>();

  @override
  void initState() {
    super.initState();
    _initCoreSystems();
    // 安全兜底：最多 10 秒必须进主界面
    Future.delayed(const Duration(seconds: 10), () {
      if (!_initCompleter.isCompleted) {
        debugPrint('[Splash] 超时兜底：强制进入主界面');
        _initCompleter.complete();
        if (mounted) setState(() => _showSplash = false);
      }
    });
    Future.microtask(() async {
      try {
        await ref.read(quotaInfoProvider.notifier).ensureLoaded();
        await _loadAvatars();
        await Future.delayed(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('[Splash] 初始化异常: $e');
      } finally {
        if (!_initCompleter.isCompleted) {
          _initCompleter.complete();
          if (mounted) setState(() => _showSplash = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _mcpReloadTimer?.cancel();
    for (final sub in _mcpWatchers) {
      sub.cancel();
    }
    _mcpWatchers.clear();
    _skillReloadTimer?.cancel();
    for (final sub in _skillWatchers) {
      sub.cancel();
    }
    _skillWatchers.clear();
    super.dispose();
  }

  Future<void> _loadAvatars() async {
    final repo = SettingsRepository();
    final userPath = await repo.getUserAvatarPath();
    final agentPath = await repo.getAgentAvatarPath();
    final ttsModel = await repo.getTtsModel();
    final ttsVoice = await repo.getTtsVoice();
    final ttsEnabled = await repo.getTtsEnabled();
    if (mounted) {
      ref.read(userAvatarProvider.notifier).state = userPath;
      ref.read(agentAvatarProvider.notifier).state = agentPath;
      ref.read(ttsModelProvider.notifier).state = ttsModel;
      ref.read(ttsVoiceProvider.notifier).state = ttsVoice;
      ref.read(ttsEnabledProvider.notifier).state = ttsEnabled;
    }
  }

  void _initCoreSystems() {
    if (_initialized) return;
    _initialized = true;

    ToolRegistry.instance.init();
    ToolRegistry.instance.registerModule(BrowserTools.module);
    ToolRegistry.instance.registerModule(PhoneTools.module);
    ToolRegistry.instance.registerModule(AmapTools.module);
    ToolRegistry.instance.registerModule(CityPolicyTools.module);
    ToolRegistry.instance.registerModule(TrendTools.module);
    ToolRegistry.instance.registerModule(McpTools.module);
    ToolRegistry.instance.registerModule(MemoryTools.module);
    ToolRegistry.instance.registerModule(OrchestratorTools.module);

    SkillRegistry.instance.registerAll([planSkill, OrchestratorSkill.instance]);
    _restoreSkillState();

    final pipeline = HookPipeline.instance;
    pipeline.register(HookEvent.onToolFailure, retryDecisionHook, priority: 100, name: 'retry');
    pipeline.register(HookEvent.beforeSend, piiDetectHook, priority: 5, name: 'pii-detect');
    pipeline.register(HookEvent.beforeCompaction, compactionWarningHook, priority: 10, name: 'compaction');
    pipeline.register(HookEvent.onSessionStart, browserSessionStartHook, priority: 50, name: 'browser-session');
    pipeline.register(HookEvent.afterToolUse, browserPageLoadedHook, priority: 200, name: 'browser-loaded');

    // 延迟加载非关键模块，避免阻塞首帧渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferredInit();
    });

    // 自动清理 7 天前的旧缓存文件（异步，不阻塞启动）
    _autoCleanCache();
  }

  void _deferredInit() {
    TimeOffsetService.instance.calibrate();
    _warmUpWebView();
    _loadExternalSkills();
    _loadMcpServers();
  }

  void _autoCleanCache() {
    Future.microtask(() async {
      try {
        final result = await CacheCleaner.cleanOld(maxAgeDays: 7);
        if (result.deletedCount > 0) {
          debugPrint('[Cache] Auto-clean: deleted ${result.deletedCount} files, freed ${result.sizeLabel}');
        }
      } catch (_) {}
    });
  }

  /// 预热 WebView 引擎，消除首次打开浏览器的冷启动延迟。
  /// 延迟 3 秒执行，避免与地图 GLSurfaceView 初始化竞争 GL 上下文导致崩溃。
  void _warmUpWebView() {
    Timer(const Duration(seconds: 3), () {
      try {
        HeadlessInAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('about:blank')),
          onLoadStop: (controller, url) async {
            await Future.delayed(const Duration(milliseconds: 500));
            controller.dispose();
          },
        ).run();
      } catch (e) {
        debugPrint('[DeferredInit] WebView warm-up failed: $e');
      }
    });
  }

  Future<void> _restoreSkillState() async {
    final settings = SettingsRepository();
    final enabled = await settings.getEnabledSkillNames();
    SkillRegistry.instance.setEnabledAll(enabled);
  }

  Future<void> _loadExternalSkills() async {
    try {
      final settings = SettingsRepository();
      final safUri = await settings.getSafUri();

      if (safUri.isNotEmpty && SafClient.isSupported) {
        final safClient = SafClient();
        final result = await SkillLoader.loadFromSafAuto(
          safClient: safClient,
          safUri: safUri,
        );
        _applySkillLoadResult(result);
      } else {
        final appDir = await _getAppDocumentsDir();
        await _reloadAllSkills(appDir);
        await _startSkillFileWatcher(appDir);
      }
    } catch (e) {
      debugPrint('[SkillLoader] 外部 skills 加载失败: $e');
    }
  }

  void _applySkillLoadResult(SkillLoadResult result) async {
    if (result.loaded.isNotEmpty) {
      debugPrint('[SkillLoader] ${result.summarize()}');
      for (final name in result.loaded) {
        debugPrint('[SkillLoader]   加载: $name');
      }
      final settings = SettingsRepository();
      final current = await settings.getEnabledSkillNames();
      final merged = {...current, ...result.loaded};
      await settings.setEnabledSkillNames(merged.toList());
      SkillRegistry.instance.setEnabledAll(merged.toList());
    }
    if (result.errors.isNotEmpty) {
      debugPrint('[SkillLoader] 错误: ${result.errors.join("; ")}');
    }
  }

  Future<void> _reloadAllSkills(String appDir) async {
    final result = await SkillLoader.reload(appDir);
    _applySkillLoadResult(result);
    // 重载后重建监听器，覆盖新增/删除的 skill 目录
    await _startSkillFileWatcher(appDir);
  }

  void _onSkillChanged(String appDir) {
    _skillReloadTimer?.cancel();
    _skillReloadTimer = Timer(const Duration(seconds: 2), () {
      debugPrint('[SkillLoader] 检测到 SKILL.md 变更，正在热重载...');
      _reloadAllSkills(appDir);
    });
  }

  Future<void> _startSkillFileWatcher(String appDir) async {
    for (final sub in _skillWatchers) {
      sub.cancel();
    }
    _skillWatchers.clear();

    for (final relativePath in SkillLoader.scanPaths) {
      final scanDir = Directory('$appDir/$relativePath');
      if (!await scanDir.exists()) continue;

      // 监听父 skills 目录：检测子目录的增删（新 skill 创建 / 旧 skill 删除）
      final dirSub = scanDir.watch(events: FileSystemEvent.all).listen(
        (_) => _onSkillChanged(appDir),
        onError: (e) => debugPrint('[SkillLoader] 目录监听错误 ($relativePath): $e'),
      );
      _skillWatchers.add(dirSub);
      debugPrint('[SkillLoader] 已启动目录监听: $relativePath/');

      // 监听每个已有 SKILL.md 文件的修改
      await for (final entity in scanDir.list()) {
        if (entity is! Directory) continue;
        final skillMd = File('${entity.path}/SKILL.md');
        if (await skillMd.exists()) {
          final fileSub = skillMd.watch(events: FileSystemEvent.all).listen(
            (_) => _onSkillChanged(appDir),
            onError: (e) => debugPrint('[SkillLoader] 文件监听错误 (${entity.path}): $e'),
          );
          _skillWatchers.add(fileSub);
        }
      }
      debugPrint('[SkillLoader] 已启动 ${_skillWatchers.length} 个 skill 监听');
    }

    // 如果 .claude/skills 不存在，监听 .claude 目录以检测新建
    final claudeSkillsDir = Directory('$appDir/.claude/skills');
    if (!await claudeSkillsDir.exists()) {
      final claudeDir = Directory('$appDir/.claude');
      if (await claudeDir.exists()) {
        final sub = claudeDir.watch(events: FileSystemEvent.create).listen((event) {
          final path = event.path.replaceAll('\\', '/');
          if (path.endsWith('/skills') || path.contains('/skills/')) {
            _onSkillChanged(appDir);
          }
        });
        _skillWatchers.add(sub);
        debugPrint('[SkillLoader] 已启动父目录监听 (.claude/)');
      }
    }
  }

  Future<void> _loadMcpServers() async {
    try {
      final appDir = await _getAppDocumentsDir();
      await _reloadAllMcpServers(appDir);
      await _startMcpFileWatcher(appDir);
    } catch (e) {
      debugPrint('[MCP] 加载失败: $e');
    }
  }

  /// 核心重载逻辑：清空 → 文件加载 → 手动配置加载 → 工具发现 → 模块注册
  Future<void> _reloadAllMcpServers(String appDir) async {
    try {
      // 清除旧的动态模块，清空 registry
      ToolRegistry.instance.clearDynamicModules();
      McpRegistry.instance.clear();

      // 1. 从本地 .mcp.json / .claude/mcp.json 加载
      final loadResult = await McpLoader.loadFromWorkspace(appDir);
      if (loadResult.loaded.isNotEmpty) {
        debugPrint('[MCP] ${loadResult.summarize()}');
        for (final name in loadResult.loaded) {
          debugPrint('[MCP]   服务器: $name');
        }
      }
      if (loadResult.errors.isNotEmpty) {
        debugPrint('[MCP] 错误: ${loadResult.errors.join("; ")}');
      }

      // 2. 从 SettingsRepository 加载手动配置的 MCP 服务器
      final settings = SettingsRepository();
      final configuredServers = await settings.getMcpServersConfig();
      for (final config in configuredServers) {
        try {
          final serverConfig = McpServerConfig.fromJson(config['name'] as String, config);
          McpRegistry.instance.register(serverConfig);
          debugPrint('[MCP] 注册配置服务器: ${serverConfig.name}');
        } catch (e) {
          debugPrint('[MCP] 配置服务器加载失败: $e');
        }
      }

      if (McpRegistry.instance.serverCount > 0) {
        final discovered = await McpRegistry.instance.discoverAllTools();
        for (final entry in discovered.entries) {
          debugPrint('[MCP] ${entry.key}: 发现 ${entry.value.tools.length} 个工具');
        }

        final schemas = McpRegistry.instance.allToolSchemas;
        if (schemas.isNotEmpty) {
          ToolRegistry.instance.registerModule(McpToolModule.fromSchemas(schemas));
          debugPrint('[MCP] 共注入 ${schemas.length} 个 MCP 工具到 ToolRegistry (via McpToolModule)');
        }
      }
    } catch (e) {
      debugPrint('[MCP] 重载失败: $e');
    }
  }

  /// 启动 .mcp.json 文件监听，变更时自动热重载
  Future<void> _startMcpFileWatcher(String appDir) async {
    for (final sub in _mcpWatchers) {
      sub.cancel();
    }
    _mcpWatchers.clear();

    final watchedFiles = <String>{};
    for (final relativePath in McpLoader.configSearchPaths) {
      final file = File('$appDir/$relativePath');
      if (await file.exists()) {
        final sub = file.watch(events: FileSystemEvent.all).listen(
          (_) => _onMcpConfigChanged(appDir),
          onError: (e) => debugPrint('[MCP] 文件监听错误 ($relativePath): $e'),
        );
        _mcpWatchers.add(sub);
        watchedFiles.add(relativePath);
        debugPrint('[MCP] 已启动文件监听: $relativePath');
      }
    }

    // 如果有文件尚不存在，监听父目录以检测新建
    if (watchedFiles.length < McpLoader.configSearchPaths.length) {
      try {
        final dir = Directory(appDir);
        final sub = dir.watch(events: FileSystemEvent.create).listen((event) {
          final path = event.path.replaceAll('\\', '/');
          final isTarget = McpLoader.configSearchPaths.any((p) => path.endsWith('/$p'));
          if (isTarget) {
            debugPrint('[MCP] 检测到新配置文件: $path');
            _onMcpConfigChanged(appDir);
            _startMcpFileWatcher(appDir);
          }
        });
        _mcpWatchers.add(sub);
        debugPrint('[MCP] 已启动父目录监听 (等待配置文件创建)');
      } catch (_) {}
    }
  }

  void _onMcpConfigChanged(String appDir) {
    // 防抖：2 秒内的多次变更合并为一次重载
    _mcpReloadTimer?.cancel();
    _mcpReloadTimer = Timer(const Duration(seconds: 2), () {
      debugPrint('[MCP] 检测到 .mcp.json 变更，正在热重载...');
      _reloadAllMcpServers(appDir);
    });
  }

  Future<String> _getAppDocumentsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navigationIndexProvider);

    final pages = <Widget>[
      ChatPage(onNavigateToSettings: () => ref.read(navigationIndexProvider.notifier).state = 3),
      const MapPage(),
      const CreationPage(),
      const SettingsPage(),
    ];

    void goToTab(int index) {
      if (index == currentIndex) return;
      ref.read(navigationIndexProvider.notifier).state = index;
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: _showSplash
          ? QuantumSplash(
              ready: _initCompleter.isCompleted,
              onReady: _initCompleter.future,
              onComplete: () {
                if (mounted) setState(() => _showSplash = false);
                Future.delayed(const Duration(seconds: 1), _showBatteryDialog);
              },
            )
          : IndexedStack(
              index: currentIndex,
              children: pages,
            ),
      bottomNavigationBar:
          _showSplash ? null : PixelNavBar(
        currentIndex: currentIndex,
        onTap: goToTab,
        showSettings: true,
        showMap: true,
        labels: const ['对话', '地图', '创作', '设置'],
      ),
    );
  }

  void _showBatteryDialog() async {
    if (!mounted) return;
    try {
      final alreadyIgnored =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (alreadyIgnored) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保持后台运行'),
        content: const Text(
          '为保障定时任务准时执行，建议关闭省电策略对 My minimax 的限制。\n\n'
          '这不会增加额外耗电，只是在系统优化时跳过本应用。',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
            },
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
  }
}

