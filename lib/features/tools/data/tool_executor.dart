// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers.dart';
import '../../../core/api/minimax_client.dart';
import '../../../core/engine/conversation_session.dart';
import '../../../core/engine/tool_cancel_registry.dart';
import '../../../core/mcp/mcp_registry.dart';
import '../../../core/mcp/mcp_client.dart' show McpException;
import '../../../core/browser/browser_state.dart' show fileChangeNotifier;
import '../../../core/browser/adapters/browser_tool_adapter.dart';
import '../../../core/saf/saf_client.dart';
import '../../../core/tools/tool_registry.dart';
import '../../../core/api/weather_client.dart' show WeatherClient, WeatherException;
import '../../../core/api/amap_client.dart' show AmapClient, AmapException, GeoPoint, StaticMapMarker, StaticMapLabel, StaticMapPath, GrasproadPoint, TrafficInfo;
import '../../map/data/map_action.dart' show mapActionBus, mapActionPending, addToHistory, ShowPoisAction, ShowRouteAction, ShowLocationAction, ShowTrafficEventsAction, TrafficEventItem, ShowTrafficRoadsAction, TrafficRoadItem, ShowGrasproadAction, ShowFutureRouteAction, FutureRoutePathItem;
import '../../../core/api/worldtime_client.dart' show WorldTimeClient, WorldTimeException;
import '../../../core/phone/phone_client.dart';
import '../../../core/phone/location_client.dart';
import '../../../core/phone/sms_client.dart';
import '../../../core/phone/overlay_client.dart';
import '../../../core/phone/screen_capture_client.dart';
import '../../../core/api/kuaidi100_client.dart' show Kuaidi100Client;

import '../../../shared/document_converter/services/pdf_ocr_bridge.dart';
import '../../../core/browser/web_agent.dart';
import '../../../core/map/map_agent.dart';
import '../../../core/design/design.dart';
import '../../browser/data/browser_tool_handler.dart';
import '../../../core/hooks/hook_pipeline.dart';
import '../../../core/logging/tool_call_logger.dart';
import '../../../core/storage/database_helper.dart';
import '../../settings/data/settings_repository.dart';
import '../../memory/data/memory_cache.dart';
import '../../../shared/utils/file_utils.dart';
import '../../../shared/utils/temp_file_manager.dart';
import '../../../shared/document_converter/converters/pdf_converter.dart';
import '../../../shared/document_converter/converters/docx_converter.dart';
import '../../../shared/document_converter/converters/pptx_converter.dart';
import '../../../shared/document_generator/docx_writer.dart';
import '../../../shared/document_generator/xlsx_writer.dart';
import '../../../shared/document_generator/pptx_writer.dart';
import '../../../shared/document_generator/pdf_writer.dart';
import '../../../shared/document_generator/epub_writer.dart';
import '../../../shared/document_generator/office_editor.dart';
import '../../../shared/document_generator/pdf_editor.dart';
import '../domain/tool.dart';
import '../../../core/tools/trend_tools.dart';
import 'content/content_extractor.dart';
import '../domain/extracted_content.dart';
import '../../../core/page_index/page_index_engine.dart';
import '../../../core/page_index/index_repository.dart';
import '../../../core/page_index/models.dart';
import '../../../core/page_index/page_index_utils.dart';
import '../../../shared/document_converter/services/pdf_native_bridge.dart';

class _WorkspaceInfo {

  const _WorkspaceInfo({required this.path, this.useSaf = false, this.safUri});
  final String path;
  final bool useSaf;
  final String? safUri;

  bool get isConfigured => useSaf && safUri != null && safUri!.isNotEmpty;
}

class ToolExecutor {

  ToolExecutor({
    SettingsRepository? settingsRepo,
    SafClient? safClient,
    HookPipeline? hookPipeline,
    ToolCallLogger? toolLogger,
    DatabaseHelper? db,
    Ref? ref,
  })  : _settingsRepo = settingsRepo ?? SettingsRepository(),
        _safClient = safClient ?? SafClient(),
        _hookPipeline = hookPipeline ?? HookPipeline.instance,
        _toolLogger = toolLogger ?? (db != null ? ToolCallLogger(db) : null),
        _ref = ref;
  final SettingsRepository _settingsRepo;
  final SafClient _safClient;
  final HookPipeline _hookPipeline;
  final ToolCallLogger? _toolLogger;
  final Ref? _ref;
  MinimaxClient? _minimaxClient;
  BrowserToolHandler? _browserToolHandler;
  IBrowserBackend? _browserBackend;
  AmapClient? _amapClient;

  /// PageIndex 引擎 & 仓库（静态：跨工具调用复用，保持活跃文档状态）
  static PageIndexEngine? _pageIndexEngine;
  static PageIndexRepository? _pageIndexRepo;

  /// 当前活跃文档路径（静态：免去每轮传 path）
  static String? _activeDocumentPath;
  static String? _activeDocumentRelPath;

  /// 地图截图回调：MapPage 注册，ToolExecutor 等待结果。返回截图路径。
  static String? Function(String?)? onScreenshotComplete;

  /// 清除活跃文档（新对话或 close_document 时调用）
  static void clearActiveDocument() {
    _activeDocumentPath = null;
    _activeDocumentRelPath = null;
  }

  /// Per-round result cache (toolName + argsHash → result).
  /// Cleared at the start of each new user message.
  static final Map<String, ToolResult> _resultCache = {};

  /// Clear the shared result cache. Call before starting a new stream.
  static void clearResultCache() => _resultCache.clear();

  void setBrowserToolHandler(BrowserToolHandler? handler) {
    _browserToolHandler = handler;
  }

  void setBrowserBackend(IBrowserBackend? backend) {
    _browserBackend = backend;
  }

  static const _allowedUrlSchemas = ['http', 'https'];

  /// Release all static callbacks and resources. Call when recreating the executor
  /// (e.g., API key / settings change) to prevent stale callback leakage (X8).
  void dispose() {
    PdfConverter.visionCallback = null;
    PdfConverter.llmCleanup = null;
    DocxConverter.imageCallback = null;
    PptxConverter.imageCallback = null;
    _minimaxClient = null;
    TempFileManager().dispose();
  }

  /// 可用工具（从 ToolRegistry 获取，不再重复维护）
  static List<Tool> get availableTools => ToolRegistry.instance.toToolModels();

  Future<ToolResult> _executeMcpTool(String toolName, Map<String, dynamic> params) async {
    try {
      final result = await McpRegistry.instance.callTool(toolName, params);
      return ToolResult(
        toolName: toolName,
        success: true,
        output: result.text,
      );
    } on McpException catch (e) {
      return ToolResult(toolName: toolName, success: false, output: '', error: e.message);
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: toolName, success: false, output: '', error: 'MCP call failed: $e / MCP 调用失败: $e');
    }
  }

  Future<_WorkspaceInfo> _getWorkspace() async {
    if (!SafClient.isSupported) {
      return const _WorkspaceInfo(path: '');
    }

    final safUri = await _settingsRepo.getSafUri();
    if (safUri.isEmpty) {
      return const _WorkspaceInfo(path: '');
    }

    return _WorkspaceInfo(path: '', useSaf: true, safUri: safUri);
  }

  String _toRelativePath(String path) {
    String rel = path.trim();
    // Strip leading slashes and "./" prefixes
    while (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    while (rel.startsWith('./')) {
      rel = rel.substring(2);
    }
    // Normalize "." and ".." segments
    final segments = rel.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty && s != '.').toList();
    final resolved = <String>[];
    for (final seg in segments) {
      if (seg == '..') {
        if (resolved.isNotEmpty) resolved.removeLast();
      } else {
        resolved.add(seg);
      }
    }
    if (resolved.isEmpty) return '';
    return resolved.join('/');
  }

  /// 如果路径被标准化了，在消息中注明
  String _pathNote(String original, String normalized) {
    final trimmed = original.trim();
    if (trimmed != normalized) {
      return '$normalized (Original path / 原始路径: $trimmed)';
    }
    return normalized;
  }

  /// Deterministic JSON encoding for cache keys (key-order-independent).
  static String _sortedJson(Map<String, dynamic> map) {
    final sortedKeys = map.keys.toList()..sort();
    final buf = StringBuffer();
    buf.write('{');
    for (var i = 0; i < sortedKeys.length; i++) {
      if (i > 0) buf.write(',');
      buf.write('"${sortedKeys[i]}":');
      final v = map[sortedKeys[i]];
      if (v is String) {
        buf.write('"$v"');
      } else if (v == null) {
        buf.write('null');
      } else {
        buf.write('$v');
      }
    }
    buf.write('}');
    return buf.toString();
  }

  /// Tools that modify state and should invalidate the cache.
  static bool _isMutatingTool(String name) {
    switch (name) {
      case 'writeFile':
      case 'updateFile':
      case 'deleteFile':
      case 'moveFile':
      case 'mkdir':
      case 'appendFile':
      case 'generateDocx':
      case 'generateXlsx':
      case 'generatePptx':
      case 'generatePdf':
      case 'generateEpub':
      case 'task_set':
      case 'task_delete':
      case 'calendar_create':
      case 'calendar_delete':
      case 'contacts_create':
      case 'contacts_delete':
      case 'sms_send':
      case 'sms_delete':
      case 'phone_call':
      case 'overlay_show':
      case 'overlay_hide':
      case 'convertFile':
      case 'memory_change':
      case 'memory_delete':
        return true;
      default:
        return false;
    }
  }

  /// 只读工具 — 无需 SAF 授权即可使用（尝试 SAF，不行就走本地）
  static const _readFileTools = {'readFile', 'listFiles', 'glob', 'grep'};

  /// 写入/删除/生成工具 — 必须在 SAF 授权目录内操作
  static const _writeFileTools = {
    'writeFile', 'updateFile', 'deleteFile', 'appendFile', 'mkdir', 'moveFile',
    'convertFile', 'generateDocx', 'generateXlsx', 'generatePptx', 'generatePdf',
  };

  String _missingParamError(String toolName) {
    return 'Missing required parameter for $toolName. Check the tool input_schema for required fields.';
  }

  /// 截断过长的工具输出，防止撑爆上下文
  String _truncateOutput(String output, {int maxChars = 8000}) {
    if (output.length <= maxChars) return output;
    // 在行边界截断
    final cutoff = output.lastIndexOf('\n', maxChars);
    final splitAt = cutoff > maxChars ~/ 2 ? cutoff : maxChars;
    final truncated = output.substring(0, splitAt);
    final remaining = output.length - splitAt;
    return '$truncated\n\n（...输出已截断，剩余约 $remaining 字符。如需完整内容，请用更精确的查询或分页读取。）';
  }

  /// 拦截：只允许在 SAF 授权目录内进行写入/删除操作
  ToolResult? _guardWorkspace(String toolName, Map<String, dynamic> params, _WorkspaceInfo workspace) {
    if (!_writeFileTools.contains(toolName)) return null;

    if (!workspace.isConfigured) {
      return ToolResult(
        toolName: toolName, success: false, output: '',
        error: '拦截：未授权存储目录。写入/删除操作需要在设置中授权 SAF 目录。',
      );
    }

    final path = (params['path'] as String?) ??
        (params['source'] as String?) ??
        (params['filePath'] as String?) ??
        (params['dirPath'] as String?) ??
        '';
    if (path.isEmpty) return null; // 后面会报 missing param

    // 拒绝绝对路径
    if (RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path) || path.startsWith('/')) {
      return ToolResult(
        toolName: toolName, success: false, output: '',
        error: '拦截：拒绝绝对路径 "$path"。只能操作已授权 SAF 目录内的相对路径。',
      );
    }

    // 拒绝试图越权的 ../
    final normalized = _toRelativePath(path);
    final depth = '../'.allMatches(path).length;
    if (depth > 0 && normalized.isEmpty) {
      return ToolResult(
        toolName: toolName, success: false, output: '',
        error: '拦截：路径 "$path" 试图越权访问授权目录之外的位置。操作被拒绝。',
      );
    }

    return null;
  }

  /// 核心工具分发逻辑（不包含 hook、风险评估、日志）。
  Future<ToolResult> _executeCore(String toolName, Map<String, dynamic> params, {PauseToken? pauseToken}) async {
    final pause = pauseToken;
    try {
      final workspace = await _getWorkspace();

      // 拦截：只在 SAF 授权目录内允许写入/删除
      final guardResult = _guardWorkspace(toolName, params, workspace);
      if (guardResult != null) return guardResult;

      switch (toolName) {
        case 'readFile':
          final path = params['path'] as String?;
          if (path == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return workspace.isConfigured
              ? await _safReadFile(workspace.safUri!, path)
              : await _localReadFile(path);
        case 'convertFile':
          final cvPath = params['path'] as String?;
          if (cvPath == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _safConvertFile(workspace.safUri!, cvPath);
        case 'generateDocx':
          final content = params['content'] as String?;
          if (content == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          final path = (params['outputPath'] as String?) ?? 'output.docx';
          return await _safGenerateDocx(workspace.safUri!, path, content);
        case 'generateXlsx':
          final sheets = params['sheets'] as List?;
          if (sheets == null || sheets.isEmpty) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          final path = (params['outputPath'] as String?) ?? 'output.xlsx';
          final data = jsonEncode(sheets);
          return await _safGenerateXlsx(workspace.safUri!, path, data);
        case 'generatePptx':
          final slides = params['slides'] as List?;
          if (slides == null || slides.isEmpty) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          final path = (params['outputPath'] as String?) ?? 'output.pptx';
          final content = slides.map((s) => s.toString()).join('\n---\n');
          return await _safGeneratePptx(workspace.safUri!, path, content);
        case 'generatePdf':
          final content = params['content'] as String?;
          if (content == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          final path = (params['outputPath'] as String?) ?? 'output.pdf';
          return await _safGeneratePdf(workspace.safUri!, path, content);
        case 'generateEpub':
          final content = params['content'] as String?;
          if (content == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          final path = (params['outputPath'] as String?) ?? 'output.epub';
          return await _safGenerateEpub(workspace.safUri!, path, content, params['title'] as String?, params['author'] as String?);
          final ePdfP = params['path'] as String?;
          final ePdfO = params['old_str'] as String?;
          final ePdfN = params['new_str'] as String?;
          if (ePdfP == null || ePdfO == null || ePdfN == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _safEditPdf(workspace.safUri!, ePdfP, ePdfO, ePdfN);
        case 'writeFile':
          final path = params['path'] as String?;
          final content = params['content'] as String?;
          if (path == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          if (content == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _safWriteFile(workspace.safUri!, path, content);
        case 'updateFile':
          final path = params['path'] as String?;
          final oldStr = params['old_str'] as String?;
          final newStr = params['new_str'] as String?;
          if (path == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          if (oldStr == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          if (newStr == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _safUpdateFile(workspace.safUri!, path, oldStr, newStr);
        case 'deleteFile':
          final path = params['path'] as String?;
          if (path == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _safDeleteFile(workspace.safUri!, path);
        case 'listFiles':
          final path = params['path'] as String?;
          return workspace.isConfigured
              ? await _safListFiles(workspace.safUri!, path)
              : await _localListFiles(path);
        case 'fetchUrl':
          final url = params['url'] as String?;
          if (url == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _fetchUrl(url);
        case 'city_policy_lookup':
          return await _doCityPolicyLookup(toolName, params);
        case 'webSearch':
          final query = params['query'] as String?;
          if (query == null || query.trim().isEmpty) {
            return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          }
          final webSearchRedirect = _guardWebSearch(query);
          if (webSearchRedirect != null) return webSearchRedirect;
          return await _doWebSearch(query);
        case 'ask':
          final question = params['question'] as String?;
          final options = params['options'] as String?;
          if (question == null || question.trim().isEmpty) {
            return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          }
          final optionsList = (options ?? '是,否')
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          final multiSelect = params['multiSelect'] == true;
          return ToolResult(
            toolName: toolName,
            success: true,
            output: '已向用户提问：$question\n选项：${optionsList.join('、')}',
            interactive: InteractivePrompt(
              question: question,
              options: optionsList,
              multiSelect: multiSelect,
            ),
          );
        case 'grep':
          final grepPattern = params['pattern'] as String?;
          if (grepPattern == null || grepPattern.isEmpty) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          final grepPath = params['path'] as String?;
          final grepInclude = params['include'] as String?;
          return await _doGrep(grepPattern, grepPath, grepInclude, workspace);
        case 'glob':
          final globPattern = params['pattern'] as String?;
          if (globPattern == null || globPattern.isEmpty) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          final globPath = params['path'] as String?;
          return await _doGlob(globPattern, globPath, workspace);
        case 'moveFile':
          final source = params['source'] as String?;
          final destination = params['destination'] as String?;
          if (source == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          if (destination == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _safMoveFile(workspace.safUri!, source, destination);
        case 'mkdir':
          final dirPath = params['path'] as String?;
          if (dirPath == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _safMkdir(workspace.safUri!, dirPath);
        case 'appendFile':
          final appendPath = params['path'] as String?;
          final appendContent = params['content'] as String?;
          if (appendPath == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          if (appendContent == null) return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
          return await _safAppendFile(workspace.safUri!, appendPath, appendContent);
        case 'getWeather':
          return await _getWeather(params);
        case 'web_agent':
          return await _runWebAgent(params, pause);
        case 'generate_page':
          return await _generatePage(params);

        // ── 高德地图能力 ──
        case 'geocode':
          return await _amapGeocode(params);
        case 'regeocode':
          return await _amapRegeocode(params);
        case 'search_places':
          return await _amapSearchPlaces(params);
        case 'search_nearby':
          return await _amapSearchNearby(params);
        case 'plan_driving_route':
          return await _amapDrivingRoute(params);
        case 'plan_transit_route':
          return await _amapTransitRoute(params);
        case 'plan_walking_route':
          return await _amapWalkingRoute(params);
        case 'plan_cycling_route':
          return await _amapCyclingRoute(params);
        case 'plan_electrobike_route':
          return await _amapElectrobikeRoute(params);
        case 'get_bus_arrival':
          return await _amapBusArrival(params);
        case 'get_traffic_status':
          return await _amapTrafficStatus(params);
        case 'get_district_info':
          return await _amapDistrictInfo(params);
        case 'get_traffic_events':
          return await _amapTrafficEvents(params);
        case 'grasproad':
          return await _amapGrasproad(params);
        case 'future_route':
          return await _amapFutureRoute(params);
        case 'map_agent':
          return await _runMapAgent(params, pause);
        case 'static_map':
          return await _staticMap(params);
        case 'distance_calc':
          return await _distanceCalc(params);
        case 'map_screenshot':
          return await _mapScreenshotTool(params);
        case 'set_map_cache_limit':
          return await _setMapCacheLimit(params);
        case 'coordinate_converter':
          return await _coordinateConverter(params);
        case 'poi_detail':
          return await _amapPoiDetail(params);
        case 'bus_stop_by_id':
          return await _amapBusStopById(params);
        case 'search_bus_stop':
          return await _amapSearchBusStop(params);
        case 'bus_line_by_id':
          return await _amapBusLineById(params);
        case 'search_bus_line':
          return await _amapSearchBusLine(params);

        // ── 手机原生能力 ──
        case 'getCurrentTime':
          return await _getCurrentTime(params);
        case 'contacts_search':
          return await _contactsSearch(params);
        case 'contacts_list':
          return await _contactsSearch({'query': ''});
        case 'contacts_get':
          return await _contactsGet(params);
        case 'contacts_create':
          return await _contactsCreate(params);
        case 'contacts_delete':
          return await _contactsDelete(params);
        case 'calendar_query':
          return await _calendarQuery(params);
        case 'calendar_create':
          return await _calendarCreate(params);
        case 'calendar_delete':
          return await _calendarDelete(params);
        case 'phone_call':
          return await _phoneCall(params);
        case 'phone_call_log':
          return await _phoneCallLog(params);
        case 'location_get':
          return await _locationGet(params);
        case 'sms_read':
          return await _smsRead(params);
        case 'sms_send':
          return await _smsSend(params);
        case 'sms_delete':
          return await _smsDelete(params);
        case 'clipboard_write':
          return await _clipboardWrite(params);
        case 'overlay_show':
          return await _overlayShow(params);
        case 'overlay_hide':
          return await _overlayHide(params);
        case 'vibrate':
          return await _vibrate(params);
        case 'task_set':
          return await _taskSet(params);
        case 'task_list':
          return await _taskList(params);
        case 'task_delete':
          return await _taskDelete(params);
        case 'task_update':
          return await _taskUpdate(params);
        case 'task_history':
          return await _taskHistory(params);
        case 'notification_read':
          return await _notificationRead(params);
        case 'notification_post':
          return await _notificationPost(params);
        case 'express_track':
          return await _expressTrack(params);
        case 'express_subscribe':
          return await _expressSubscribe(params);
        case 'express_map':
          return await _expressMap(params);
        case 'express_check_subscriptions':
          return await _expressCheckSubscriptions(params);
        case 'screen_capture':
          return await _screenCapture(params);

        // ── 热点趋势工具 ──
        case 'getTrendingTopics':
        case 'searchTrendingTopics':
        case 'analyzeTopic':
        case 'getHistoricalTrends':
          return await TrendTools.execute(toolName, params);

        // ── 记忆管理工具 ──
        case 'memory_list':
          return await _memoryList(params);
        case 'memory_search':
          return await _memorySearch(params);
        case 'memory_delete':
          return await _memoryDelete(params);
        case 'memory_change':
          return await _memoryAdd(params);

        // ── PageIndex 文档索引与检索工具 ──
        case 'build_page_index':
          return await _buildPageIndex(params, workspace);
        case 'get_document_info':
          return await _getDocumentInfo(params);
        case 'get_document_structure':
          return await _getDocumentStructure(params);
        case 'get_page_content':
          return await _getPageContent(params, workspace);
        case 'list_indexed_documents':
          return await _listIndexedDocuments();
        case 'delete_page_index':
          return await _deletePageIndex(params);
        case 'search_documents':
          return await _searchDocuments(params);
        case 'read_section':
          return await _readSection(params, workspace);
        case 'close_document':
          return await _closeDocument();

        default:
          // 路由到浏览器工具
          if (toolName.startsWith('browser_')) {
            final be = _browserBackend ?? _browserToolHandler;
            if (be != null) {
              return await be.execute(toolName, params);
            }
            return ToolResult(
              toolName: toolName,
              success: false,
              output: '',
              error: 'Browser not initialized. Open the browser tab first.',
            );
          }
          // 路由到 MCP 服务器
          if (toolName.startsWith('mcp__') || McpRegistry.instance.mcpToolNames.contains(toolName)) {
            return await _executeMcpTool(toolName, params);
          }
          return ToolResult(toolName: toolName, success: false, output: '', error: 'Unknown tool: $toolName');
      }
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: toolName, success: false, output: '', error: e.toString());
    }
  }

  /// 带缓存 + 日志的工具执行（Hook 已提升到 Agent 循环层）。
  Future<ToolResult> execute(
    String toolName,
    Map<String, dynamic> params, {
    String? conversationId,
    String? messageId,
    PauseToken? pauseToken,
  }) async {
    // 日志开始
    String? callId;
    if (_toolLogger != null && conversationId != null) {
      callId = await _toolLogger.logCallStart(
        conversationId: conversationId,
        toolName: toolName,
        inputSummary: params.toString(),
        messageId: messageId,
        riskScore: 0,
      );
    }

    // 执行（优先命中缓存）
    final cacheKey = '$toolName:${_sortedJson(params)}';
    ToolResult result;
    if (_resultCache.containsKey(cacheKey)) {
      result = _resultCache[cacheKey]!;
    } else {
      result = await _executeCore(toolName, params, pauseToken: pauseToken);
      if (result.success && !_isMutatingTool(toolName)) {
        _resultCache[cacheKey] = result;
      }
      if (_isMutatingTool(toolName)) {
        _resultCache.clear();
      }
    }

    // 5. 日志结束
    if (_toolLogger != null && callId != null) {
      await _toolLogger.logCallEnd(callId,
        success: result.success,
        outputSummary: result.success ? result.output : (result.error ?? ''),
      );
    }

    return result;
  }

  /// 带完整 hooks + 风险评估 + 日志 + 累积追踪的工具执行。
  ///
  /// 已废弃 — Hook 执行已提升到 Agent 循环层（chat_repository.dart）。
  /// 保留此方法仅为向后兼容，内部委托给 [execute]。
  @Deprecated('Hook execution moved to Agent loop. Use execute() instead.')
  Future<ToolResult> executeWithHooks(
    String toolName,
    Map<String, dynamic> params, {
    String? conversationId,
    String? messageId,
    PauseToken? pauseToken,
  }) async {
    return execute(toolName, params,
        conversationId: conversationId,
        messageId: messageId,
        pauseToken: pauseToken);
  }

  Future<ToolResult> executeWithTimeout(
    String toolName,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
    CancelToken? cancelToken,
  }) async {
    return await Future.any([
      execute(toolName, params),
      Future.delayed(timeout, () => ToolResult(
        toolName: toolName,
        success: false,
        output: '',
        error: '工具执行超时（${timeout.inSeconds}秒）',
      )),
      if (cancelToken != null) cancelToken.cancelledResult(toolName, () => ToolResult(
        toolName: toolName,
        success: false,
        output: '',
        error: '工具执行已取消',
      )),
    ]);
  }

  // ─── 本地文件读取（SAF 未授权时的 fallback） ──────────

  Future<ToolResult> _localReadFile(String path) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$path');
      if (!await file.exists()) {
        return ToolResult(
          toolName: 'readFile',
          success: false,
          output: '',
          error: '文件不存在: $path（工作目录未授权，读取范围限于应用内部存储）',
        );
      }
      final content = await file.readAsString();
      return ToolResult(toolName: 'readFile', success: true, output: _truncateOutput(content));
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'readFile',
        success: false,
        output: '',
        error: '读取失败: $e',
      );
    }
  }

  Future<ToolResult> _localListFiles(String? dirPath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(dirPath != null ? '${dir.path}/$dirPath' : dir.path);
      if (!await targetDir.exists()) {
        return ToolResult(
          toolName: 'listFiles',
          success: false,
          output: '',
          error: '目录不存在: ${dirPath ?? "/"}（工作目录未授权，读取范围限于应用内部存储）',
        );
      }
      final entries = await targetDir.list().toList();
      final buf = StringBuffer();
      for (final e in entries) {
        final name = e.path.split('/').last;
        buf.writeln(e is Directory ? '[DIR]  $name/' : '[FILE] $name');
      }
      return ToolResult(toolName: 'listFiles', success: true,
          output: buf.isEmpty ? '目录为空' : _truncateOutput(buf.toString()));
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'listFiles',
        success: false,
        output: '',
        error: '列出目录失败: $e',
      );
    }
  }

  Future<ToolResult> _doGlob(String pattern, String? searchPath, _WorkspaceInfo workspace) async {
    final glob = Glob(pattern);
    if (workspace.isConfigured) {
      // SAF mode: use listFiles + Glob.matches for filtering
      final safResult = await _safListFiles(workspace.safUri!, searchPath);
      if (!safResult.success) return safResult;
      final lines = safResult.output.split('\n').where((l) {
        final name = l.replaceFirst('[FILE] ', '').replaceFirst('[DIR]  ', '').trim();
        return glob.matches(name);
      }).toList();
      return ToolResult(toolName: 'glob', success: true,
          output: lines.isEmpty ? '无匹配文件' : _truncateOutput(lines.join('\n')));
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final root = searchPath != null ? '${dir.path}/$searchPath' : dir.path;
      if (!Directory(root).existsSync()) {
        return ToolResult(toolName: 'glob', success: false, output: '', error: '目录不存在: ${searchPath ?? "/"}');
      }
      final matched = glob.listSync(root: root)
          .whereType<File>()
          .map((f) => f.path)
          .toList();
      matched.sort();
      return ToolResult(toolName: 'glob', success: true,
          output: matched.isEmpty ? '无匹配文件' : _truncateOutput(matched.join('\n')));
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'glob', success: false, output: '', error: 'glob 失败: $e');
    }
  }

  Future<ToolResult> _doGrep(String pattern, String? searchPath, String? include, _WorkspaceInfo workspace) async {
    final re = RegExp(pattern, caseSensitive: false);
    final fileGlob = include != null ? Glob(include) : null;
    final buf = StringBuffer();
    int totalMatches = 0;

    void addMatch(String path, int lineNum, String text) {
      buf.writeln('$path:$lineNum: $text');
      totalMatches++;
    }

    if (workspace.isConfigured) {
      // SAF mode: list files, filter by glob, read & search each
      final safResult = await _safListFiles(workspace.safUri!, searchPath);
      if (!safResult.success) return safResult;
      for (final line in safResult.output.split('\n')) {
        if (!line.startsWith('[FILE] ')) continue;
        final fileName = line.substring(7).trim();
        if (fileGlob != null && !fileGlob.matches(fileName)) continue;
        final prefix = searchPath != null ? '$searchPath/' : '';
        final relPath = '$prefix$fileName';
        try {
          final content = await _safClient.readFile(workspace.safUri!, relPath);
          final fileLines = content.split('\n');
          for (var i = 0; i < fileLines.length && totalMatches < 200; i++) {
            if (re.hasMatch(fileLines[i])) addMatch(relPath, i + 1, fileLines[i].trim());
          }
        } catch (_) {}
        if (totalMatches >= 200) {
          buf.writeln('...(truncated, 200 matches limit)');
          return ToolResult(toolName: 'grep', success: true, output: buf.toString());
        }
      }
      return ToolResult(toolName: 'grep', success: true,
          output: buf.isEmpty ? '无匹配结果' : buf.toString());
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final root = searchPath != null ? '${dir.path}/$searchPath' : dir.path;
      if (!Directory(root).existsSync()) {
        return ToolResult(toolName: 'grep', success: false, output: '', error: '目录不存在: ${searchPath ?? "/"}');
      }
      final entries = fileGlob != null
          ? fileGlob.listSync(root: root).whereType<File>()
          : Directory(root).listSync(recursive: true).whereType<File>();
      for (final file in entries) {
        if (totalMatches >= 200) {
          buf.writeln('...(truncated, 200 matches limit)');
          return ToolResult(toolName: 'grep', success: true, output: buf.toString());
        }
        try {
          final lines = await file.readAsLines();
          for (var i = 0; i < lines.length && totalMatches < 200; i++) {
            if (re.hasMatch(lines[i])) addMatch(file.path, i + 1, lines[i].trim());
          }
        } catch (_) {}
      }
      return ToolResult(toolName: 'grep', success: true,
          output: buf.isEmpty ? '无匹配结果' : buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'grep', success: false, output: '', error: 'grep 失败: $e');
    }
  }

  // ─── SAF 文件操作实现 ────────────────────────────────────

  Future<ToolResult> _safReadFile(String safUri, String path) async {
    final relPath = _toRelativePath(path);
    final mimeType = lookupMimeType(relPath);

    // Auto-convert document files to Markdown
    if (FileUtils.isDocumentFile(mimeType: mimeType, fileName: relPath)) {
      try {
        if (_needsMinimaxForFormat(mimeType)) {
          await _ensureMinimaxClient();
        }
        final bytes = await _safClient.readFileBytes(safUri, relPath);
        if (bytes != null) {
          final result = await FileUtils.convertToMarkdown(
            bytes: bytes,
            mimeType: mimeType,
            fileName: relPath,
          );
          final label = result.detectedFormat ?? 'document';
          final titleLine = result.title != null ? 'Title: ${result.title}\n\n' : '';
          final searchableText = _extractSearchableText(result.markdownContent, label);
          final editHint = _editHint(label);
          return ToolResult(
            toolName: 'readFile',
            success: true,
            output: _truncateOutput(
              '[$label → Markdown]$editHint\n'
              '$searchableText\n'
              '--- 读取内容 ---\n'
              '$titleLine${result.markdownContent}',
            ),
          );
        }
      } catch (e) {
        print('[ToolExecutor] error: \$e');
        // Fallback to plain text read
      }
    }

    final content = await _safClient.readFile(safUri, relPath);
    return ToolResult(toolName: 'readFile', success: true, output: _truncateOutput(content));
  }

  Future<ToolResult> _safConvertFile(String safUri, String path) async {
    final relPath = _toRelativePath(path);
    final mimeType = lookupMimeType(relPath);

    if (_needsMinimaxForFormat(mimeType)) {
      await _ensureMinimaxClient();
    }

    final bytes = await _safClient.readFileBytes(safUri, relPath);
    if (bytes == null) {
      return ToolResult(
        toolName: 'convertFile',
        success: false,
        output: '',
        error: '无法读取文件: ${_pathNote(path, relPath)}',
      );
    }

    try {
      final result = await FileUtils.convertToMarkdown(
        bytes: bytes,
        mimeType: mimeType,
        fileName: relPath,
      );
      final label = result.detectedFormat ?? mimeType ?? 'document';
      final titleLine = result.title != null ? 'Title: ${result.title}\n\n' : '';
      final editHint = _editHint(label);
      return ToolResult(
        toolName: 'convertFile',
        success: true,
        output: '[$label → Markdown]\n\n$editHint$titleLine${result.markdownContent}',
      );
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'convertFile',
        success: false,
        output: '',
        error: '文档转换失败: $e',
      );
    }
  }

  /// Tell the agent how to edit this format.
  String _editHint(String format) {
    switch (format) {
      case 'docx':
        return '\n> 直接覆盖原文件重新生成: generateDocx(content=下方「修改后」的markdown, outputPath=当前文件路径)\n'
            '> outputPath 必须传当前文件的完整路径，直接覆盖旧文档';
      case 'xlsx':
        return '\n> 直接覆盖原文件重新生成: generateXlsx(sheets=下方「修改后」的数据, outputPath=当前文件路径)\n'
            '> outputPath 必须传当前文件的完整路径，直接覆盖旧文档';
      case 'pptx':
        return '\n> 直接覆盖原文件重新生成: generatePptx(slides=下方「修改后」的幻灯片, outputPath=当前文件路径)\n'
            '> outputPath 必须传当前文件的完整路径，直接覆盖旧文档';
      case 'pdf':
        return '\n> 直接覆盖原文件重新生成: generatePdf(content=下方「修改后」的markdown, outputPath=当前文件路径)\n'
            '> outputPath 必须传当前文件的完整路径，直接覆盖旧文档';
      default:
        return '';
    }
  }

  /// Extract searchable text from the already-converted result for edit matching.
  /// Uses the cached markdown content instead of re-processing bytes.
  String _extractSearchableText(String markdownContent, String? format) {
    if (format == null || !['docx', 'xlsx', 'pptx'].contains(format)) return '';
    if (markdownContent.isEmpty) return '';
    return '--- Original text (for old_str exact match) / 原文（供 old_str 精确匹配用） ---\n$markdownContent\n';
  }

  // ─── 文档生成 ────────────────────────────────────────

  Future<ToolResult> _safGenerateDocx(String safUri, String path, String markdown) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = DocxWriter(markdown).build();
      await _safClient.writeFileBytes(safUri, relPath, bytes);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'generateDocx', success: true, output: 'Word document generated: ${_pathNote(path, relPath)} / Word 文档已生成: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'generateDocx', success: false, output: '', error: 'Generation failed: $e / 生成失败: $e');
    }
  }

  Future<ToolResult> _safGenerateXlsx(String safUri, String path, String data) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = XlsxWriter(data).build();
      await _safClient.writeFileBytes(safUri, relPath, bytes);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'generateXlsx', success: true, output: 'Excel spreadsheet generated: ${_pathNote(path, relPath)} / Excel 表格已生成: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'generateXlsx', success: false, output: '', error: 'Generation failed: $e / 生成失败: $e');
    }
  }

  Future<ToolResult> _safGeneratePptx(String safUri, String path, String markdown) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = PptxWriter(markdown).build();
      await _safClient.writeFileBytes(safUri, relPath, bytes);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'generatePptx', success: true, output: 'PPT generated: ${_pathNote(path, relPath)} / PPT 已生成: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'generatePptx', success: false, output: '', error: 'Generation failed: $e / 生成失败: $e');
    }
  }

  Future<ToolResult> _safGeneratePdf(String safUri, String path, String markdown) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = await PdfWriter(markdown).build();
      await _safClient.writeFileBytes(safUri, relPath, bytes);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'generatePdf', success: true, output: 'PDF generated: ${_pathNote(path, relPath)} / PDF 已生成: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'generatePdf', success: false, output: '', error: 'Generation failed: $e / 生成失败: $e');
    }
  }

  Future<ToolResult> _safGenerateEpub(String safUri, String path, String markdown, String? title, String? author) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = EpubWriter(
        markdown: markdown,
        title: title,
        author: author,
      ).build();
      await _safClient.writeFileBytes(safUri, relPath, bytes);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'generateEpub', success: true, output: 'EPUB generated: ${_pathNote(path, relPath)} / EPUB 已生成: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'generateEpub', success: false, output: '', error: 'Generation failed: $e / 生成失败: $e');
    }
  }

  // ─── Office 原地编辑 ─────────────────────────────────────

  Future<ToolResult> _safEditDocx(String safUri, String path, String oldStr, String newStr, [bool replaceAll = true]) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = await _safClient.readFileBytes(safUri, relPath);
      if (bytes == null) return const ToolResult(toolName: 'editDocx', success: false, output: '', error: 'Unable to read file / 无法读取文件');
      final modified = OfficeEditor.editDocx(bytes, oldStr, newStr, replaceAll: replaceAll);
      await _safClient.writeFileBytes(safUri, relPath, modified);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'editDocx', success: true, output: 'Word document updated: ${_pathNote(path, relPath)} / Word 文档已更新: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'editDocx', success: false, output: '', error: 'Edit failed: $e / 编辑失败: $e');
    }
  }

  Future<ToolResult> _safEditXlsx(String safUri, String path, String oldStr, String newStr, [bool replaceAll = true]) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = await _safClient.readFileBytes(safUri, relPath);
      if (bytes == null) return const ToolResult(toolName: 'editXlsx', success: false, output: '', error: 'Unable to read file / 无法读取文件');
      final modified = OfficeEditor.editXlsx(bytes, oldStr, newStr, replaceAll: replaceAll);
      await _safClient.writeFileBytes(safUri, relPath, modified);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'editXlsx', success: true, output: 'Excel spreadsheet updated: ${_pathNote(path, relPath)} / Excel 表格已更新: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'editXlsx', success: false, output: '', error: 'Edit failed: $e / 编辑失败: $e');
    }
  }

  Future<ToolResult> _safEditPptx(String safUri, String path, String oldStr, String newStr, [bool replaceAll = true]) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = await _safClient.readFileBytes(safUri, relPath);
      if (bytes == null) return const ToolResult(toolName: 'editPptx', success: false, output: '', error: 'Unable to read file / 无法读取文件');
      final modified = OfficeEditor.editPptx(bytes, oldStr, newStr, replaceAll: replaceAll);
      await _safClient.writeFileBytes(safUri, relPath, modified);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'editPptx', success: true, output: 'PPT updated: ${_pathNote(path, relPath)} / PPT 已更新: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'editPptx', success: false, output: '', error: 'Edit failed: $e / 编辑失败: $e');
    }
  }

  Future<ToolResult> _safEditPdf(String safUri, String path, String oldStr, String newStr) async {
    final relPath = _toRelativePath(path);
    try {
      final bytes = await _safClient.readFileBytes(safUri, relPath);
      if (bytes == null) return const ToolResult(toolName: 'editPdf', success: false, output: '', error: 'Unable to read file / 无法读取文件');
      final modified = PdfEditor.edit(bytes, oldStr, newStr);
      await _safClient.writeFileBytes(safUri, relPath, modified);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'editPdf', success: true, output: 'PDF updated: ${_pathNote(path, relPath)} / PDF 已更新: ${_pathNote(path, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      // In-place edit failed — OCR the PDF so the LLM has the text to edit directly
      String? ocrText;
      try {
        final bytes = await _safClient.readFileBytes(safUri, relPath);
        if (bytes != null) {
          final result = await FileUtils.convertToMarkdown(
            bytes: bytes,
            mimeType: 'application/pdf',
            fileName: path,
            options: {'skipLlmCleanup': true},
          );
          ocrText = result.markdownContent;
        }
      } catch (_) {}

      final hint = ocrText != null && ocrText.trim().isNotEmpty
          ? '\n\n当前 PDF 内容（已自动提取）：\n```\n$ocrText\n```\n\n直接在 Markdown 中修改目标文本，然后用 generatePdf 重新生成 PDF。'
          : '\n\n建议：用 readFile 读取 PDF 内容 → 修改 Markdown → generatePdf 生成新文件。';

      return ToolResult(
        toolName: 'editPdf',
        success: false,
        output: '',
        error: 'PDF 原地编辑失败：$e$hint',
      );
    }
  }

  Future<ToolResult> _safWriteFile(String safUri, String path, String content) async {
    final relPath = _toRelativePath(path);
    String? existingContent;
    bool fileExists = false;
    try {
      existingContent = await _safClient.readFile(safUri, relPath);
      fileExists = true; // read succeeded → file exists (even if empty)
    } catch (_) {}
    await _safClient.writeFile(safUri, relPath, content);
    fileChangeNotifier.value++;
    return ToolResult(toolName: 'writeFile', success: true, output: 'File saved: ${_pathNote(path, relPath)} / 文件已保存: ${_pathNote(path, relPath)}');
  }

  Future<ToolResult> _safUpdateFile(String safUri, String path, String oldStr, String newStr) async {
    final relPath = _toRelativePath(path);
    final content = await _safClient.readFile(safUri, relPath);
    if (!content.contains(oldStr)) {
      return const ToolResult(toolName: 'updateFile', success: false, output: '', error: 'Specified text not found, replace failed / 未找到指定文本，替换失败');
    }
    final updated = content.replaceFirst(oldStr, newStr);
    await _safClient.writeFile(safUri, relPath, updated);
    fileChangeNotifier.value++;
    return const ToolResult(toolName: 'updateFile', success: true, output: 'Replaced / 已替换');
  }

  Future<ToolResult> _safDeleteFile(String safUri, String path) async {
    final relPath = _toRelativePath(path);
    String? content;
    try { content = await _safClient.readFile(safUri, relPath); } catch (_) {}
    await _safClient.deleteFile(safUri, relPath);
    fileChangeNotifier.value++;
    return ToolResult(toolName: 'deleteFile', success: true, output: 'Deleted: ${_pathNote(path, relPath)} / 已删除: ${_pathNote(path, relPath)}');
  }

  Future<ToolResult> _safListFiles(String safUri, String? path) async {
    final relPath = (path == null || path.isEmpty) ? null : _toRelativePath(path);
    final files = await _safClient.listFiles(safUri, relPath);
    // 构造完整相对路径，让模型能直接用于后续文件操作
    final prefix = (relPath != null && relPath.isNotEmpty) ? '$relPath/' : '';
    final output = files.map((f) {
      final type = f.isDirectory ? '[DIR]' : '[FILE]';
      final size = f.isDirectory ? '' : ' (${f.size}B)';
      final fullPath = '$prefix${f.name}';
      return '$type $fullPath$size';
    }).join('\n');
    return ToolResult(toolName: 'listFiles', success: true, output: output.isEmpty ? '(empty directory) / （空目录）' : output);
  }

  /// Tier 3: render URL in browser, wait for SPA hydration, return rendered HTML.
  Future<String?> _fetchHtmlViaBrowser(String url) async {
    final backend = _browserBackend ?? _browserToolHandler;
    if (backend == null) return null;
    if (_browserToolHandler == null ||
        _browserToolHandler!.controllers.isEmpty) {
      return null;
    }
    try {
      final navResult = await backend.execute('browser_navigate', {'url': url});
      if (!navResult.success) return null;

      final controller = _browserToolHandler!.controllers.values.first;
      final result = await controller
          .evaluateJavascript(source: 'document.documentElement.outerHTML');
      return result?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Returns true when the extracted content looks like an SPA shell —
  /// content is near-empty and the HTML itself was clearly JS-dependent.
  bool _isSpaResult(ExtractedLinkContent r) {
    return r.totalCharacters < 200 ||
        (r.content.length < 200 && r.description == null);
  }

  Future<ToolResult> _fetchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_allowedUrlSchemas.contains(uri.scheme)) {
      return const ToolResult(
        toolName: 'fetchUrl',
        success: false,
        output: '',
        error:
            'Security restriction: only http/https protocols supported / 安全限制：仅支持 http/https 协议',
      );
    }

    return _extractWithTiers(
      url: url,
      toolName: 'fetchUrl',
      maxChars: 12000,
      formatOutput: (extracted, usedBrowser) {
        final buffer = StringBuffer();
        if (extracted.title != null) {
          buffer.writeln('# ${extracted.title}');
        }
        if (extracted.siteName != null) {
          buffer.writeln('*Source: ${extracted.siteName}*');
        }
        if (extracted.author != null) {
          buffer.writeln('*Author: ${extracted.author}*');
        }
        if (extracted.publishedDate != null) {
          buffer.writeln('*Published: ${extracted.publishedDate}*');
        }
        if (extracted.description != null) {
          buffer.writeln('> ${extracted.description}');
        }
        buffer.writeln('*Reading time: ~${extracted.readingTimeMinutes} min*');
        if (extracted.truncated) {
          buffer.writeln(
              '*[Content truncated at ${extracted.totalCharacters} chars]*');
        }
        if (usedBrowser) {
          buffer.writeln('*[Rendered via browser for JS-heavy page]*');
        }
        buffer.writeln();
        buffer.writeln('## Extracted Content');
        buffer.writeln();
        buffer.write(extracted.content);
        return buffer.toString();
      },
    );
  }

  /// Tiered extraction: HTTP first → browser fallback for SPA/empty pages.
  Future<ToolResult> _extractWithTiers({
    required String url,
    required String toolName,
    required int maxChars,
    required String Function(ExtractedLinkContent extracted, bool usedBrowser)
        formatOutput,
  }) async {
    const extractor = ContentExtractor();
    final sizedExtractor = ContentExtractor(maxCharacters: maxChars);
    ExtractedLinkContent? extracted;
    bool usedBrowser = false;

    // Tier 1: Static HTTP fetch (with charset detection)
    try {
      final (html, source) = await extractor.fetchHtmlForTiered(url);
      extracted = await sizedExtractor.extractFromHtml(html, url);
    } catch (_) {
      // HTTP fetch totally failed — will try browser below
    }

    // Tier 2 & 3: If result looks like SPA shell, try browser render
    if (extracted == null || _isSpaResult(extracted)) {
      try {
        final browserHtml = await _fetchHtmlViaBrowser(url);
        if (browserHtml != null && browserHtml.isNotEmpty) {
          final browserResult =
              await sizedExtractor.extractFromHtml(browserHtml, url);
          // Only replace if browser gave more content
          if (browserResult.totalCharacters >
              (extracted?.totalCharacters ?? 0)) {
            extracted = browserResult;
            usedBrowser = true;
          }
        }
      } catch (_) {
        // Browser unavailable or failed — use static fallback if any
      }
    }

    // If everything failed
    if (extracted == null) {
      return ToolResult(
        toolName: toolName,
        success: false,
        output: '',
        error:
            'All extraction methods failed for $url / 所有抓取方式均失败: $url',
      );
    }

    return ToolResult(
      toolName: toolName,
      success: true,
      output: formatOutput(extracted, usedBrowser),
    );
  }

  /// 硬拦截：webSearch 被误用于实时热搜或 URL 抓取场景时，返回重定向提示
  ToolResult? _guardWebSearch(String query) {
    // 实时热搜 → 应该用 getTrendingTopics / searchTrendingTopics
    // 历史热搜（上周/昨天/去年）不过，走 webSearch
    final q = query.trim();
    final isHistorical = RegExp(r'上周|昨天|去年|上个月|历史|回顾|往期|以前|之前|过去|往期').hasMatch(q);
    final isDefinition = RegExp(r'是什么|什么意思|如何|怎么|定义|概念|介绍|科普|解释').hasMatch(q);
    if (!isHistorical && !isDefinition && RegExp(r'热搜|热点|热榜|今日最火|都在聊|流行什么').hasMatch(q)) {
      return const ToolResult(
        toolName: 'webSearch',
        success: false,
        output: '',
        error: '❌ 工具选错。实时热搜/热点请用 getTrendingTopics 或 searchTrendingTopics。'
            '如果是历史热搜，请明确说明"热搜工具仅支持实时数据"后，用 webSearch 重新查询。',
      );
    }
    // 裸 URL → 应该用 fetchUrl
    if (RegExp(r'^https?://|^www\.').hasMatch(q)) {
      return const ToolResult(
        toolName: 'webSearch',
        success: false,
        output: '',
        error: '❌ 工具选错。读取网页内容请用 fetchUrl，不要用 webSearch 搜 URL。',
      );
    }
    return null;
  }

  Future<ToolResult> _doWebSearch(String query) async {
    try {
      await _ensureMinimaxClient();
      final result = await _minimaxClient!.search(query);

      if (result.results.isEmpty) {
        return const ToolResult(toolName: 'webSearch', success: true, output: 'No relevant results found / 未找到相关结果');
      }

      final buffer = StringBuffer();
      for (var i = 0; i < result.results.length; i++) {
        final item = result.results[i];
        buffer.writeln('${i + 1}. ${item.title}');
        buffer.writeln('   ${item.link}');
        if (item.snippet.isNotEmpty) {
          buffer.writeln('   ${item.snippet}');
        }
        buffer.writeln();
      }

      return ToolResult(toolName: 'webSearch', success: true, output: _truncateOutput(buffer.toString()));
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'webSearch', success: false, output: '', error: 'Search failed: $e / 搜索失败: $e');
    }
  }

  /// 安全从 Map 取值，避免 String→Map 类型转换崩溃
  static Map<String, dynamic> _safeMap(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  /// 安全从 Map 取列表，自动过滤非 Map 元素
  static List<Map<String, dynamic>> _safeList(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v == null) return [];
    if (v is List) return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return [];
  }

  /// 安全提取 List<dynamic>（用于 guidance 等简单值列表）
  static List _safeListRaw(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is List) return v;
    return [];
  }

  static const _policyTypeLabels = {
    'social_insurance': '社保 缴费基数 报销比例',
    'housing_fund': '公积金 缴存 提取 贷款',
    'hukou': '落户 户籍 迁入条件',
    'residence_permit': '居住证 办理 条件',
    'traffic_restriction': '限行 尾号 限行区域',
    'education': '学区 入学政策 积分入学',
    'medical_insurance': '医保 报销 异地就医',
    'housing_purchase': '购房资格 限购政策',
    'general': '',
  };

  static const _policySiteFilters = [
    'site:gov.cn',
    'site:12333.cn',
    'site:gjj.gov.cn',
  ];

  Future<ToolResult> _doCityPolicyLookup(String toolName, Map<String, dynamic> params) async {
    final city = params['city'] as String?;
    final policyType = params['policyType'] as String?;
    final keyword = params['keyword'] as String?;
    final year = params['year'] as String?;

    if (city == null || city.trim().isEmpty) {
      return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
    }
    if (policyType == null || policyType.trim().isEmpty) {
      return ToolResult(toolName: toolName, success: false, output: '', error: _missingParamError(toolName));
    }

    final label = _policyTypeLabels[policyType] ?? '';
    final yearStr = year ?? DateTime.now().year.toString();
    final kw = keyword != null && keyword.isNotEmpty ? ' $keyword' : '';

    // 构建精准搜索查询：城市 + 政策类型 + 年份 + 关键词
    final query = '$city $label$kw $yearStr';

    // 加上 gov.cn 限域，优先政府官网
    final govQuery = '$query (${_policySiteFilters.join(" OR ")})';

    try {
      await _ensureMinimaxClient();
      final result = await _minimaxClient!.search(govQuery);

      if (result.results.isEmpty) {
        // 放宽限制再试一次，不加 site 过滤
        final fallback = await _minimaxClient!.search(query);
        if (fallback.results.isEmpty) {
          return ToolResult(toolName: toolName, success: true,
            output: '未找到"$city"关于"${label.isNotEmpty ? label : policyType}"的政策信息。'
                '建议：① 检查城市名是否为全称（如"杭州市"）；② 尝试换一个 policyType；'
                '③ 用 general 类型 + 具体关键词重试。');
        }
        // 用放宽后的结果
        final buf = StringBuffer();
        buf.writeln('【$city - ${label.isNotEmpty ? label : policyType} 政策查询】（放宽搜索）');
        buf.writeln();
        for (var i = 0; i < fallback.results.length; i++) {
          buf.writeln('${i + 1}. ${fallback.results[i].title}');
          buf.writeln('   ${fallback.results[i].link}');
          if (fallback.results[i].snippet.isNotEmpty) {
            buf.writeln('   ${fallback.results[i].snippet}');
          }
          buf.writeln();
        }
        return ToolResult(toolName: toolName, success: true, output: _truncateOutput(buf.toString()));
      }

      final buf = StringBuffer();
      buf.writeln('【$city - ${label.isNotEmpty ? label : policyType} 政策查询】');
      if (keyword != null && keyword.isNotEmpty) buf.writeln('关键词: $keyword');
      buf.writeln();
      for (var i = 0; i < result.results.length; i++) {
        buf.writeln('${i + 1}. ${result.results[i].title}');
        buf.writeln('   ${result.results[i].link}');
        if (result.results[i].snippet.isNotEmpty) {
          buf.writeln('   ${result.results[i].snippet}');
        }
        buf.writeln();
      }

      return ToolResult(toolName: toolName, success: true, output: _truncateOutput(buf.toString()));
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: toolName, success: false, output: '',
        error: '城市政策查询失败: $e / City policy lookup failed: $e');
    }
  }

  Future<void> _ensureMinimaxClient() async {
    if (_minimaxClient != null) return;

    final settings = SettingsRepository();
    var apiKey = await settings.getActiveApiKey();
    final model = await settings.getModel();
    final activeType = await settings.getActiveApiKeyType();

    if (apiKey.isEmpty) {
      final standardKey = await settings.getApiKeyStandard();
      final tokenKey = await settings.getApiKey();
      if (activeType == 'standard' && standardKey.isNotEmpty) {
        apiKey = standardKey;
      } else if (tokenKey.isNotEmpty) {
        apiKey = tokenKey;
      }
    }

    if (apiKey.isEmpty) return;
    _minimaxClient = MinimaxClient(apiKey: apiKey, model: model);
    _wireVisionCallback();
  }

  /// Whether this format needs the Minimax client for vision/LLM features.
  /// PDF (OCR/structuring), DOCX (image description), PPTX (image description).
  bool _needsMinimaxForFormat(String? mimeType) {
    if (mimeType == null) return false;
    return mimeType == 'application/pdf' ||
        mimeType == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
        mimeType == 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
  }

  void _wireVisionCallback() {
    // Capture the current client reference so that if dispose() is called and a
    // new ToolExecutor is created, stale callbacks will detect the mismatch and
    // return early instead of using a disposed/outdated client (X8).
    final client = _minimaxClient;

    // Vision API now used ONLY for image description (charts, diagrams, photos)
    // Text OCR is handled by PaddleOCR+ncnn (PdfOcrBridge) — offline, unlimited pages
    PdfConverter.visionCallback = (Uint8List imageBytes) async {
      if (_minimaxClient == null || _minimaxClient != client) return '';
      final base64Str = base64.encode(imageBytes);
      return _minimaxClient!.vision(base64Str, PdfConverter.visionPrompt);
    };

    // LLM structuring — raw page text → clean Markdown (called once per document)
    PdfConverter.llmCleanup = (String rawText) async {
      if (_minimaxClient == null || _minimaxClient != client) return rawText;
      return _structureWithLLM(rawText);
    };

    // DOCX image description
    DocxConverter.imageCallback = (Uint8List imageBytes, String? altText) async {
      if (_minimaxClient == null || _minimaxClient != client) return '';
      final base64Str = base64.encode(imageBytes);
      final prompt = altText != null && altText.isNotEmpty
          ? 'Describe this image concisely in one sentence. Context: $altText'
          : 'Describe this image concisely in one sentence.';
      return _minimaxClient!.vision(base64Str, prompt);
    };

    // PPTX image description
    PptxConverter.imageCallback = (Uint8List imageBytes, String? altText) async {
      if (_minimaxClient == null || _minimaxClient != client) return '';
      final base64Str = base64.encode(imageBytes);
      final prompt = altText != null && altText.isNotEmpty
          ? 'Describe this presentation image concisely. Context: $altText'
          : 'Describe this presentation image concisely.';
      return _minimaxClient!.vision(base64Str, prompt);
    };
  }

  /// Stage 2: Send raw OCR text to chat LLM for structuring into Markdown.
  Future<String> _structureWithLLM(String rawText) async {
    if (_minimaxClient == null) return rawText;
    try {
      String lastContent = '';
      final stream = _minimaxClient!.chatStream(
        rawText,
        systemPrompt: PdfConverter.structurePrompt,
        thinkingBudgetTokens: 0,
        temperature: 0.3,
        maxTokens: 16384,
        toolChoice: {'type': 'none'},
      );
      final streamDone = () async {
        await for (final chunk in stream) {
          if (chunk.content != null) lastContent = chunk.content!;
          if (chunk.isContentFinished || chunk.stopReason != null) break;
        }
      }();
      try {
        await streamDone.timeout(const Duration(seconds: 30));
      } catch (_) {
        // Timeout — return whatever partial content was collected
      }
      return lastContent.isNotEmpty ? lastContent : rawText;
    } catch (_) {
      return rawText;
    }
  }

  Future<ToolResult> _safMoveFile(String safUri, String source, String destination) async {
    final relSrc = _toRelativePath(source);
    final relDst = _toRelativePath(destination);
    try {
      final content = await _safClient.readFile(safUri, relSrc);
      await _safClient.writeFile(safUri, relDst, content);
      await _safClient.deleteFile(safUri, relSrc);
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'moveFile', success: true, output: 'Moved: ${_pathNote(source, relSrc)} -> ${_pathNote(destination, relDst)} / 已移动: ${_pathNote(source, relSrc)} -> ${_pathNote(destination, relDst)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'moveFile', success: false, output: '', error: 'Move failed: $e / 移动失败: $e');
    }
  }

  Future<ToolResult> _safMkdir(String safUri, String dirPath) async {
    final relPath = '${_toRelativePath(dirPath)}/.keep';
    try {
      await _safClient.writeFile(safUri, relPath, '');
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'mkdir', success: true, output: 'Directory created: ${_pathNote(dirPath, _toRelativePath(dirPath))} / 已创建目录: ${_pathNote(dirPath, _toRelativePath(dirPath))}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'mkdir', success: false, output: '', error: 'Create directory failed: $e / 创建目录失败: $e');
    }
  }

  Future<ToolResult> _safAppendFile(String safUri, String filePath, String content) async {
    final relPath = _toRelativePath(filePath);
    try {
      final existing = await _safClient.readFile(safUri, relPath);
      await _safClient.writeFile(safUri, relPath, '$existing$content');
      fileChangeNotifier.value++;
      return ToolResult(toolName: 'appendFile', success: true, output: 'Content appended to: ${_pathNote(filePath, relPath)} / 已追加内容到: ${_pathNote(filePath, relPath)}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'appendFile', success: false, output: '', error: 'Append failed: $e / 追加失败: $e');
    }
  }

  Future<ToolResult> _getWeather(Map<String, dynamic> params) async {
    try {
      final city = params['city'] as String?;
      final adcode = params['adcode'] as String?;
      final extended = params['extended'] as bool? ?? true;
      final forecast = params['forecast'] as bool? ?? true;
      final hourly = params['hourly'] as bool? ?? false;
      final minutely = params['minutely'] as bool? ?? false;
      final indices = params['indices'] as bool? ?? false;
      final lang = params['lang'] as String? ?? 'zh';

      final client = WeatherClient();
      final data = await client.query(
        city: city, adcode: adcode, extended: extended,
        forecast: forecast, hourly: hourly,
        minutely: minutely, indices: indices, lang: lang,
      );

      final buf = StringBuffer();

      // === 第一部分：位置 + 当前实况 ===
      final province = data['province'] as String?;
      final cityName = data['city'] as String?;
      final district = data['district'] as String?;
      final loc = [province, cityName, district].where((s) => s != null && s.isNotEmpty).join(' ');
      buf.writeln('📍 $loc');
      final icon = data['weather_icon'] as String?;
      buf.writeln('🌤 ${data['weather'] ?? '-'} ${icon != null ? '[$icon] ' : ''} ${data['temperature'] ?? '-'}°C');
      buf.writeln('💧 湿度: ${data['humidity'] ?? '-'}%  风向: ${data['wind_direction'] ?? '-'} ${data['wind_power'] ?? '-'}');
      buf.writeln('🕐 更新时间: ${data['report_time'] ?? '-'}');

      // === 第二部分：扩展数据 (extended=true) ===
      if (extended) {
        final feels = data['feels_like'];
        final vis = data['visibility'];
        final pres = data['pressure'];
        final uv = data['uv'];
        final precip = data['precipitation'];
        final cloud = data['cloud'];
        final aqi = data['aqi'];
        final aqiLevel = data['aqi_level'];
        final aqiCat = data['aqi_category'];
        final aqiPrimary = data['aqi_primary'];

        final hasExtended = feels != null || vis != null || pres != null ||
            uv != null || precip != null || cloud != null || aqi != null;
        if (hasExtended) {
          buf.writeln();
          buf.writeln('--- 扩展数据 ---');
          if (feels != null) buf.write('体感: $feels°C  ');
          if (vis != null) buf.write('能见度: ${vis}km  ');
          if (pres != null) buf.write('气压: ${pres}hPa  ');
          if (uv != null) buf.write('紫外线: $uv  ');
          if (precip != null) buf.write('降水量: ${precip}mm  ');
          if (cloud != null) buf.write('云量: $cloud%  ');
          buf.writeln();
          if (aqi != null) {
            buf.write('AQI: $aqi (');
            if (aqiCat != null) buf.write('$aqiCat');
            if (aqiLevel != null) buf.write(' Lv.$aqiLevel');
            buf.write(')');
            if (aqiPrimary != null) buf.write(' 主要污染物: $aqiPrimary');
            buf.writeln();
          }

          final pollutants = _safeMap(data, 'air_pollutants');
          if (pollutants.isNotEmpty) {
            buf.write('污染物: ');
            final parts = <String>[];
            if (pollutants['pm25'] != null) parts.add('PM2.5=${pollutants['pm25']}μg/m³');
            if (pollutants['pm10'] != null) parts.add('PM10=${pollutants['pm10']}μg/m³');
            if (pollutants['o3'] != null) parts.add('O₃=${pollutants['o3']}μg/m³');
            if (pollutants['no2'] != null) parts.add('NO₂=${pollutants['no2']}μg/m³');
            if (pollutants['so2'] != null) parts.add('SO₂=${pollutants['so2']}μg/m³');
            if (pollutants['co'] != null) parts.add('CO=${pollutants['co']}mg/m³');
            buf.writeln(parts.join(', '));
          }
        }
      }

      // === 第三部分：多天预报 (forecast=true) ===
      if (forecast) {
        final tempMax = data['temp_max'];
        final tempMin = data['temp_min'];
        if (tempMax != null || tempMin != null) {
          buf.writeln();
          buf.write('📊 今天: ');
          if (tempMin != null) buf.write('↓$tempMin°C  ');
          if (tempMax != null) buf.write('↑$tempMax°C');
          buf.writeln();
        }

        final fList = _safeList(data, 'forecast');
        if (fList.isNotEmpty) {
          buf.writeln('--- 多天预报 ---');
          for (final day in fList.take(7)) {
            final d = day.cast<String, dynamic>();
            final date = d['date'] ?? '';
            final week = d['week'] ?? '';
            final wDay = d['weather_day'] ?? '-';
            final wNight = d['weather_night'] ?? '';
            final tMin = d['temp_min'] ?? '';
            final tMax = d['temp_max'] ?? '';
            final hum = d['humidity'] ?? '';
            final sr = d['sunrise'] ?? '';
            final ss = d['sunset'] ?? '';
            final wDirD = d['wind_dir_day'] ?? '';
            final wScaleD = d['wind_scale_day'] ?? '';
            final wSpeedD = d['wind_speed_day'] ?? '';
            final p = d['precip'] ?? '';
            final dVis = d['visibility'] ?? '';
            final dUv = d['uv_index'] ?? '';

            buf.write('$date $week: ');
            buf.write(wNight.isNotEmpty && wNight != wDay ? '$wDay→$wNight  ' : '$wDay  ');
            buf.write('↓$tMin°C ↑$tMax°C');
            if (hum != '') buf.write('  💧$hum%');
            if (p != '' && p != 0) buf.write('  🌧${p}mm');
            if (sr != '' && ss != '') buf.write('  ☀$sr-$ss');
            buf.writeln();
            if (wDirD != '' || wScaleD != '' || wSpeedD != '') {
              buf.write('  风: ');
              if (wDirD != '') buf.write('$wDirD ');
              if (wScaleD != '') buf.write('$wScaleD ');
              if (wSpeedD != '') buf.write('${wSpeedD}km/h');
              buf.writeln();
            }
            if (dVis != '' || dUv != '') {
              buf.write('  ');
              if (dVis != '') buf.write('能见度: ${dVis}km  ');
              if (dUv != '') buf.write('紫外线: $dUv');
              buf.writeln();
            }
          }
        }
      }

      // === 第四部分：逐小时预报 (hourly=true) ===
      if (hourly) {
        final hList = _safeList(data, 'hourly_forecast');
        if (hList.isNotEmpty) {
          buf.writeln();
          buf.writeln('--- 逐小时预报 ---');
          for (final d in hList.take(24)) {
            final time = (d['time'] as String?) ?? '';
            final t = d['temperature'] ?? '';
            final w = d['weather'] ?? '';
            final fl = d['feels_like'] ?? '';
            final pop = d['pop'] ?? '';
            final hHum = d['humidity'] ?? '';
            final hPrecip = d['precip'] ?? '';
            final hVis = d['visibility'] ?? '';
            final hUv = d['uv_index'] ?? '';
            final hWindDir = d['wind_direction'] ?? '';
            final hWindSpeed = d['wind_speed'] ?? '';
            final hWindScale = d['wind_scale'] ?? '';

            final shortTime = time.length > 16 ? time.substring(11, 16) : time;
            buf.write('$shortTime: $w  $t°C');
            if (fl != '') buf.write(' (体感$fl°C)');
            if (pop != '' && pop != 0) buf.write('  💧降水概率$pop%');
            if (hHum != '') buf.write('  湿度$hHum%');
            if (hPrecip != '' && hPrecip != 0) buf.write('  降水${hPrecip}mm');
            if (hWindDir != '' || hWindScale != '' || hWindSpeed != '') {
              buf.write('  ');
              if (hWindDir != '') buf.write('$hWindDir ');
              if (hWindScale != '') buf.write('$hWindScale ');
              if (hWindSpeed != '') buf.write('${hWindSpeed}km/h');
            }
            if (hVis != '') buf.write('  能见度${hVis}km');
            if (hUv != '' && hUv != 0) buf.write('  UV$hUv');
            buf.writeln();
          }
        }
      }

      // === 第五部分：分钟级降水 (minutely=true, 仅国内) ===
      if (minutely) {
        final mp = _safeMap(data, 'minutely_precip');
        if (mp.isNotEmpty) {
          buf.writeln();
          buf.writeln('--- 分钟级降水 ---');
          buf.writeln('${mp['summary'] ?? '-'}');
          buf.writeln('更新时间: ${mp['update_time'] ?? '-'}');
          final mpData = _safeList(mp, 'data');
          if (mpData.isNotEmpty) {
            buf.writeln('未来降水趋势:');
            for (final p in mpData.take(15)) {
              final ptTime = (p['time'] as String?) ?? '';
              final ptPrecip = p['precip'] ?? 0;
              final ptType = p['type'] as String? ?? '';
              final shortTime = ptTime.length > 16 ? ptTime.substring(11, 16) : ptTime;
              final icon2 = ptType == 'snow' ? '❄' : '🌧';
              buf.writeln('  $shortTime: $icon2 ${ptPrecip}mm');
            }
          }
        }
      }

      // === 第六部分：生活指数 (indices=true) ===
      if (indices) {
        final idx = _safeMap(data, 'life_indices');
        if (idx.isNotEmpty) {
          buf.writeln();
          buf.writeln('--- 18项生活指数 ---');
          const names = {
            'clothing': '穿衣', 'uv': '紫外线', 'car_wash': '洗车', 'drying': '晾晒',
            'air_conditioner': '空调', 'cold_risk': '感冒', 'exercise': '运动',
            'comfort': '舒适度', 'travel': '出行', 'fishing': '钓鱼',
            'allergy': '过敏', 'sunscreen': '防晒', 'mood': '心情',
            'beer': '啤酒', 'umbrella': '雨伞', 'traffic': '交通',
            'air_purifier': '空气净化器', 'pollen': '花粉',
          };
          const order = [
            'comfort', 'clothing', 'uv', 'sunscreen', 'umbrella', 'car_wash',
            'drying', 'air_conditioner', 'cold_risk', 'exercise', 'travel',
            'traffic', 'fishing', 'beer', 'mood', 'allergy', 'air_purifier', 'pollen',
          ];
          for (final key in order) {
            final v = _safeMap(idx, key);
            if (v.isNotEmpty) {
              final level = v['level'] as String? ?? '';
              final advice = v['advice'] as String? ?? '';
              buf.writeln('  ${names[key] ?? key}: $level — $advice');
            }
          }
        }
      }

      // === 第七部分：气象预警 ===
      final alerts = _safeList(data, 'alerts');
      if (alerts.isNotEmpty) {
        buf.writeln();
        buf.writeln('⚠️ 气象预警 (${alerts.length}条):');
        for (final alert in alerts) {
          buf.writeln('  【${alert['type'] ?? ''}${alert['level'] ?? ''}】${alert['title'] ?? ''}');
          final text = alert['text']?.toString();
          if (text != null && text.isNotEmpty) {
            buf.writeln('    $text');
          }
          final pubTime = alert['publish_time']?.toString();
          final publisher = alert['publisher']?.toString();
          if (pubTime != null || publisher != null) {
            buf.write('    发布时间: ${pubTime ?? '-'}');
            if (publisher != null) buf.write('  发布单位: $publisher');
            buf.writeln();
          }
          final guidance = _safeListRaw(alert, 'guidance');
          if (guidance.isNotEmpty) {
            buf.writeln('    防御指引:');
            for (final g in guidance) {
              buf.writeln('      - $g');
            }
          }
        }
      }

      final output = buf.toString();
      return ToolResult(toolName: 'getWeather', success: true, output: '\n\n$output\n\n');
    } on WeatherException catch (e) {
      return ToolResult(toolName: 'getWeather', success: false, output: '',
          error: '天气查询失败: ${e.message}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'getWeather', success: false, output: '',
          error: '天气查询失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 高德地图工具实现
  // ═══════════════════════════════════════════════════════════

  Future<AmapClient> _getAmapClient() async {
    final key = await _settingsRepo.getAmapApiKey();
    if (key.isEmpty) {
      throw AmapException('NO_KEY', '请先在设置中配置高德地图 API Key');
    }
    // Always create fresh client to pick up key changes from settings
    final client = AmapClient(apiKey: key);
    _amapClient = client;
    return client;
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} 公里';
    }
    return '${meters.toInt()} 米';
  }

  // ── 地理编码 ──
  Future<ToolResult> _amapGeocode(Map<String, dynamic> params) async {
    try {
      final address = params['address'] as String?;
      if (address == null || address.isEmpty) {
        return const ToolResult(toolName: 'geocode', success: false, output: '', error: '缺少 address 参数');
      }
      final city = params['city'] as String?;
      final client = await _getAmapClient();
      final results = await client.geocode(address, city: city);

      if (results.isEmpty) {
        return ToolResult(toolName: 'geocode', success: true, output: '未找到与 "$address" 匹配的坐标。请尝试更详细的地址。');
      }

      final buf = StringBuffer();
      buf.writeln('地理编码结果（共 ${results.length} 条）:');
      for (final r in results) {
        buf.writeln('  📍 ${r.name ?? r.address}');
        buf.writeln('     坐标: ${r.location.lng}, ${r.location.lat}');
        if (r.city != null) buf.writeln('     城市: ${r.city}');
        if (r.adcode != null) buf.writeln('     区划代码: ${r.adcode}');
      }

      // Publish to map
      final first = results.first;
      final action = ShowLocationAction(
        location: first.location,
        name: first.name,
        address: first.address,
      );
      mapActionBus.value = action;
      addToHistory(action);
      mapActionPending.value = action;

      return ToolResult(toolName: 'geocode', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'geocode', success: false, output: '', error: '地理编码失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'geocode', success: false, output: '', error: '地理编码失败: $e');
    }
  }

  // ── 逆地理编码 ──
  Future<ToolResult> _amapRegeocode(Map<String, dynamic> params) async {
    try {
      final lng = (params['lng'] as num?)?.toDouble();
      final lat = (params['lat'] as num?)?.toDouble();
      if (lng == null || lat == null) {
        return const ToolResult(toolName: 'regeocode', success: false, output: '', error: '缺少 lng/lat 参数');
      }
      final client = await _getAmapClient();
      final result = await client.regeocode(GeoPoint(lng, lat));

      if (result == null) {
        return const ToolResult(toolName: 'regeocode', success: true, output: '未找到该坐标对应的地址。');
      }

      final buf = StringBuffer();
      buf.writeln('逆地理编码结果:');
      buf.writeln('  📍 ${result.address}');
      if (result.city != null) buf.writeln('  城市: ${result.city}');
      if (result.adcode != null) buf.writeln('  区划代码: ${result.adcode}');
      buf.writeln('  坐标: $lng, $lat');
      return ToolResult(toolName: 'regeocode', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'regeocode', success: false, output: '', error: '逆地理编码失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'regeocode', success: false, output: '', error: '逆地理编码失败: $e');
    }
  }

  // ── POI 搜索 ──
  Future<ToolResult> _amapSearchPlaces(Map<String, dynamic> params) async {
    try {
      final keywords = params['keywords'] as String?;
      if (keywords == null || keywords.isEmpty) {
        return const ToolResult(toolName: 'search_places', success: false, output: '', error: '缺少 keywords 参数');
      }
      final city = params['city'] as String?;
      final type = params['type'] as String?;
      final region = params['region'] as String?;
      final cityLimit = params['city_limit'] == true;
      final showFieldsStr = params['show_fields'] as String?;
      final showFields = showFieldsStr?.split(',');
      final page = (params['page'] as num?)?.toInt() ?? 1;
      final pageSize = (params['page_size'] as num?)?.toInt() ?? 20;
      final client = await _getAmapClient();
      final result = await client.searchPoi(
        keywords,
        city: city,
        type: type,
        region: region,
        cityLimit: cityLimit,
        showFields: showFields,
        page: page,
        offset: pageSize,
      );

      if (result.pois.isEmpty) {
        return ToolResult(toolName: 'search_places', success: true,
            output: '未找到与 "$keywords" 相关的地点。');
      }

      final buf = StringBuffer();
      buf.writeln('搜索 "$keywords" 结果（共 ${result.count} 条，显示前 ${result.pois.length} 条）:');
      for (int i = 0; i < result.pois.length; i++) {
        final p = result.pois[i];
        buf.writeln('  ${i + 1}. ${p.name}');
        buf.writeln('     地址: ${p.address}');
        if (p.tel != null && p.tel!.isNotEmpty) buf.writeln('     电话: ${p.tel}');
        if (p.distance != null) buf.writeln('     距离: ${p.distance}米');
        buf.writeln('     坐标: ${p.location.lng}, ${p.location.lat}');
        if (p.type != null) buf.writeln('     类型: ${p.type}');
        if (p.typecode != null) buf.writeln('     类型码: ${p.typecode}');
      }

      // Publish to map
      final poisAction = ShowPoisAction(title: '搜索: $keywords', pois: result.pois);
      mapActionBus.value = poisAction;
      addToHistory(poisAction);
      mapActionPending.value = poisAction;

      return ToolResult(toolName: 'search_places', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'search_places', success: false, output: '', error: 'POI搜索失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'search_places', success: false, output: '', error: 'POI搜索失败: $e');
    }
  }

  // ── POI详情查询 ──
  Future<ToolResult> _amapPoiDetail(Map<String, dynamic> params) async {
    try {
      final poiId = params['poi_id'] as String?;
      if (poiId == null || poiId.isEmpty) {
        return const ToolResult(toolName: 'poi_detail', success: false, output: '', error: '缺少 poi_id 参数');
      }
      final client = await _getAmapClient();
      final detail = await client.getPoiDetail(poiId);

      if (detail == null) {
        return ToolResult(toolName: 'poi_detail', success: true, output: '未找到该POI的详细信息。');
      }

      final buf = StringBuffer();
      buf.writeln('【${detail.name}】');
      if (detail.address.isNotEmpty) buf.writeln('地址: ${detail.address}');
      if (detail.tel != null && detail.tel!.isNotEmpty) buf.writeln('电话: ${detail.tel}');
      if (detail.type != null && detail.type!.isNotEmpty) buf.writeln('类型: ${detail.type}');
      if (detail.typecode != null) buf.writeln('类型码: ${detail.typecode}');
      if (detail.province != null && detail.province!.isNotEmpty) buf.writeln('省份: ${detail.province}');
      if (detail.city != null && detail.city!.isNotEmpty) buf.writeln('城市: ${detail.city}');
      if (detail.district != null && detail.district!.isNotEmpty) buf.writeln('区域: ${detail.district}');
      if (detail.rating != null) buf.writeln('评分: ${detail.rating}');
      if (detail.openingHours != null && detail.openingHours!.isNotEmpty) buf.writeln('营业时间: ${detail.openingHours}');
      if (detail.businessArea != null && detail.businessArea!.isNotEmpty) buf.writeln('商圈: ${detail.businessArea}');
      if (detail.website != null && detail.website!.isNotEmpty) buf.writeln('网站: ${detail.website}');
      if (detail.email != null && detail.email!.isNotEmpty) buf.writeln('邮箱: ${detail.email}');
      buf.writeln('坐标: ${detail.location.lng}, ${detail.location.lat}');
      if (detail.photos != null && detail.photos!.isNotEmpty) {
        buf.writeln('图片: ${detail.photos!.length}张');
        for (int i = 0; i < detail.photos!.length && i < 3; i++) {
          buf.writeln('  ${detail.photos![i]}');
        }
      }

      return ToolResult(toolName: 'poi_detail', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'poi_detail', success: false, output: '', error: 'POI详情查询失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'poi_detail', success: false, output: '', error: 'POI详情查询失败: $e');
    }
  }

  // ── 周边搜索 ──
  Future<ToolResult> _amapSearchNearby(Map<String, dynamic> params) async {
    try {
      var lng = (params['lng'] as num?)?.toDouble();
      var lat = (params['lat'] as num?)?.toDouble();
      if (lng == null || lat == null) {
        // Auto-fetch current location
        try {
          final loc = await LocationClient().getCurrentPosition();
          lng = (loc['longitude'] as num?)?.toDouble();
          lat = (loc['latitude'] as num?)?.toDouble();
        } catch (_) {}
        if (lng == null || lat == null) {
          return const ToolResult(toolName: 'search_nearby', success: false, output: '', error: '缺少坐标参数，且无法获取当前设备位置');
        }
      }
      final radius = params['radius'] as int? ?? 1000;
      final keywords = params['keywords'] as String?;
      final sortrule = params['sortrule'] as String?;
      final region = params['region'] as String?;
      final cityLimit = params['city_limit'] == true;
      final showFieldsStr = params['show_fields'] as String?;
      final showFields = showFieldsStr?.split(',');
      final page = (params['page'] as num?)?.toInt() ?? 1;
      final pageSize = (params['page_size'] as num?)?.toInt() ?? 20;
      final client = await _getAmapClient();
      final result = await client.searchNearby(
        GeoPoint(lng, lat),
        radius,
        keywords: keywords,
        sortrule: sortrule,
        region: region,
        cityLimit: cityLimit,
        showFields: showFields,
        page: page,
        offset: pageSize,
      );

      if (result.pois.isEmpty) {
        return ToolResult(toolName: 'search_nearby', success: true,
            output: '在坐标 ($lng, $lat) 周边 $radius米 范围内未找到${keywords != null ? " \"$keywords\"" : ""}相关地点。');
      }

      final buf = StringBuffer();
      buf.writeln('周边搜索${keywords != null ? " \"$keywords\"" : ""} 结果（半径 $radius米，共 ${result.count} 条）:');
      for (int i = 0; i < result.pois.length; i++) {
        final p = result.pois[i];
        buf.writeln('  ${i + 1}. ${p.name}');
        buf.writeln('     地址: ${p.address}');
        if (p.distance != null) buf.writeln('     距离: ${p.distance}米');
        if (p.tel != null && p.tel!.isNotEmpty) buf.writeln('     电话: ${p.tel}');
        if (p.type != null) buf.writeln('     类型: ${p.type}');
        if (p.rating != null) buf.writeln('     评分: ${p.rating}');
      }

      // Publish to map
      final nearbyAction = ShowPoisAction(title: '周边: ${keywords ?? "附近"}', pois: result.pois);
      mapActionBus.value = nearbyAction;
      addToHistory(nearbyAction);
      mapActionPending.value = nearbyAction;

      return ToolResult(toolName: 'search_nearby', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'search_nearby', success: false, output: '', error: '周边搜索失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'search_nearby', success: false, output: '', error: '周边搜索失败: $e');
    }
  }

  // ── 驾车路线 ──
  Future<ToolResult> _amapDrivingRoute(Map<String, dynamic> params) async {
    try {
      final oLng = (params['origin_lng'] as num?)?.toDouble();
      final oLat = (params['origin_lat'] as num?)?.toDouble();
      final dLng = (params['dest_lng'] as num?)?.toDouble();
      final dLat = (params['dest_lat'] as num?)?.toDouble();
      if (oLng == null || oLat == null || dLng == null || dLat == null) {
        return const ToolResult(toolName: 'plan_driving_route', success: false, output: '', error: '缺少起终点坐标参数');
      }
      final strategy = params['strategy'] as int? ?? 0;
      final client = await _getAmapClient();
      final route = await client.drivingRoute(GeoPoint(oLng, oLat), GeoPoint(dLng, dLat), strategy: strategy);

      final buf = StringBuffer();
      buf.writeln('🚗 驾车路线:');
      buf.writeln('  距离: ${_formatDistance(route.distance)}');
      buf.writeln('  预计用时: ${route.duration}');
      if (route.taxiCost != null) buf.writeln('  预估费用: ${route.taxiCost}');
      if (route.steps != null && route.steps!.isNotEmpty) {
        buf.writeln('  路线步骤:');
        for (int i = 0; i < route.steps!.length; i++) {
          final s = route.steps![i];
          buf.writeln('    ${i + 1}. ${s.instruction} (${s.distance} / ${s.duration})');
        }
      }

      // Publish to map
      final drivingAction = ShowRouteAction(
        routeType: 'driving',
        origin: GeoPoint(oLng, oLat),
        destination: GeoPoint(dLng, dLat),
        distance: route.distance,
        duration: route.duration,
        polyline: route.polyline,
        steps: route.steps,
        taxiCost: route.taxiCost,
      );
      mapActionBus.value = drivingAction;
      addToHistory(drivingAction);
      mapActionPending.value = drivingAction;

      return ToolResult(toolName: 'plan_driving_route', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'plan_driving_route', success: false, output: '', error: '驾车路线规划失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'plan_driving_route', success: false, output: '', error: '驾车路线规划失败: $e');
    }
  }

  // ── 公交路线 ──
  Future<ToolResult> _amapTransitRoute(Map<String, dynamic> params) async {
    try {
      final oLng = (params['origin_lng'] as num?)?.toDouble();
      final oLat = (params['origin_lat'] as num?)?.toDouble();
      final dLng = (params['dest_lng'] as num?)?.toDouble();
      final dLat = (params['dest_lat'] as num?)?.toDouble();
      if (oLng == null || oLat == null || dLng == null || dLat == null) {
        return const ToolResult(toolName: 'plan_transit_route', success: false, output: '', error: '缺少起终点坐标参数');
      }
      final city = params['city'] as String?;
      final strategy = params['strategy'] as int? ?? 0;
      final client = await _getAmapClient();
      final routes = await client.transitRoute(GeoPoint(oLng, oLat), GeoPoint(dLng, dLat), city: city, strategy: strategy);

      if (routes.isEmpty) {
        return const ToolResult(toolName: 'plan_transit_route', success: true, output: '未找到公交/地铁路线方案。请检查起终点是否正确，或尝试其他出行方式。');
      }

      final buf = StringBuffer();
      buf.writeln('🚌 公交/地铁路线（共 ${routes.length} 条方案）:');
      for (int r = 0; r < routes.length; r++) {
        final route = routes[r];
        buf.writeln('');
        buf.writeln('═══ 方案 ${r + 1} ═══');
        buf.writeln('  总距离: ${_formatDistance(route.distance)}');
        buf.writeln('  总用时: ${route.duration}');
        if (route.cost != null && route.cost! > 0) buf.writeln('  费用: ¥${route.cost!.toStringAsFixed(1)}');
        if (route.taxiCost != null) buf.writeln('  打车参考价: ${route.taxiCost}');

        if (route.transitSegments != null) {
          buf.writeln('  换乘方案:');
          for (int s = 0; s < route.transitSegments!.length; s++) {
            final seg = route.transitSegments![s];
            final icon = seg.type == 'walk' ? '🚶' : seg.type == 'subway' ? '🚇' : '🚌';
            if (seg.type == 'walk') {
              buf.writeln('    $icon 步行 ${seg.distance} (${seg.duration})');
            } else {
              buf.writeln('    $icon ${seg.lineName ?? ""} (${seg.type == "subway" ? "地铁" : "公交"})');
              if (seg.departureStop != null) buf.writeln('        上车: ${seg.departureStop}');
              if (seg.arrivalStop != null) buf.writeln('        下车: ${seg.arrivalStop}');
              if (seg.stopCount > 0) buf.writeln('        经停: ${seg.stopCount} 站');
            }
          }
        }
      }

      // Publish first route to map (transit has no polyline)
      if (routes.isNotEmpty) {
        final first = routes.first;
        final transitAction = ShowRouteAction(
          routeType: 'transit',
          origin: GeoPoint(oLng, oLat),
          destination: GeoPoint(dLng, dLat),
          distance: first.distance,
          duration: first.duration,
          polyline: null,
          cost: first.cost,
          taxiCost: first.taxiCost,
        );
        mapActionBus.value = transitAction;
        addToHistory(transitAction);
        mapActionPending.value = transitAction;
      }

      return ToolResult(toolName: 'plan_transit_route', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'plan_transit_route', success: false, output: '', error: '公交路线规划失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'plan_transit_route', success: false, output: '', error: '公交路线规划失败: $e');
    }
  }

  // ── 步行路线 ──
  Future<ToolResult> _amapWalkingRoute(Map<String, dynamic> params) async {
    try {
      final oLng = (params['origin_lng'] as num?)?.toDouble();
      final oLat = (params['origin_lat'] as num?)?.toDouble();
      final dLng = (params['dest_lng'] as num?)?.toDouble();
      final dLat = (params['dest_lat'] as num?)?.toDouble();
      if (oLng == null || oLat == null || dLng == null || dLat == null) {
        return const ToolResult(toolName: 'plan_walking_route', success: false, output: '', error: '缺少起终点坐标参数');
      }
      final client = await _getAmapClient();
      final route = await client.walkingRoute(GeoPoint(oLng, oLat), GeoPoint(dLng, dLat));

      final buf = StringBuffer();
      buf.writeln('🚶 步行路线:');
      buf.writeln('  距离: ${_formatDistance(route.distance)}');
      buf.writeln('  预计用时: ${route.duration}');
      if (route.steps != null && route.steps!.isNotEmpty) {
        buf.writeln('  路线步骤:');
        for (int i = 0; i < route.steps!.length; i++) {
          final s = route.steps![i];
          buf.writeln('    ${i + 1}. ${s.instruction} (${s.distance})');
        }
      }

      // Publish to map
      final walkingAction = ShowRouteAction(
        routeType: 'walking',
        origin: GeoPoint(oLng, oLat),
        destination: GeoPoint(dLng, dLat),
        distance: route.distance,
        duration: route.duration,
        polyline: route.polyline,
        steps: route.steps,
      );
      mapActionBus.value = walkingAction;
      addToHistory(walkingAction);
      mapActionPending.value = walkingAction;

      return ToolResult(toolName: 'plan_walking_route', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'plan_walking_route', success: false, output: '', error: '步行路线规划失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'plan_walking_route', success: false, output: '', error: '步行路线规划失败: $e');
    }
  }

  // ── 骑行路线 ──
  Future<ToolResult> _amapCyclingRoute(Map<String, dynamic> params) async {
    try {
      final oLng = (params['origin_lng'] as num?)?.toDouble();
      final oLat = (params['origin_lat'] as num?)?.toDouble();
      final dLng = (params['dest_lng'] as num?)?.toDouble();
      final dLat = (params['dest_lat'] as num?)?.toDouble();
      if (oLng == null || oLat == null || dLng == null || dLat == null) {
        return const ToolResult(toolName: 'plan_cycling_route', success: false, output: '', error: '缺少起终点坐标参数');
      }
      final client = await _getAmapClient();
      final route = await client.cyclingRoute(GeoPoint(oLng, oLat), GeoPoint(dLng, dLat));

      final buf = StringBuffer();
      buf.writeln('🚴 骑行路线:');
      buf.writeln('  距离: ${_formatDistance(route.distance)}');
      buf.writeln('  预计用时: ${route.duration}');
      if (route.steps != null && route.steps!.isNotEmpty) {
        buf.writeln('  路线步骤:');
        for (int i = 0; i < route.steps!.length; i++) {
          final s = route.steps![i];
          buf.writeln('    ${i + 1}. ${s.instruction} (${s.distance})');
        }
      }

      // Publish to map (cycling v4 API may not return polyline)
      final cyclingAction = ShowRouteAction(
        routeType: 'cycling',
        origin: GeoPoint(oLng, oLat),
        destination: GeoPoint(dLng, dLat),
        distance: route.distance,
        duration: route.duration,
        polyline: route.polyline,
        steps: route.steps,
      );
      mapActionBus.value = cyclingAction;
      addToHistory(cyclingAction);
      mapActionPending.value = cyclingAction;

      return ToolResult(toolName: 'plan_cycling_route', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'plan_cycling_route', success: false, output: '', error: '骑行路线规划失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'plan_cycling_route', success: false, output: '', error: '骑行路线规划失败: $e');
    }
  }

  // ── 电动车路线 ──
  Future<ToolResult> _amapElectrobikeRoute(Map<String, dynamic> params) async {
    try {
      final oLng = (params['origin_lng'] as num?)?.toDouble();
      final oLat = (params['origin_lat'] as num?)?.toDouble();
      final dLng = (params['dest_lng'] as num?)?.toDouble();
      final dLat = (params['dest_lat'] as num?)?.toDouble();
      if (oLng == null || oLat == null || dLng == null || dLat == null) {
        return const ToolResult(toolName: 'plan_electrobike_route', success: false, output: '', error: '缺少起终点坐标参数');
      }
      final client = await _getAmapClient();
      final route = await client.electrobikeRoute(GeoPoint(oLng, oLat), GeoPoint(dLng, dLat));

      final buf = StringBuffer();
      buf.writeln('🛵 电动车路线:');
      buf.writeln('  距离: ${_formatDistance(route.distance)}');
      buf.writeln('  预计用时: ${route.duration}');
      if (route.steps != null && route.steps!.isNotEmpty) {
        buf.writeln('  路线步骤:');
        for (int i = 0; i < route.steps!.length; i++) {
          final s = route.steps![i];
          buf.writeln('    ${i + 1}. ${s.instruction} (${s.distance})');
        }
      }

      final electrobikeAction = ShowRouteAction(
        routeType: 'electrobike',
        origin: GeoPoint(oLng, oLat),
        destination: GeoPoint(dLng, dLat),
        distance: route.distance,
        duration: route.duration,
        polyline: route.polyline,
        steps: route.steps,
      );
      mapActionBus.value = electrobikeAction;
      addToHistory(electrobikeAction);
      mapActionPending.value = electrobikeAction;

      return ToolResult(toolName: 'plan_electrobike_route', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'plan_electrobike_route', success: false, output: '', error: '电动车路线规划失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'plan_electrobike_route', success: false, output: '', error: '电动车路线规划失败: $e');
    }
  }

  // ── 实时公交到站 ──
  Future<ToolResult> _amapBusArrival(Map<String, dynamic> params) async {
    try {
      final city = params['city'] as String?;
      final stopName = params['stop_name'] as String?;
      if (city == null || city.isEmpty || stopName == null || stopName.isEmpty) {
        return const ToolResult(toolName: 'get_bus_arrival', success: false, output: '', error: '缺少 city/stop_name 参数');
      }
      final lineName = params['line_name'] as String?;
      final client = await _getAmapClient();
      final arrivals = await client.getBusArrival(city, stopName, busName: lineName);

      if (arrivals.isEmpty) {
        return ToolResult(toolName: 'get_bus_arrival', success: true,
            output: '未查询到 "$stopName" 的实时公交信息。可能原因：该站点不存在、该城市不支持实时数据、无经过线路。');
      }

      final buf = StringBuffer();
      buf.writeln('🚏 公交实时到站 - $stopName ($city):');
      for (final a in arrivals) {
        buf.writeln('');
        buf.writeln('  ${a.busName} (往 ${a.direction}):');
        for (final l in a.lines) {
          buf.write('    ➤ ${l.name}');
          if (l.etaText != null) {
            buf.write(' — ${l.etaText}');
          } else if (l.etaSeconds != null) {
            final mins = l.etaSeconds! ~/ 60;
            buf.write(' — 约$mins分钟后到达');
          }
          if (l.distanceMeters != null) buf.write(' (距本站 ${l.distanceMeters} 米)');
          if (l.busCount != null && l.busCount! > 0) buf.write(' [${l.busCount} 辆在途]');
          buf.writeln();
        }
      }
      return ToolResult(toolName: 'get_bus_arrival', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'get_bus_arrival', success: false, output: '', error: '公交到站查询失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'get_bus_arrival', success: false, output: '', error: '公交到站查询失败: $e');
    }
  }

  // ── 公交站 ID 查询 ──
  Future<ToolResult> _amapBusStopById(Map<String, dynamic> params) async {
    try {
      final stopId = params['stop_id'] as String?;
      if (stopId == null || stopId.isEmpty) {
        return const ToolResult(toolName: 'bus_stop_by_id', success: false, output: '', error: '缺少 stop_id 参数');
      }
      final extensions = params['extensions'] as String?;
      final client = await _getAmapClient();
      final stop = await client.getBusStopById(stopId, extensions: extensions);
      if (stop == null) {
        return ToolResult(toolName: 'bus_stop_by_id', success: true, output: '未找到该公交站信息。');
      }
      final buf = StringBuffer();
      buf.writeln('🚏 公交站信息 - ${stop.name}:');
      buf.writeln('  ID: ${stop.id}');
      buf.writeln('  坐标: ${stop.location.lng}, ${stop.location.lat}');
      if (stop.adcode != null) buf.writeln('  行政区划: ${stop.adcode}');
      if (stop.citycode != null) buf.writeln('  城市码: ${stop.citycode}');
      if (stop.buslines != null && stop.buslines!.isNotEmpty) {
        buf.writeln('  途经线路 (${stop.buslines!.length} 条):');
        for (final line in stop.buslines!) {
          buf.writeln('    • ${line.name} (${line.startStop} → ${line.endStop})');
        }
      }
      return ToolResult(toolName: 'bus_stop_by_id', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'bus_stop_by_id', success: false, output: '', error: '公交站查询失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'bus_stop_by_id', success: false, output: '', error: '公交站查询失败: $e');
    }
  }

  // ── 公交站关键字查询 ──
  Future<ToolResult> _amapSearchBusStop(Map<String, dynamic> params) async {
    try {
      final keywords = params['keywords'] as String?;
      if (keywords == null || keywords.isEmpty) {
        return const ToolResult(toolName: 'search_bus_stop', success: false, output: '', error: '缺少 keywords 参数');
      }
      final city = params['city'] as String?;
      final extensions = params['extensions'] as String?;
      final page = (params['page'] as num?)?.toInt() ?? 1;
      final offset = (params['offset'] as num?)?.toInt() ?? 20;
      final client = await _getAmapClient();
      final stops = await client.searchBusStop(keywords, city: city, page: page, offset: offset, extensions: extensions);
      if (stops.isEmpty) {
        return ToolResult(toolName: 'search_bus_stop', success: true, output: '未找到 "$keywords" 相关的公交站。');
      }
      final buf = StringBuffer();
      buf.writeln('🚌 公交站搜索 "$keywords" 结果 (共 ${stops.length} 条):');
      for (int i = 0; i < stops.length; i++) {
        final s = stops[i];
        buf.writeln('  ${i + 1}. ${s.name}');
        buf.writeln('     坐标: ${s.location.lng}, ${s.location.lat}');
        if (s.buslines != null && s.buslines!.isNotEmpty) {
          buf.writeln('     途经: ${s.buslines!.map((l) => l.name).join(', ')}');
        }
      }
      return ToolResult(toolName: 'search_bus_stop', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'search_bus_stop', success: false, output: '', error: '公交站搜索失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'search_bus_stop', success: false, output: '', error: '公交站搜索失败: $e');
    }
  }

  // ── 公交路线 ID 查询 ──
  Future<ToolResult> _amapBusLineById(Map<String, dynamic> params) async {
    try {
      final lineId = params['line_id'] as String?;
      if (lineId == null || lineId.isEmpty) {
        return const ToolResult(toolName: 'bus_line_by_id', success: false, output: '', error: '缺少 line_id 参数');
      }
      final extensions = params['extensions'] as String?;
      final client = await _getAmapClient();
      final line = await client.getBusLineById(lineId, extensions: extensions);
      if (line == null) {
        return ToolResult(toolName: 'bus_line_by_id', success: true, output: '未找到该公交线路信息。');
      }
      final buf = StringBuffer();
      buf.writeln('🚌 公交线路 - ${line.name}:');
      buf.writeln('  类型: ${line.type}');
      buf.writeln('  区间: ${line.startStop} → ${line.endStop}');
      if (line.startTime != null && line.endTime != null) buf.writeln('  运营时间: ${line.startTime} - ${line.endTime}');
      if (line.distance != null) buf.writeln('  全程距离: ${line.distance} 公里');
      if (line.basicPrice != null && line.totalPrice != null) buf.writeln('  票价: ¥${line.basicPrice} - ¥${line.totalPrice}');
      if (line.company != null) buf.writeln('  所属公司: ${line.company}');
      if (line.loop != null) buf.writeln('  环线: ${line.loop == 1 ? "是" : "否"}');
      buf.writeln('  坐标串: ${line.polyline}');
      if (line.busstops != null && line.busstops!.isNotEmpty) {
        buf.writeln('  途经站点 (${line.busstops!.length} 站):');
        for (final st in line.busstops!) {
          buf.writeln('    ${st.sequence}. ${st.name}');
        }
      }
      return ToolResult(toolName: 'bus_line_by_id', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'bus_line_by_id', success: false, output: '', error: '公交线路查询失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'bus_line_by_id', success: false, output: '', error: '公交线路查询失败: $e');
    }
  }

  // ── 公交路线关键字查询 ──
  Future<ToolResult> _amapSearchBusLine(Map<String, dynamic> params) async {
    try {
      final keywords = params['keywords'] as String?;
      if (keywords == null || keywords.isEmpty) {
        return const ToolResult(toolName: 'search_bus_line', success: false, output: '', error: '缺少 keywords 参数');
      }
      final city = params['city'] as String?;
      if (city == null || city.isEmpty) {
        return const ToolResult(toolName: 'search_bus_line', success: false, output: '', error: '缺少 city 参数');
      }
      final extensions = params['extensions'] as String?;
      final page = (params['page'] as num?)?.toInt() ?? 1;
      final offset = (params['offset'] as num?)?.toInt() ?? 20;
      final client = await _getAmapClient();
      final lines = await client.searchBusLine(keywords, city: city, page: page, offset: offset, extensions: extensions);
      if (lines.isEmpty) {
        return ToolResult(toolName: 'search_bus_line', success: true, output: '未找到 "$keywords" 相关的公交线路。');
      }
      final buf = StringBuffer();
      buf.writeln('🚌 公交线路搜索 "$keywords" 结果 (共 ${lines.length} 条):');
      for (int i = 0; i < lines.length; i++) {
        final l = lines[i];
        buf.writeln('  ${i + 1}. ${l.name}');
        buf.writeln('     类型: ${l.type} | ${l.startStop} → ${l.endStop}');
        if (l.startTime != null && l.endTime != null) buf.writeln('     运营: ${l.startTime}-${l.endTime}');
        if (l.distance != null) buf.writeln('     全程: ${l.distance}公里');
      }
      return ToolResult(toolName: 'search_bus_line', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'search_bus_line', success: false, output: '', error: '公交线路搜索失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'search_bus_line', success: false, output: '', error: '公交线路搜索失败: $e');
    }
  }

  // ── 交通路况 (圆形/线路/矩形) ──
  Future<ToolResult> _amapTrafficStatus(Map<String, dynamic> params) async {
    try {
      final type = params['type'] as String? ?? 'circle';
      final level = params['level'] as int? ?? 6;
      final allExtensions = params['extensions'] != 'base';
      final client = await _getAmapClient();

      TrafficInfo? status;

      if (type == 'road') {
        // 指定线路交通态势
        final roadName = params['road_name'] as String?;
        final adcode = params['adcode'] as String?;
        if (roadName == null || roadName.isEmpty) {
          return const ToolResult(toolName: 'get_traffic_status', success: false, output: '', error: '缺少 road_name 参数');
        }
        if (adcode == null || adcode.isEmpty) {
          return const ToolResult(toolName: 'get_traffic_status', success: false, output: '', error: '缺少 adcode 参数');
        }
        status = await client.getRoadTrafficStatus(
          roadName: roadName,
          adcode: adcode,
          level: level,
          allExtensions: allExtensions,
        );
      } else if (type == 'rectangle') {
        // 矩形区域交通态势
        final swLng = (params['sw_lng'] as num?)?.toDouble();
        final swLat = (params['sw_lat'] as num?)?.toDouble();
        final neLng = (params['ne_lng'] as num?)?.toDouble();
        final neLat = (params['ne_lat'] as num?)?.toDouble();
        if (swLng == null || swLat == null || neLng == null || neLat == null) {
          return const ToolResult(toolName: 'get_traffic_status', success: false, output: '', error: '缺少矩形坐标参数 (sw_lng/sw_lat/ne_lng/ne_lat)');
        }
        status = await client.getRectangleTrafficStatus(
          southwest: GeoPoint(swLng, swLat),
          northeast: GeoPoint(neLng, neLat),
          level: level,
          allExtensions: allExtensions,
        );
      } else {
        // 圆形区域交通态势
        var lng = (params['lng'] as num?)?.toDouble();
        var lat = (params['lat'] as num?)?.toDouble();
        if (lng == null || lat == null) {
          try {
            final loc = await LocationClient().getCurrentPosition();
            lng = (loc['longitude'] as num?)?.toDouble();
            lat = (loc['latitude'] as num?)?.toDouble();
          } catch (_) {}
          if (lng == null || lat == null) {
            return const ToolResult(toolName: 'get_traffic_status', success: false, output: '', error: '缺少坐标参数，且无法获取当前设备位置');
          }
        }
        final radius = params['radius'] as int? ?? 1000;
        status = await client.getTrafficStatus(
          GeoPoint(lng, lat),
          radius: radius,
          level: level,
          allExtensions: allExtensions,
        );
      }

      if (status == null) {
        return const ToolResult(toolName: 'get_traffic_status', success: true, output: '未获取到该位置的交通态势数据。');
      }

      final emoji = {'0': '❓', '1': '🟢', '2': '🟡', '3': '🟠', '4': '🔴'};
      final labels = {'0': '未知', '1': '畅通', '2': '缓行', '3': '拥堵', '4': '严重拥堵'};
      final buf = StringBuffer();
      buf.writeln('🚥 交通态势:');
      buf.writeln('  ${emoji[status.status] ?? "❓"} ${labels[status.status] ?? status.description}');
      buf.writeln('  ${status.description}');
      if (status.expedite != null) {
        buf.writeln('  📊 畅通 ${status.expedite!.toStringAsFixed(1)}% | 缓行 ${status.congested?.toStringAsFixed(1) ?? "0"}% | 拥堵 ${status.blocked?.toStringAsFixed(1) ?? "0"}%');
      }
      if (status.roads != null && status.roads!.isNotEmpty) {
        buf.writeln('  道路详情 (${status.roads!.length}条):');
        for (final r in status.roads!) {
          buf.writeln('  • ${r.name} [${labels[r.status] ?? r.status}] ${r.speed}km/h ${r.direction}');
        }
      }

      // 收集道路列表用于地图渲染
      final roadItems = <TrafficRoadItem>[];
      if (status.roads != null && status.roads!.isNotEmpty) {
        for (final r in status.roads!) {
          roadItems.add(TrafficRoadItem(
            name: r.name,
            status: r.status,
            direction: r.direction,
            speed: r.speed,
            polyline: r.polyline,
          ));
        }
      }

      // 推送地图交通态势
      if (roadItems.isNotEmpty) {
        final trafficAction = ShowTrafficRoadsAction(
          type: type,
          status: status.status,
          description: status.description,
          expedite: status.expedite,
          congested: status.congested,
          blocked: status.blocked,
          roads: roadItems,
        );
        mapActionBus.value = trafficAction;
        addToHistory(trafficAction);
        mapActionPending.value = trafficAction;
      }

      return ToolResult(toolName: 'get_traffic_status', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'get_traffic_status', success: false, output: '', error: '路况查询失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'get_traffic_status', success: false, output: '', error: '路况查询失败: $e');
    }
  }

  // ── 未来路径规划 (高级/企业) ──
  Future<ToolResult> _amapFutureRoute(Map<String, dynamic> params) async {
    try {
      final oLng = (params['origin_lng'] as num?)?.toDouble();
      final oLat = (params['origin_lat'] as num?)?.toDouble();
      final dLng = (params['dest_lng'] as num?)?.toDouble();
      final dLat = (params['dest_lat'] as num?)?.toDouble();
      if (oLng == null || oLat == null || dLng == null || dLat == null) {
        return const ToolResult(toolName: 'future_route', success: false, output: '', error: '缺少起终点坐标参数');
      }
      final firstTime = params['first_time'] as int?;
      if (firstTime == null) {
        return const ToolResult(toolName: 'future_route', success: false, output: '', error: '缺少 first_time 参数（Unix时间戳秒）');
      }
      final interval = params['interval'] as int? ?? 60;
      final count = params['count'] as int? ?? 10;

      final client = await _getAmapClient();
      final result = await client.getFutureRoute(
        origin: GeoPoint(oLng, oLat),
        destination: GeoPoint(dLng, dLat),
        firstTime: firstTime,
        interval: interval,
        count: count > 48 ? 48 : (count < 1 ? 1 : count),
        strategy: params['strategy'] as int? ?? 1,
        province: params['province'] as String?,
        number: params['number'] as String?,
        carType: params['car_type'] as int? ?? 0,
      );

      if (result.paths.isEmpty) {
        return ToolResult(toolName: 'future_route', success: true, output: '未找到符合条件的路线。');
      }

      final buf = StringBuffer();
      buf.writeln('🚗 未来路径规划 (${result.paths.length}条路线):');
      for (int i = 0; i < result.paths.length; i++) {
        final path = result.paths[i];
        buf.writeln('路线${i + 1}: ${(path.distance / 1000).toStringAsFixed(2)}公里 红绿灯${path.trafficLights}个');
        if (path.steps.isNotEmpty) {
          buf.writeln('  首段: ${path.steps.first.road} ${path.steps.first.distance}米');
        }
        // 显示第一个时间段的预览
        if (path.steps.isNotEmpty && path.steps.first.timeInfos != null && path.steps.first.timeInfos!.isNotEmpty) {
          final ti = path.steps.first.timeInfos!.first;
          if (ti.elements.isNotEmpty) {
            final el = ti.elements.first;
            buf.writeln('  出发 ${ti.starttime}: 预计${el.duration}分钟 收费${el.tolls}元 ${el.restriction == 0 ? "不限行" : "⚠️限行"}');
          }
        }
      }
      buf.writeln('\n💡 提示：此接口为企业高级服务，请确保已申请相应权限。');

      // 推送地图未来路线（取第一时间段的路线）
      final pathItems = <FutureRoutePathItem>[];
      for (int i = 0; i < result.paths.length; i++) {
        final path = result.paths[i];
        String depTime = '';
        int duration = 0;
        double tolls = 0;
        int restriction = 0;
        String? polyline;

        // 从第一时间信息获取
        for (final step in path.steps) {
          if (step.timeInfos != null && step.timeInfos!.isNotEmpty) {
            final ti = step.timeInfos!.first;
            depTime = ti.starttime;
            if (ti.elements.isNotEmpty) {
              final el = ti.elements.first;
              duration = el.duration;
              tolls = el.tolls;
              restriction = el.restriction;
            }
            break;
          }
        }

        // 合并所有 step 的 polyline
        if (path.steps.isNotEmpty) {
          final parts = <String>[];
          for (final s in path.steps) {
            if (s.polyline != null && s.polyline!.isNotEmpty) parts.add(s.polyline!);
          }
          if (parts.isNotEmpty) polyline = parts.join(';');
        }

        pathItems.add(FutureRoutePathItem(
          departureTime: depTime,
          duration: duration,
          tolls: tolls,
          restriction: restriction,
          polyline: polyline,
        ));
      }

      final futureAction = ShowFutureRouteAction(
        origin: GeoPoint(oLng, oLat),
        destination: GeoPoint(dLng, dLat),
        paths: pathItems,
      );
      mapActionBus.value = futureAction;
      addToHistory(futureAction);
      mapActionPending.value = futureAction;

      return ToolResult(toolName: 'future_route', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'future_route', success: false, output: '', error: '未来路径规划失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'future_route', success: false, output: '', error: '未来路径规划失败: $e');
    }
  }

  // ── 行政区划 ──
  Future<ToolResult> _amapDistrictInfo(Map<String, dynamic> params) async {
    try {
      final keywords = params['keywords'] as String?;
      if (keywords == null || keywords.isEmpty) {
        return const ToolResult(toolName: 'get_district_info', success: false, output: '', error: '缺少 keywords 参数');
      }
      final subdistrict = params['subdistrict'] as int? ?? 0;
      final client = await _getAmapClient();
      final districts = await client.getDistricts(keywords, subdistrict: subdistrict);

      if (districts.isEmpty) {
        return ToolResult(toolName: 'get_district_info', success: true, output: '未找到 "$keywords" 的行政区划信息。');
      }

      final buf = StringBuffer();
      for (final d in districts) {
        buf.writeln('${d.name} (${d.level})');
        buf.writeln('  adcode: ${d.adcode}');
        if (d.center != null) buf.writeln('  中心坐标: ${d.center!.lng}, ${d.center!.lat}');
        if (d.children != null && d.children!.isNotEmpty) {
          for (final c in d.children!) {
            buf.writeln('  ├─ ${c.name} (adcode: ${c.adcode})');
            if (c.center != null) buf.writeln('  │  中心: ${c.center!.lng}, ${c.center!.lat}');
          }
        }
      }
      return ToolResult(toolName: 'get_district_info', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'get_district_info', success: false, output: '', error: '行政区划查询失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'get_district_info', success: false, output: '', error: '行政区划查询失败: $e');
    }
  }

  // ── 交通事件查询 ──
  Future<ToolResult> _amapTrafficEvents(Map<String, dynamic> params) async {
    try {
      final adcode = params['adcode'] as String?;
      if (adcode == null || adcode.isEmpty) {
        return const ToolResult(toolName: 'get_traffic_events', success: false, output: '', error: '缺少 adcode 参数');
      }
      final client = await _getAmapClient();
      final events = await client.getTrafficEvents(
        adcode: adcode,
        clientKey: params['client_key'] as String?,
        eventType: params['event_type'] as String?,
        isExpressway: params['is_expressway'] as bool? ?? false,
      );

      if (events.isEmpty) {
        return ToolResult(toolName: 'get_traffic_events', success: true, output: '该区域暂无交通事件。');
      }

      final buf = StringBuffer();
      buf.writeln('🚧 交通事件 (${adcode}) 共${events.length}条:');
      final eventItems = <TrafficEventItem>[];
      for (final e in events) {
        buf.writeln('• ${e.eventType}: ${e.description}');
        buf.writeln('  路段: ${e.roadName} ${e.direction}');
        if (e.delayTime != null) buf.writeln('  预计延时: ${e.delayTime}');
        if (e.startTime.isNotEmpty) buf.writeln('  时间: ${e.startTime} ~ ${e.endTime}');
        if (e.lat != null && e.lng != null) buf.writeln('  坐标: ${e.lng}, ${e.lat}');
        buf.writeln();
        if (e.lat != null && e.lng != null) {
          eventItems.add(TrafficEventItem(
            id: e.id,
            eventType: e.eventType,
            description: e.description,
            roadName: e.roadName,
            direction: e.direction,
            location: GeoPoint(e.lng!, e.lat!),
          ));
        }
      }

      // 推送地图标注
      if (eventItems.isNotEmpty) {
        final trafficEventsAction = ShowTrafficEventsAction(adcode: adcode, events: eventItems);
        mapActionBus.value = trafficEventsAction;
        addToHistory(trafficEventsAction);
        mapActionPending.value = trafficEventsAction;
      }

      return ToolResult(toolName: 'get_traffic_events', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'get_traffic_events', success: false, output: '', error: '交通事件查询失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'get_traffic_events', success: false, output: '', error: '交通事件查询失败: $e');
    }
  }

  // ── 轨迹纠偏 ──
  Future<ToolResult> _amapGrasproad(Map<String, dynamic> params) async {
    try {
      final pointsRaw = params['points'] as List<dynamic>?;
      if (pointsRaw == null || pointsRaw.isEmpty) {
        return const ToolResult(toolName: 'grasproad', success: false, output: '', error: '缺少 points 参数');
      }
      final points = pointsRaw.map((p) {
        return GrasproadPoint(
          lng: (p['lng'] as num).toDouble(),
          lat: (p['lat'] as num).toDouble(),
          speed: (p['speed'] as num).toDouble(),
          angle: (p['angle'] as num).toDouble(),
          timestamp: (p['timestamp'] as num).toInt(),
        );
      }).toList();

      final client = await _getAmapClient();
      final result = await client.grasproad(points);

      if (result.errcode != null && result.errcode != 0) {
        return ToolResult(toolName: 'grasproad', success: false, output: '',
            error: '轨迹纠偏失败: ${result.errmsg ?? "errcode=${result.errcode}"}');
      }

      final buf = StringBuffer();
      buf.writeln('🛣️ 轨迹纠偏结果:');
      buf.writeln('  纠偏后总距离: ${(result.distance / 1000).toStringAsFixed(2)} 公里');
      buf.writeln('  坐标点数: ${result.points.length}');
      if (result.points.isNotEmpty) {
        buf.writeln('  起点: ${result.points.first.lng.toStringAsFixed(6)}, ${result.points.first.lat.toStringAsFixed(6)}');
        buf.writeln('  终点: ${result.points.last.lng.toStringAsFixed(6)}, ${result.points.last.lat.toStringAsFixed(6)}');
      }

      // 推送地图轨迹纠偏结果
      final grasproadAction = ShowGrasproadAction(distance: result.distance, points: result.points);
      mapActionBus.value = grasproadAction;
      addToHistory(grasproadAction);
      mapActionPending.value = grasproadAction;

      return ToolResult(toolName: 'grasproad', success: true, output: buf.toString());
    } on AmapException catch (e) {
      return ToolResult(toolName: 'grasproad', success: false, output: '', error: '轨迹纠偏失败: $e');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'grasproad', success: false, output: '', error: '轨迹纠偏失败: $e');
    }
  }

  // ── 静态地图 ──
  Future<ToolResult> _staticMap(Map<String, dynamic> params) async {
    final lng = (params['lng'] as num?)?.toDouble();
    final lat = (params['lat'] as num?)?.toDouble();
    if (lng == null || lat == null) {
      return ToolResult(toolName: 'static_map', success: false, output: '', error: '缺少 lng/lat 参数');
    }
    try {
      final repo = SettingsRepository();
      final key = await repo.getAmapApiKey();
      if (key.isEmpty) return ToolResult(toolName: 'static_map', success: false, output: '', error: '请先配置高德 API Key');
      final client = AmapClient(apiKey: key);

      // 解析标注 markers
      List<StaticMapMarker>? markers;
      if (params['markers'] != null) {
        markers = (params['markers'] as List<dynamic>).map((m) {
          final points = (m['points'] as List<dynamic>).map((p) => GeoPoint(
            (p['lng'] as num).toDouble(),
            (p['lat'] as num).toDouble(),
          )).toList();
          return StaticMapMarker(
            size: m['size'] as String? ?? 'mid',
            color: m['color'] != null ? (m['color'] as num).toInt() : null,
            label: m['label'] as String?,
            iconUrl: m['iconUrl'] as String?,
            points: points,
          );
        }).toList();
      }

      // 解析文字标签 labels
      List<StaticMapLabel>? labels;
      if (params['labels'] != null) {
        labels = (params['labels'] as List<dynamic>).map((l) {
          final points = (l['points'] as List<dynamic>).map((p) => GeoPoint(
            (p['lng'] as num).toDouble(),
            (p['lat'] as num).toDouble(),
          )).toList();
          return StaticMapLabel(
            content: l['content'] as String,
            font: l['font'] as int? ?? 0,
            bold: l['bold'] as bool? ?? false,
            fontSize: l['fontSize'] as int? ?? 10,
            fontColor: l['fontColor'] != null ? (l['fontColor'] as num).toInt() : 0xFFFFFF,
            background: l['background'] != null ? (l['background'] as num).toInt() : 0x5288d8,
            points: points,
          );
        }).toList();
      }

      // 解析折线/多边形 paths
      List<StaticMapPath>? paths;
      if (params['paths'] != null) {
        paths = (params['paths'] as List<dynamic>).map((p) {
          final points = (p['points'] as List<dynamic>).map((pt) => GeoPoint(
            (pt['lng'] as num).toDouble(),
            (pt['lat'] as num).toDouble(),
          )).toList();
          return StaticMapPath(
            weight: p['weight'] as int? ?? 5,
            color: p['color'] != null ? (p['color'] as num).toInt() : 0x0000FF,
            transparency: p['transparency'] != null ? (p['transparency'] as num).toDouble() : 1.0,
            fillColor: p['fillColor'] != null ? (p['fillColor'] as num).toInt() : null,
            fillTransparency: p['fillTransparency'] != null ? (p['fillTransparency'] as num).toDouble() : 0.5,
            points: points,
          );
        }).toList();
      }

      final url = client.staticMapUrl(
        center: GeoPoint(lng, lat),
        zoom: (params['zoom'] as num?)?.toInt() ?? 14,
        width: (params['width'] as num?)?.toInt() ?? 600,
        height: (params['height'] as num?)?.toInt() ?? 400,
        scale: (params['scale'] as num?)?.toInt() ?? 1,
        traffic: params['traffic'] == true,
        markers: markers,
        labels: labels,
        paths: paths,
      );
      return ToolResult(toolName: 'static_map', success: true, output: '![]($url)\n\n静态地图已生成，可复制链接查看。');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'static_map', success: false, output: '', error: '静态地图生成失败: $e');
    }
  }

  // ── 距离计算 ──
  Future<ToolResult> _distanceCalc(Map<String, dynamic> params) async {
    final oLng = (params['origin_lng'] as num?)?.toDouble();
    final oLat = (params['origin_lat'] as num?)?.toDouble();
    final dLng = (params['dest_lng'] as num?)?.toDouble();
    final dLat = (params['dest_lat'] as num?)?.toDouble();
    if (oLng == null || oLat == null || dLng == null || dLat == null) {
      return ToolResult(toolName: 'distance_calc', success: false, output: '', error: '缺少起终点坐标');
    }
    // Haversine formula
    const r = 6371000.0;
    final dLatRad = (dLat - oLat) * pi / 180.0;
    final dLngRad = (dLng - oLng) * pi / 180.0;
    final a = sin(dLatRad / 2) * sin(dLatRad / 2) +
        cos(oLat * pi / 180.0) * cos(dLat * pi / 180.0) *
            sin(dLngRad / 2) * sin(dLngRad / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distance = r * c;
    final km = (distance / 1000).toStringAsFixed(2);
    return ToolResult(toolName: 'distance_calc', success: true,
        output: '两点直线距离: ${distance.toInt()} 米 (约 $km 公里)');
  }

  // ── 地图截图 ──
  Future<ToolResult> _mapScreenshotTool(Map<String, dynamic> params) async {
    // 触发 MapPage 执行截图
    _ref?.read(mapScreenshotRequestProvider.notifier).state =
        DateTime.now().millisecondsSinceEpoch.toString();

    // 等待截图结果（MapPage 会通过 onScreenshotComplete 回调传入路径）
    // 使用 Completer 将同步回调转换为异步 Future
    final completer = Completer<String?>();
    String? pendingResult;
    onScreenshotComplete = (result) {
      pendingResult = result;
      if (!completer.isCompleted) completer.complete(result);
    };
    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => pendingResult,
      );
      if (result != null && result.isNotEmpty) {
        return ToolResult(
          toolName: 'map_screenshot',
          success: true,
          output: '地图截图已保存: $result',
        );
      }
      return ToolResult(
        toolName: 'map_screenshot',
        success: true,
        output: '截图已完成，请在地图页面查看。',
      );
    } finally {
      onScreenshotComplete = null;
    }
  }

  // ── 地图截图缓存上限 ──
  Future<ToolResult> _setMapCacheLimit(Map<String, dynamic> params) async {
    final limit = (params['limit'] as num?)?.toInt() ?? 3;
    final clamped = limit.clamp(0, 50);
    _ref?.read(mapCacheLimitProvider.notifier).state = clamped;
    return ToolResult(
      toolName: 'set_map_cache_limit',
      success: true,
      output: '地图截图缓存上限已设置为 $clamped 张。',
    );
  }

  // ── 坐标转换 ──
  Future<ToolResult> _coordinateConverter(Map<String, dynamic> params) async {
    final lng = (params['lng'] as num?)?.toDouble();
    final lat = (params['lat'] as num?)?.toDouble();
    final type = params['type'] as String? ?? 'gps2gcj';
    if (lng == null || lat == null) {
      return ToolResult(toolName: 'coordinate_converter', success: false, output: '', error: '缺少 lng/lat 参数');
    }
    double outLng, outLat;
    if (type == 'gps2gcj') {
      final r = _wgs84ToGcj02(lng, lat);
      outLng = r.$1; outLat = r.$2;
    } else {
      final r = _gcj02ToWgs84(lng, lat);
      outLng = r.$1; outLat = r.$2;
    }
    return ToolResult(toolName: 'coordinate_converter', success: true,
        output: '坐标转换 ($type):\n- 原始: $lng, $lat\n- 结果: $outLng, $outLat');
  }

  // GCJ-02 ↔ WGS-84 conversion
  static (double, double) _wgs84ToGcj02(double lng, double lat) {
    const pi = 3.141592653589793;
    const a = 6378245.0;
    const ee = 0.00669342162296594323;
    double dLat = _transformLat(lng - 105.0, lat - 35.0);
    double dLng = _transformLng(lng - 105.0, lat - 35.0);
    double radLat = lat / 180.0 * pi;
    double magic = sin(radLat);
    magic = 1 - ee * magic * magic;
    double sqrtMagic = sqrt(magic);
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi);
    dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * pi);
    return (lng + dLng, lat + dLat);
  }

  static (double, double) _gcj02ToWgs84(double lng, double lat) {
    final gcj = _wgs84ToGcj02(lng, lat);
    return (lng * 2 - gcj.$1, lat * 2 - gcj.$2);
  }

  static double _transformLat(double x, double y) {
    const pi = 3.141592653589793;
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    const pi = 3.141592653589793;
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }

  // ── 地图 Agent：智能编排 ──
  Future<ToolResult> _runMapAgent(Map<String, dynamic> params, PauseToken? pauseToken) async {
    final task = params['task'] as String?;
    if (task == null || task.isEmpty) {
      return const ToolResult(toolName: 'map_agent', success: false, output: '', error: '缺少 task 参数');
    }

    await _ensureMinimaxClient();
    if (_minimaxClient == null) {
      return const ToolResult(
        toolName: 'map_agent',
        success: false,
        output: '',
        error: 'API 客户端未就绪',
      );
    }

    final agent = MapAgent(
      client: _minimaxClient!,
      dispatch: (toolName, p) => _dispatchMapTool(toolName, p),
    );

    try {
      final result = await agent.execute(task: task, pauseToken: pauseToken);

      final buf = StringBuffer();
      buf.writeln(result.summary);

      if (result.data != null && result.data!.isNotEmpty) {
        buf.writeln('\n## Extracted Data');
        try {
          buf.writeln(const JsonEncoder.withIndent('  ').convert(result.data));
        } catch (_) {
          buf.writeln(result.data.toString());
        }
      }

      buf.writeln('\n---');
      buf.writeln('Present this result directly to the user without further analysis or tool calls.');

      return ToolResult(
        toolName: 'map_agent',
        success: result.success,
        output: buf.toString(),
      );
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'map_agent',
        success: false,
        output: '',
        error: 'Map Agent 执行失败: $e',
      );
    }
  }

  Future<ToolResult> _dispatchMapTool(String name, Map<String, dynamic> params) async {
    switch (name) {
      case 'geocode': return _amapGeocode(params);
      case 'regeocode': return _amapRegeocode(params);
      case 'search_places': return _amapSearchPlaces(params);
      case 'search_nearby': return _amapSearchNearby(params);
      case 'plan_driving_route': return _amapDrivingRoute(params);
      case 'plan_transit_route': return _amapTransitRoute(params);
      case 'plan_walking_route': return _amapWalkingRoute(params);
      case 'plan_cycling_route': return _amapCyclingRoute(params);
      case 'plan_electrobike_route': return _amapElectrobikeRoute(params);
      case 'get_bus_arrival': return _amapBusArrival(params);
      case 'get_traffic_status': return _amapTrafficStatus(params);
      case 'get_traffic_events': return _amapTrafficEvents(params);
      case 'get_district_info': return _amapDistrictInfo(params);
      case 'location_get': return _locationGet(params);
      case 'static_map': return _staticMap(params);
      case 'distance_calc': return _distanceCalc(params);
      case 'map_screenshot': return _mapScreenshotTool(params);
      case 'coordinate_converter': return _coordinateConverter(params);
      case 'poi_detail': return _amapPoiDetail(params);
      case 'bus_stop_by_id': return _amapBusStopById(params);
      case 'search_bus_stop': return _amapSearchBusStop(params);
      case 'bus_line_by_id': return _amapBusLineById(params);
      case 'search_bus_line': return _amapSearchBusLine(params);
      case 'grasproad': return _amapGrasproad(params);
      case 'future_route': return _amapFutureRoute(params);
      default:
        return ToolResult(
          toolName: name,
          success: false,
          output: '',
          error: 'MapAgent 未知工具: $name',
        );
    }
  }

  Future<ToolResult> _runWebAgent(Map<String, dynamic> params, PauseToken? pauseToken) async {
    final backend = _browserBackend ?? _browserToolHandler;
    if (backend == null) {
      return const ToolResult(
        toolName: 'web_agent',
        success: false,
        output: '',
        error: '浏览器未初始化。请先打开浏览器标签页。',
      );
    }

    final task = params['task'] as String?;
    if (task == null || task.isEmpty) {
      return const ToolResult(
        toolName: 'web_agent',
        success: false,
        output: '',
        error: '缺少 task 参数',
      );
    }

    await _ensureMinimaxClient();
    if (_minimaxClient == null) {
      return const ToolResult(
        toolName: 'web_agent',
        success: false,
        output: '',
        error: 'API 客户端未就绪',
      );
    }

    final agent = WebAgent(
      client: _minimaxClient!,
      backend: backend,
    );

    try {
      final result = await agent.execute(
        task: task,
        startUrl: params['startUrl'] as String?,
        pauseToken: pauseToken,
      );

      // 只返回摘要 + 关键数据给主 Agent，避免二次分析产生大量思考。
      // 执行轨迹和 judge 评估仅写日志，不塞进输出。
      final buf = StringBuffer();
      buf.writeln(result.summary);

      if (result.data != null && result.data!.isNotEmpty) {
        buf.writeln('\n## Extracted Data');
        try {
          buf.writeln(const JsonEncoder.withIndent('  ').convert(result.data));
        } catch (_) {
          buf.writeln(result.data.toString());
        }
      }

      // 在最后加一句，让主 Agent 直接把结果呈现给用户
      buf.writeln('\n---');
      buf.writeln('Present this result directly to the user without further analysis or tool calls.');

      return ToolResult(
        toolName: 'web_agent',
        success: result.success,
        output: buf.toString(),
      );
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'web_agent',
        success: false,
        output: '',
        error: 'Web Agent 执行失败: $e',
      );
    }
  }

  // ─── 页面生成工具 ──────────────────────────────────

  Future<ToolResult> _generatePage(Map<String, dynamic> params) async {
    await _ensureMinimaxClient();
    if (_minimaxClient == null) {
      return const ToolResult(
        toolName: 'generate_page',
        success: false,
        output: '',
        error: 'API 客户端未就绪',
      );
    }

    final extraction = params['extraction'] as String?;
    final requirements = (params['requirements'] ?? params['description']) as String?;
    final freestyle = params['freestyle'] as bool? ?? false;

    if (requirements == null || requirements.isEmpty) {
      return const ToolResult(
        toolName: 'generate_page',
        success: false,
        output: '',
        error: '缺少 requirements 参数 (描述你想生成什么页面)',
      );
    }

    try {
      final generator = PageGenerator(_minimaxClient!);
      final multiVariant = params['multiVariant'] as bool? ?? false;
      final skipRefine = params['skipRefine'] as bool? ?? false;
      final compact = params['compact'] as bool? ?? false;

      // Auto-detect: simple request → compact mode (fast, cheap)
      final useCompact = compact ||
          (DesignAnalyzer.isSimpleRequest(requirements) &&
              extraction == null &&
              !multiVariant);

      GeneratedPage page;

      if (useCompact) {
        // Fast path: lightweight prompt for simple components
        final design = MatchedDesign(
          style: params['style'] as String? ?? 'vega',
          baseColor: params['baseColor'] as String? ?? 'neutral',
          accentTheme: params['accentTheme'] as String?,
          font: params['font'] as String? ?? 'inter',
        );
        page = await generator.generateCompact(
          userRequirements: requirements,
          design: design,
        );
      } else if (multiVariant) {
        // Multi-variant mode: generate 3 variants + auto-select best
        final variantResult = await generator.generateMultiVariant(
          userRequirements: requirements,
          extractionJson: extraction,
          style: params['style'] as String?,
          baseColor: params['baseColor'] as String?,
          accentTheme: params['accentTheme'] as String?,
          font: params['font'] as String?,
        );
        page = variantResult.best;
      } else if (freestyle) {
        page = await generator.generateFreestyle(requirements);
      } else {
        page = await generator.generate(
          userRequirements: requirements,
          extractionJson: extraction,
          contentText: params['contentText'] as String?,
          style: params['style'] as String?,
          baseColor: params['baseColor'] as String?,
          accentTheme: params['accentTheme'] as String?,
          font: params['font'] as String?,
        );
      }

      if (page.html.isEmpty) {
        final detail = page.error ?? page.summary;
        debugPrint('[generate_page] FAILED: $detail');
        debugPrint('[generate_page] params: freestyle=$freestyle, compact=$useCompact, multiVariant=$multiVariant');
        return ToolResult(
          toolName: 'generate_page',
          success: false,
          output: '',
          error: '页面生成失败 — $detail',
        );
      }

      // ── Auto-critique + refine ──
      GeneratedPage finalPage = page;
      if (!skipRefine && !multiVariant) {
        // Single refine pass (multi-variant already picked the best of 3)
        finalPage = await generator.critiqueAndRefine(page, maxIterations: 1);
      }

      // ── Persist design system ──
      DesignSystemState.instance.commit(finalPage.design);
      try {
        final ws = await _getWorkspace();
        if (ws.path.isNotEmpty) {
          await DesignSystemState.instance.saveToFile(ws.path);
        }
      } catch (_) {
        // File save failure is non-fatal
      }

      final buf = StringBuffer();
      buf.writeln(finalPage.summary);
      if (finalPage.iterations > 1) {
        buf.writeln('(经过 ${finalPage.iterations} 轮打磨)');
      }
      buf.writeln();
      buf.writeln('--- 生成完成 ---');
      buf.writeln('Design: ${finalPage.design.stylePreset.title} / ${finalPage.design.baseColor}'
          '${finalPage.design.accentTheme != null ? ' + ${finalPage.design.accentTheme}' : ''}'
          ' / ${finalPage.design.font}');
      buf.writeln('Click the preview button below the HTML to view this page in the browser.');
      if (multiVariant) {
        buf.writeln('(多方案对比模式 — 已自动选择最佳方案)');
      }
      buf.writeln();
      buf.writeln('--- HTML ---');
      buf.write(finalPage.html);

      return ToolResult(
        toolName: 'generate_page',
        success: true,
        output: buf.toString(),
      );
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'generate_page',
        success: false,
        output: '',
        error: '页面生成异常: $e',
      );
    }
  }

  // ─── 时间工具 ──────────────────────────────────────

  Future<ToolResult> _getCurrentTime(Map<String, dynamic> params) async {
    try {
      final tz = (params['timezone'] as String?)?.isNotEmpty == true
          ? params['timezone'] as String
          : null;

      // Try the external API first; if it's down, fall back to device time.
      String? apiTime;
      try {
        final client = WorldTimeClient();
        final data = await client.query(tz ?? DateTime.now().timeZoneName);
        apiTime = 'Timezone / 时区: ${data['timezone']}\n'
            'Datetime / 时间: ${data['datetime']}\n'
            'Weekday / 星期: ${data['weekday']}\n'
            'UTC offset / UTC偏移: ${data['offset_string']}';
      } catch (_) {}

      final now = DateTime.now();
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final localOffset = now.timeZoneOffset;
      final sign = localOffset.isNegative ? '-' : '+';
      final hours = localOffset.inHours.abs().toString().padLeft(2, '0');
      final mins = (localOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');

      final out = StringBuffer();
      if (apiTime != null) {
        out.writeln(apiTime);
      } else {
        out.writeln('Timezone / 时区: ${now.timeZoneName}');
        out.writeln('Datetime / 时间: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}');
        out.writeln('Weekday / 星期: ${weekdays[now.weekday - 1]}');
        out.writeln('UTC offset / UTC偏移: UTC$sign$hours:$mins');
      }
      out.writeln('Unix: ${now.millisecondsSinceEpoch ~/ 1000}');

      return ToolResult(toolName: 'getCurrentTime', success: true, output: out.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'getCurrentTime', success: false, output: '', error: 'Time query failed: $e / 时间查询失败: $e');
    }
  }

  // ─── 手机原生能力执行方法 ──────────────────────────

  Future<ToolResult> _contactsSearch(Map<String, dynamic> params) async {
    try {
      final client = ContactsClient();
      final results = await client.search(params['query'] as String? ?? '');
      if (results.isEmpty) return const ToolResult(toolName: 'contacts_search', success: true, output: 'No matching contacts found / 未找到匹配的联系人');
      final buf = StringBuffer();
      for (final c in results) {
        buf.writeln('${c['contactId']} | ${c['displayName']}${c['hasPhoneNumber'] == true ? ' [has phone]' : ''}');
      }
      return ToolResult(toolName: 'contacts_search', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'contacts_search', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _contactsGet(Map<String, dynamic> params) async {
    try {
      final contactId = params['contactId'] as String?;
      if (contactId == null || contactId.isEmpty) return const ToolResult(toolName: 'contacts_get', success: false, output: '', error: 'Missing contactId / 缺少 contactId');
      final client = ContactsClient();
      final contact = await client.getById(contactId);
      if (contact == null) return const ToolResult(toolName: 'contacts_get', success: false, output: '', error: 'Contact not found / 联系人不存在');
      final buf = StringBuffer();
      buf.writeln('Name / 姓名: ${contact['displayName']}');
      final phones = _safeList(contact, 'phones');
      for (final m in phones) {
        buf.writeln('Phone / 电话 [${m['type']}]: ${m['number']}');
      }
      final emails = _safeList(contact, 'emails');
      for (final m in emails) {
        buf.writeln('Email / 邮箱 [${m['type']}]: ${m['address']}');
      }
      if (contact['organization'] is String && (contact['organization'] as String).isNotEmpty) {
        buf.writeln('Organization / 组织: ${contact['organization']}');
      }
      return ToolResult(toolName: 'contacts_get', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'contacts_get', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _contactsCreate(Map<String, dynamic> params) async {
    try {
      final givenName = params['givenName'] as String?;
      if (givenName == null || givenName.isEmpty) return const ToolResult(toolName: 'contacts_create', success: false, output: '', error: 'Missing givenName / 缺少 givenName');
      final client = ContactsClient();
      final result = await client.createContact(
        givenName: givenName,
        familyName: params['familyName'] as String?,
        phone: params['phone'] as String?,
        email: params['email'] as String?,
      );
      return ToolResult(toolName: 'contacts_create', success: true, output: result);
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'contacts_create', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _contactsDelete(Map<String, dynamic> params) async {
    try {
      final contactId = params['contactId'] as String?;
      if (contactId == null || contactId.isEmpty) return const ToolResult(toolName: 'contacts_delete', success: false, output: '', error: 'Missing contactId / 缺少 contactId');
      final client = ContactsClient();
      final result = await client.deleteContact(contactId);
      return ToolResult(toolName: 'contacts_delete', success: true, output: result);
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'contacts_delete', success: false, output: '', error: e.toString());
    }
  }

  int _isoDateToMs(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return DateTime.now().millisecondsSinceEpoch;
    try {
      final cleaned = dateStr.trim().replaceAll('T', ' ').replaceAll('Z', '');
      if (cleaned.length == 10) return DateTime.parse('${cleaned}T00:00:00').millisecondsSinceEpoch;
      return DateTime.parse(cleaned).millisecondsSinceEpoch;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<ToolResult> _calendarQuery(Map<String, dynamic> params) async {
    try {
      final client = CalendarClient();
      final startMs = _isoDateToMs(params['startDate'] as String? ?? '');
      final endMs = _isoDateToMs(params['endDate'] as String? ?? '');
      final events = await client.queryEvents(startMs: startMs, endMs: endMs);
      if (events.isEmpty) return const ToolResult(toolName: 'calendar_query', success: true, output: 'No calendar events in this time range / 该时间范围内无日历事件');
      final buf = StringBuffer();
      for (final ev in events) {
        final begin = DateTime.fromMillisecondsSinceEpoch(ev['beginMs'] as int);
        final end = DateTime.fromMillisecondsSinceEpoch(ev['endMs'] as int);
        final timeStr = '${begin.month}/${begin.day} ${begin.hour.toString().padLeft(2, '0')}:${begin.minute.toString().padLeft(2, '0')}'
            ' → ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
        buf.writeln('[${ev['eventId']}] $timeStr | ${ev['title']}');
        if (ev['location'] is String && (ev['location'] as String).isNotEmpty) {
          buf.writeln('  Location / 地点: ${ev['location']}');
        }
        if (ev['description'] is String && (ev['description'] as String).isNotEmpty) {
          buf.writeln('  ${ev['description']}');
        }
      }
      return ToolResult(toolName: 'calendar_query', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'calendar_query', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _calendarCreate(Map<String, dynamic> params) async {
    try {
      final title = params['title'] as String?;
      if (title == null || title.isEmpty) return const ToolResult(toolName: 'calendar_create', success: false, output: '', error: 'Missing title / 缺少 title');
      final client = CalendarClient();
      final startMs = _isoDateToMs(params['startDate'] as String?);
      final endMs = _isoDateToMs(params['endDate'] as String?);
      final result = await client.createEvent(
        title: title,
        description: params['description'] as String?,
        startMs: startMs,
        endMs: endMs,
      );
      return ToolResult(toolName: 'calendar_create', success: true, output: result['message'] ?? 'Event created / 事件已创建');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'calendar_create', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _calendarDelete(Map<String, dynamic> params) async {
    try {
      final client = CalendarClient();
      final eventId = params['eventId'] as String?;
      if (eventId == null || eventId.isEmpty) return const ToolResult(toolName: 'calendar_delete', success: false, output: '', error: 'Missing eventId / 缺少 eventId');
      final ok = await client.deleteEvent(eventId);
      return ToolResult(toolName: 'calendar_delete', success: ok, output: ok ? 'Deleted / 已删除' : '', error: ok ? null : 'Delete failed / 删除失败');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'calendar_delete', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _phoneCall(Map<String, dynamic> params) async {
    try {
      final client = PhoneClient();
      final phoneNumber = params['phoneNumber'] as String?;
      if (phoneNumber == null || phoneNumber.isEmpty) {
        return const ToolResult(toolName: 'phone_call', success: false, output: '', error: 'Missing phoneNumber param / 缺少 phoneNumber 参数');
      }
      await client.call(phoneNumber);
      return ToolResult(toolName: 'phone_call', success: true, output: '正在呼叫 $phoneNumber...');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'phone_call', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _phoneCallLog(Map<String, dynamic> params) async {
    try {
      final client = PhoneClient();
      final calls = await client.getCallLog(limit: params['limit'] as int? ?? 50);
      if (calls.isEmpty) return const ToolResult(toolName: 'phone_call_log', success: true, output: 'No call records / 无通话记录');
      final buf = StringBuffer();
      for (final c in calls) {
        final date = DateTime.fromMillisecondsSinceEpoch(c['date'] as int);
        final timeStr = '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        final typeIcon = c['type'] == 'incoming' ? '↓' : c['type'] == 'outgoing' ? '↑' : '✗';
        final name = c['name'] as String? ?? '';
        final number = c['number'] as String? ?? '';
        final label = name.isNotEmpty ? '$name ($number)' : number;
        final dur = c['duration'] as int? ?? 0;
        final durStr = dur > 0 ? ' ${dur}s' : '';
        buf.writeln('$typeIcon $timeStr | $label$durStr');
      }
      return ToolResult(toolName: 'phone_call_log', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'phone_call_log', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _locationGet(Map<String, dynamic> params) async {
    try {
      final client = LocationClient();
      final loc = await client.getCurrentPosition();
      if (loc.isEmpty) return const ToolResult(toolName: 'location_get', success: false, output: '', error: 'Unable to get location / 无法获取位置');

      final src = loc['source'] as String? ?? 'unknown';
      final buf = StringBuffer();
      buf.writeln('Latitude / 纬度: ${loc['latitude']}');
      buf.writeln('Longitude / 经度: ${loc['longitude']}');

      if (src == 'gps') {
        buf.writeln('Accuracy / 精度: ${loc['accuracy']}m');
        buf.writeln('Provider / 来源: ${loc['provider']} (GPS)');
      } else {
        final city = loc['city'] as String?;
        final region = loc['region'] as String?;
        final country = loc['country'] as String?;
        final place = [city, region, country].where((s) => s != null && s.isNotEmpty).join(', ');
        if (place.isNotEmpty) buf.writeln('Location / 位置: $place');
        buf.writeln('Source / 来源: IP-based estimation / IP定位估算');
      }

      return ToolResult(toolName: 'location_get', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'location_get', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _smsRead(Map<String, dynamic> params) async {
    try {
      final client = SmsClient();
      final messages = await client.readInbox(
        limit: params['limit'] as int? ?? 50,
        senderFilter: params['senderFilter'] as String?,
      );
      if (messages.isEmpty) return const ToolResult(toolName: 'sms_read', success: true, output: 'No messages / 无短信');
      final buf = StringBuffer();
      for (final m in messages) {
        final date = DateTime.fromMillisecondsSinceEpoch(m['date'] as int);
        final timeStr = '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        buf.writeln('[$timeStr] ${m['address']} (${m['type']}) [ID: ${m['smsId']}]');
        buf.writeln('  ${m['body']}');
        buf.writeln();
      }
      return ToolResult(toolName: 'sms_read', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'sms_read', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _smsSend(Map<String, dynamic> params) async {
    try {
      final client = SmsClient();
      final result = await client.sendSms(
        phoneNumber: params['phoneNumber'] as String? ?? '',
        message: params['message'] as String? ?? '',
      );
      return ToolResult(toolName: 'sms_send', success: true, output: result);
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'sms_send', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _smsDelete(Map<String, dynamic> params) async {
    try {
      final smsId = params['smsId'] as String?;
      if (smsId == null || smsId.isEmpty) return const ToolResult(toolName: 'sms_delete', success: false, output: '', error: 'Missing smsId / 缺少 smsId');
      final client = SmsClient();
      final result = await client.deleteSms(smsId);
      return ToolResult(toolName: 'sms_delete', success: true, output: result);
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'sms_delete', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _clipboardWrite(Map<String, dynamic> params) async {
    try {
      final text = params['text'] as String?;
      if (text == null || text.isEmpty) return const ToolResult(toolName: 'clipboard_write', success: false, output: '', error: 'Missing text / 缺少 text');
      await Clipboard.setData(ClipboardData(text: text));
      return const ToolResult(toolName: 'clipboard_write', success: true, output: '已复制到剪贴板');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'clipboard_write', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _overlayShow(Map<String, dynamic> params) async {
    try {
      final client = OverlayClient();
      final ok = await client.show(
        title: params['title'] as String?,
        text: params['text'] as String?,
      );
      return ToolResult(toolName: 'overlay_show', success: ok, output: ok ? 'Floating window shown / 悬浮窗已显示' : '',
          error: ok ? null : 'Floating window permission not granted / 悬浮窗权限未授予');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'overlay_show', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _overlayHide(Map<String, dynamic> params) async {
    try {
      final client = OverlayClient();
      await client.hide();
      return const ToolResult(toolName: 'overlay_hide', success: true, output: 'Floating window hidden / 悬浮窗已隐藏');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'overlay_hide', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _vibrate(Map<String, dynamic> params) async {
    try {
      final intensity = params['intensity'] as String? ?? 'light';
      switch (intensity) {
        case 'heavy':
          HapticFeedback.heavyImpact();
          break;
        case 'medium':
          HapticFeedback.mediumImpact();
          break;
        default:
          HapticFeedback.lightImpact();
      }
      return const ToolResult(toolName: 'vibrate', success: true, output: 'done');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'vibrate', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _taskSet(Map<String, dynamic> params) async {
    try {
      final title = params['title'] as String?;
      final taskPrompt = params['taskPrompt'] as String?;
      final repeatSeconds = params['repeatIntervalSeconds'] as int? ?? 0;
      if (title == null || title.isEmpty) {
        return const ToolResult(toolName: 'task_set', success: false, output: '', error: 'Missing title / 缺少 title');
      }
      if (taskPrompt == null || taskPrompt.isEmpty) {
        return const ToolResult(toolName: 'task_set', success: false, output: '', error: 'Missing taskPrompt / 缺少 AI 执行指令');
      }

      // 解析时间：仅接受 ISO 8601 格式
      final dueTimeStr = params['dueTime'] as String?;
      if (dueTimeStr == null || dueTimeStr.isEmpty) {
        return const ToolResult(toolName: 'task_set', success: false, output: '', error: 'Missing dueTime / 缺少执行时间（需 ISO 8601 格式）');
      }
      final dueTime = DateTime.tryParse(dueTimeStr);
      if (dueTime == null) {
        return ToolResult(toolName: 'task_set', success: false, output: '', error: 'Invalid dueTime: "$dueTimeStr" / 时间格式错误，需 ISO 8601 格式如 2026-05-15T08:00:00');
      }

      final taskType = repeatSeconds > 0 ? 'recurring' : 'scheduled';
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final timeoutSeconds = params['timeoutSeconds'] as int? ?? 60;
      final maxRetries = params['maxRetries'] as int? ?? 1;
      final taskRow = <String, dynamic>{
        'id': id,
        'title': title,
        'description': taskPrompt,  // description 字段存储 AI 执行指令
        'task_type': taskType,
        'interval_seconds': repeatSeconds,
        'due_time': dueTime.millisecondsSinceEpoch,
        'status': 'pending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'is_active': 1,
        'timeout_seconds': timeoutSeconds,
        'max_retries': maxRetries,
      };

      // 写入 MemoryCache，TaskScheduler 的 onChange 会自动重建闹钟
      await MemoryCache.instance.addTask(taskRow);

      String timeDesc;
      if (repeatSeconds > 0) {
        if (repeatSeconds >= 86400) {
          final days = repeatSeconds ~/ 86400;
          timeDesc = '每$days天';
        } else if (repeatSeconds >= 3600) {
          final hours = repeatSeconds ~/ 3600;
          timeDesc = '每$hours小时';
        } else {
          timeDesc = '每$repeatSeconds秒';
        }
      } else {
        timeDesc = '${dueTime.year}-${dueTime.month.toString().padLeft(2, '0')}-${dueTime.day.toString().padLeft(2, '0')} ${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}';
      }
      return ToolResult(toolName: 'task_set', success: true,
          output: 'AI 定时任务已设置: "$title"\n执行时间: $timeDesc\n超时: ${timeoutSeconds}秒\n重试: $maxRetries次\n任务内容: $taskPrompt');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'task_set', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _taskList(Map<String, dynamic> params) async {
    try {
      final statusFilter = params['status'] as String?;
      final cache = MemoryCache.instance;
      await cache.load();

      List<Map<String, dynamic>> tasks;
      if (statusFilter == 'completed') {
        tasks = cache.getTasks(status: 'completed');
      } else if (statusFilter == 'all') {
        tasks = cache.getTasks();
      } else {
        tasks = [
          ...cache.getTasks(status: 'pending'),
          ...cache.getTasks(status: 'inProgress'),
        ];
      }

      if (tasks.isEmpty) {
        final label = statusFilter == 'completed' ? '已完成任务' : '活跃任务';
        return ToolResult(toolName: 'task_list', success: true, output: '当前没有$label。');
      }

      final buf = StringBuffer();
      buf.writeln('共 ${tasks.length} 个任务：');
      for (final t in tasks) {
        Map<String, dynamic> value = {};
        final raw = t['value'];
        if (raw is String) {
          try { value = jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
        } else if (raw is Map<String, dynamic>) {
          value = raw;
        }

        final title = value['title'] ?? t['title'] ?? '(无标题)';
        final desc = value['description'] ?? '';
        final taskType = value['taskType'] ?? 'scheduled';
        final interval = value['intervalSeconds'] ?? 0;
        final dueTime = t['due_time'] as int?;

        final timeStr = dueTime != null
            ? DateTime.fromMillisecondsSinceEpoch(dueTime).toString().substring(0, 16)
            : '无时间';

        final typeLabel = taskType == 'recurring' ? '周期' : (taskType == 'countdown' ? '倒计时' : '定时');
        String extraStr = '';
        if (taskType == 'recurring' && interval is int && interval > 0) {
          if (interval < 60) {
            extraStr = '每$interval秒 ';
          } else if (interval < 3600) {
            extraStr = '每${interval ~/ 60}分钟 ';
          } else if (interval < 86400) {
            extraStr = '每${interval ~/ 3600}小时 ';
          } else {
            extraStr = '每${interval ~/ 86400}天 ';
          }
        }

        final statusLabel = t['status'] == 'pending' ? '待执行' :
            (t['status'] == 'completed' ? '已完成' :
            (t['status'] == 'expired' ? '已过期' : '进行中'));

        buf.writeln('- ${t['id']}: [$typeLabel$extraStr| $statusLabel] $title ($timeStr)');
        if (desc is String && desc.isNotEmpty) {
          buf.writeln('  说明: $desc');
        }
      }
      return ToolResult(toolName: 'task_list', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'task_list', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _taskDelete(Map<String, dynamic> params) async {
    try {
      final taskId = params['taskId'] as String?;
      if (taskId == null || taskId.isEmpty) {
        return const ToolResult(toolName: 'task_delete', success: false, output: '', error: '缺少 taskId 参数');
      }
      final cache = MemoryCache.instance;
      await cache.load();
      final existing = cache.getTask(taskId);
      if (existing == null) {
        return ToolResult(toolName: 'task_delete', success: false, output: '', error: '任务不存在: $taskId');
      }
      await cache.deleteTask(taskId);

      Map<String, dynamic> value = {};
      final raw = existing['value'];
      if (raw is String) {
        try { value = jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
      } else if (raw is Map<String, dynamic>) {
        value = raw;
      }
      final title = value['title'] ?? existing['title'] ?? taskId;
      return ToolResult(toolName: 'task_delete', success: true, output: '任务已删除: $title');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'task_delete', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _taskUpdate(Map<String, dynamic> params) async {
    try {
      final taskId = params['taskId'] as String?;
      if (taskId == null || taskId.isEmpty) {
        return const ToolResult(toolName: 'task_update', success: false, output: '', error: '缺少 taskId 参数');
      }
      final cache = MemoryCache.instance;
      await cache.load();
      final existing = cache.getTask(taskId);
      if (existing == null) {
        return ToolResult(toolName: 'task_update', success: false, output: '', error: '任务不存在: $taskId');
      }

      Map<String, dynamic> value = {};
      final raw = existing['value'];
      if (raw is String) {
        try { value = jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
      } else if (raw is Map<String, dynamic>) {
        value = raw;
      }

      final newTitle = params['title'] as String?;
      final newTaskPrompt = params['taskPrompt'] as String?;
      final newDueTime = params['dueTime'] as String?;
      final newInterval = params['repeatIntervalSeconds'] as int?;
      final newTaskType = params['taskType'] as String?;
      final newTimeout = params['timeoutSeconds'] as int?;
      final newMaxRetries = params['maxRetries'] as int?;

      final updated = Map<String, dynamic>.from(existing);
      if (newTitle == null && newTaskPrompt == null && newDueTime == null && newInterval == null && newTaskType == null && newTimeout == null && newMaxRetries == null) {
        return const ToolResult(toolName: 'task_update', success: false, output: '', error: '没有提供任何要修改的字段');
      }

      if (newTitle != null) value['title'] = newTitle;
      if (newTaskPrompt != null) value['description'] = newTaskPrompt;
      if (newTimeout != null) updated['timeout_seconds'] = newTimeout;
      if (newMaxRetries != null) updated['max_retries'] = newMaxRetries;

      // 更新周期/类型
      if (newInterval != null) {
        value['intervalSeconds'] = newInterval;
        value['taskType'] = newInterval > 0 ? 'recurring' : 'scheduled';
        updated['task_type'] = newInterval > 0 ? 'recurring' : 'scheduled';
        updated['interval_seconds'] = newInterval;
      }

      // 显式切换任务类型
      if (newTaskType != null && (newTaskType == 'scheduled' || newTaskType == 'recurring' || newTaskType == 'countdown')) {
        value['taskType'] = newTaskType;
        updated['task_type'] = newTaskType;
      }

      updated['value'] = jsonEncode(value);

      if (newDueTime != null) {
        DateTime dueTime;
        if (newDueTime.contains('分钟后')) {
          final mins = int.tryParse(RegExp(r'(\d+)').firstMatch(newDueTime)?.group(1) ?? '') ?? 5;
          dueTime = DateTime.now().add(Duration(minutes: mins));
        } else if (newDueTime.contains('秒后')) {
          final secs = int.tryParse(RegExp(r'(\d+)').firstMatch(newDueTime)?.group(1) ?? '') ?? 30;
          dueTime = DateTime.now().add(Duration(seconds: secs));
        } else if (newDueTime.contains('小时后')) {
          final hours = int.tryParse(RegExp(r'(\d+)').firstMatch(newDueTime)?.group(1) ?? '') ?? 1;
          dueTime = DateTime.now().add(Duration(hours: hours));
        } else if (newDueTime.contains('天')) {
          final days = int.tryParse(RegExp(r'(\d+)').firstMatch(newDueTime)?.group(1) ?? '') ?? 1;
          dueTime = DateTime.now().add(Duration(days: days));
        } else {
          dueTime = DateTime.tryParse(newDueTime) ?? DateTime.now().add(const Duration(minutes: 5));
        }
        updated['due_time'] = dueTime.millisecondsSinceEpoch;
      }

      await cache.updateTask(updated);
      final title = value['title'] ?? existing['title'] ?? taskId;
      return ToolResult(toolName: 'task_update', success: true, output: '任务已更新: $title');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'task_update', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _taskHistory(Map<String, dynamic> params) async {
    try {
      final limit = (params['limit'] as int?) ?? 20;
      final db = DatabaseHelper();
      final messages = await db.getTaskConversationMessages(limit: limit.clamp(1, 100));

      if (messages.isEmpty) {
        return const ToolResult(toolName: 'task_history', success: true, output: '暂无任务执行记录。');
      }

      // Group by alternating user/assistant pairs
      final buf = StringBuffer();
      buf.writeln('最近 ${messages.length} 条任务执行记录（新→旧）：');

      int pairNum = 0;
      for (int i = 0; i < messages.length; i++) {
        final msg = messages[i];
        final role = msg['role'] as String? ?? '';
        final content = msg['content'] as String? ?? '';
        final createdAt = msg['created_at'] as int?;
        final timeStr = createdAt != null
            ? DateTime.fromMillisecondsSinceEpoch(createdAt).toString().substring(0, 16)
            : '';

        if (role == 'user') {
          pairNum++;
          // Extract task title from wrapped format
          final title = content
              .replaceFirst('【定时任务】', '')
              .split('\n')
              .first
              .trim();
          buf.writeln('[$pairNum] $timeStr 📋 $title');
        } else if (role == 'assistant') {
          // Truncate assistant response to avoid flooding context
          final summary = content.length > 200 ? '${content.substring(0, 200)}...' : content;
          buf.writeln('    → $summary');
        }
      }

      return ToolResult(toolName: 'task_history', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'task_history', success: false, output: '', error: e.toString());
    }
  }

  // ─── PageIndex 文档索引与检索工具 ────────────────

  Future<void> _ensurePageIndexEngine() async {
    if (_pageIndexEngine != null) return;
    await _ensureMinimaxClient();
    if (_minimaxClient == null) return;
    _pageIndexEngine = PageIndexEngine(_minimaxClient!);
    _pageIndexRepo = PageIndexRepository(db: DatabaseHelper());
  }

  // ─── 记忆管理工具实现 ──────────────────────────

  Future<ToolResult> _memoryList(Map<String, dynamic> params) async {
    try {
      final category = params['category'] as String?;
      final cache = MemoryCache.instance;
      await cache.load();
      var entries = cache.allActive;
      if (category != null && category.isNotEmpty) {
        entries = entries.where((e) => e.category == category).toList();
      }
      if (entries.isEmpty) {
        return const ToolResult(toolName: 'memory_list', success: true, output: '暂无记忆条目');
      }
      final buf = StringBuffer();
      buf.writeln('共 ${entries.length} 条记忆：');
      final catNames = {
        'static': '静态', 'dynamic': '动态', 'preference': '偏好', 'notice': '注意',
        'interest': '兴趣', 'fact': '事实', 'experience': '经历', 'plan': '计划',
        'professional': '职业', 'health': '健康', 'relationship': '关系',
      };
      for (final e in entries) {
        final cat = catNames[e.category] ?? e.category;
        final conf = e.confidence == 'high' ? '★' : '';
        buf.writeln('- ${e.id}: [$cat]$conf ${e.content}');
      }
      return ToolResult(toolName: 'memory_list', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'memory_list', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _memorySearch(Map<String, dynamic> params) async {
    try {
      final query = (params['query'] as String? ?? '').toLowerCase();
      if (query.isEmpty) {
        return const ToolResult(toolName: 'memory_search', success: false, output: '', error: 'query 参数不能为空');
      }
      final cache = MemoryCache.instance;
      await cache.load();
      final matches = cache.allActive.where((e) =>
          e.content.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query)).toList();
      if (matches.isEmpty) {
        return ToolResult(toolName: 'memory_search', success: true, output: '未找到包含"$query"的记忆');
      }
      final buf = StringBuffer();
      buf.writeln('匹配 ${matches.length} 条：');
      for (final e in matches) {
        buf.writeln('- ${e.id}: [${e.category}] ${e.content}');
      }
      return ToolResult(toolName: 'memory_search', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'memory_search', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _memoryDelete(Map<String, dynamic> params) async {
    try {
      final id = params['id'] as String?;
      final keyword = params['keyword'] as String?;
      final cache = MemoryCache.instance;
      await cache.load();

      if (id != null && id.isNotEmpty) {
        // Delete by exact ID
        final entry = cache.allActive.where((e) => e.id == id).firstOrNull;
        if (entry == null) {
          return ToolResult(toolName: 'memory_delete', success: false, output: '', error: '未找到 ID 为 $id 的记忆');
        }
        await cache.remove(entry.category, entry.key ?? '');
        return ToolResult(toolName: 'memory_delete', success: true, output: '已删除: ${entry.content}');
      }

      if (keyword != null && keyword.isNotEmpty) {
        // Delete by keyword match
        final kw = keyword.toLowerCase();
        final matches = cache.allActive.where((e) => e.content.toLowerCase().contains(kw)).toList();
        if (matches.isEmpty) {
          return ToolResult(toolName: 'memory_delete', success: true, output: '未找到包含"$keyword"的记忆');
        }
        final buf = StringBuffer();
        buf.writeln('已删除 ${matches.length} 条记忆：');
        for (final e in matches) {
          buf.writeln('- ${e.content}');
          await cache.remove(e.category, e.key ?? '');
        }
        return ToolResult(toolName: 'memory_delete', success: true, output: buf.toString());
      }

      return const ToolResult(toolName: 'memory_delete', success: false, output: '', error: '请提供 id 或 keyword 参数');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'memory_delete', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _memoryAdd(Map<String, dynamic> params) async {
    try {
      final content = (params['content'] as String? ?? '').trim();
      if (content.isEmpty) {
        return const ToolResult(toolName: 'memory_change', success: false, output: '', error: 'content 参数不能为空');
      }
      final category = params['category'] as String? ?? 'fact';
      final key = params['key'] as String?;
      final confidence = params['confidence'] as String? ?? 'medium';

      final cache = MemoryCache.instance;
      await cache.load();
      await cache.addMemory(
        content: content,
        category: category,
        key: key,
        confidence: confidence,
      );

      final keyStr = key != null ? ' (key: $key)' : '';
      return ToolResult(toolName: 'memory_change', success: true, output: '记忆已添加: [$category$keyStr] $content');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'memory_change', success: false, output: '', error: e.toString());
    }
  }

  /// 解析文档路径：优先用参数，未传则用当前活跃文档
  String? _resolveDocPath(Map<String, dynamic> params) {
    final p = params['path'] as String?;
    if (p != null && p.isNotEmpty) return p;
    return _activeDocumentPath;
  }

  /// 设置活跃文档路径
  void _setActiveDoc(String path, String relPath) {
    _activeDocumentPath = path;
    _activeDocumentRelPath = relPath;
  }

  Future<ToolResult> _buildPageIndex(
    Map<String, dynamic> params,
    _WorkspaceInfo workspace,
  ) async {
    final path = params['path'] as String?;
    if (path == null || path.isEmpty) {
      return ToolResult(
        toolName: 'build_page_index',
        success: false, output: '',
        error: _missingParamError('build_page_index'),
      );
    }
    final relPath = _toRelativePath(path);
    final genSummaries = params['generate_summaries'] as bool? ?? false;
    final genDesc = params['generate_description'] as bool? ?? false;

    try {
      await _ensurePageIndexEngine();
      if (_pageIndexEngine == null || _pageIndexRepo == null) {
        return const ToolResult(
          toolName: 'build_page_index',
          success: false, output: '',
          error: 'API 客户端未就绪，无法调用 LLM',
        );
      }

      final mimeType = lookupMimeType(relPath);
      final bytes = await _safClient.readFileBytes(workspace.safUri!, relPath);
      if (bytes == null) {
        return ToolResult(
          toolName: 'build_page_index',
          success: false, output: '',
          error: '无法读取文件: ${_pathNote(path, relPath)}',
        );
      }

      final docId = _pageIndexRepo!.docIdFor(relPath);
      final docName = relPath.split('/').last;

      // 获取内容并检测真实页码
      final isMd = relPath.toLowerCase().endsWith('.md') ||
          mimeType == 'text/markdown';
      final isPdf = !isMd &&
          (relPath.toLowerCase().endsWith('.pdf') ||
              mimeType == 'application/pdf');

      String markdownContent;
      int? realPageCount;
      String docType = isMd ? 'markdown' : 'pdf';

      if (isMd) {
        markdownContent = utf8.decode(bytes);
      } else if (isPdf) {
        // 取得真实页数
        String? tmpPath;
        try {
          final tmpDir = await getTemporaryDirectory();
          tmpPath = '${tmpDir.path}/_pi_$docName';
          await File(tmpPath).writeAsBytes(bytes);
          realPageCount = await PdfNativeBridge.getPageCount(tmpPath);
        } catch (_) {}
        try { if (tmpPath != null) await File(tmpPath).delete(); } catch (_) {}

        final convResult = await FileUtils.convertToMarkdown(
          bytes: bytes, mimeType: mimeType, fileName: relPath,
        );
        markdownContent = convResult.markdownContent;
      } else {
        final convResult = await FileUtils.convertToMarkdown(
          bytes: bytes, mimeType: mimeType, fileName: relPath,
        );
        markdownContent = convResult.markdownContent;
      }

      final progressMessages = <String>[];
      final result = await _pageIndexEngine!.build(
        docId: docId,
        docName: docName,
        markdownContent: markdownContent,
        docType: docType,
        realPageCount: realPageCount,
        generateSummaries: genSummaries,
        generateDescription: genDesc,
        onProgress: (msg) => progressMessages.add(msg),
      );

      // 计算内容指纹用于增量更新检测（长度 + 前 1KB 的 base64）
      String? contentHash;
      try {
        final sample = bytes.length > 1024 ? bytes.sublist(0, 1024) : bytes;
        contentHash = '${bytes.length}_${base64.encode(sample).hashCode.toRadixString(16)}';
      } catch (_) {}

      await _pageIndexRepo!.saveIndex(result, contentHash: contentHash);
      _setActiveDoc(path, relPath); // 设为当前活跃文档

      final buf = StringBuffer();
      buf.writeln('索引构建完成');
      buf.writeln('文档: ${result.docName}');
      buf.writeln('类型: ${result.docType}');
      if (result.pageCount != null) buf.writeln('页数: ${result.pageCount}');
      if (result.lineCount != null) buf.writeln('行数: ${result.lineCount}');
      buf.writeln('节点数: ${flattenTree(result.structure).length}');
      buf.writeln();
      buf.writeln('--- 目录结构 ---');
      _formatTocTree(result.structure, buf);
      buf.writeln();
      buf.writeln('使用 get_document_structure 看结构，get_page_content 读具体内容。');

      return ToolResult(
        toolName: 'build_page_index',
        success: true,
        output: buf.toString(),
      );
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'build_page_index',
        success: false, output: '',
        error: '页面索引构建失败: $e',
      );
    }
  }

  void _formatTocTree(List<TreeNode> nodes, StringBuffer buf, [int indent = 0]) {
    for (final node in nodes) {
      final prefix = '  ' * indent;
      buf.writeln('$prefix[${node.nodeId ?? '?'}] ${node.title}'
          ' (${node.startIndex}-${node.endIndex})');
      if (node.nodes != null && node.nodes!.isNotEmpty) {
        _formatTocTree(node.nodes!, buf, indent + 1);
      }
    }
  }

  Future<ToolResult> _getDocumentInfo(Map<String, dynamic> params) async {
    final path = _resolveDocPath(params);
    if (path == null || path.isEmpty) {
      return const ToolResult(toolName: 'get_document_info', success: false, output: '', error: 'No document specified and no active document. Please pass path param / 未指定文档且无活跃文档。请传 path 参数。');
    }
    final relPath = _toRelativePath(path);
    _setActiveDoc(path, relPath);

    try {
      await _ensurePageIndexEngine();
      if (_pageIndexRepo == null) {
        return const ToolResult(
          toolName: 'get_document_info',
          success: false, output: '',
          error: 'Please use build_page_index to build document index first / 请先使用 build_page_index 构建文档索引',
        );
      }

      final result = await _pageIndexRepo!.getIndexByPath(relPath);
      if (result == null) {
        return ToolResult(
          toolName: 'get_document_info',
          success: false, output: '',
          error: 'Index not found for "${_pathNote(path, relPath)}". Please call build_page_index first / 未找到"${_pathNote(path, relPath)}"的索引。请先调用 build_page_index。',
        );
      }

      final buf = StringBuffer();
      buf.writeln('Name / 名称: ${result.docName}');
      buf.writeln('Type / 类型: ${result.docType}');
      if (result.docDescription != null) buf.writeln('Description / 描述: ${result.docDescription}');
      if (result.pageCount != null) buf.writeln('Pages / 页数: ${result.pageCount}');
      if (result.lineCount != null) buf.writeln('Lines / 行数: ${result.lineCount}');
      buf.writeln('Sections / 章节数: ${flattenTree(result.structure).length}');
      buf.writeln('Build time / 构建时间: ${result.createdAt.toIso8601String()}');

      return ToolResult(toolName: 'get_document_info', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'get_document_info', success: false, output: '', error: 'Get failed: $e / 获取失败: $e');
    }
  }

  Future<ToolResult> _getDocumentStructure(Map<String, dynamic> params) async {
    final path = _resolveDocPath(params);
    if (path == null || path.isEmpty) {
      return const ToolResult(toolName: 'get_document_structure', success: false, output: '', error: 'No document specified and no active document. Please pass path param / 未指定文档且无活跃文档。请传 path 参数。');
    }
    final relPath = _toRelativePath(path);
    _setActiveDoc(path, relPath);
    final includeSummaries = params['include_summaries'] as bool? ?? false;
    final maxNodes = params['max_nodes'] as int? ?? 100;
    final query = params['query'] as String?;

    try {
      await _ensurePageIndexEngine();
      if (_pageIndexRepo == null) {
        return const ToolResult(toolName: 'get_document_structure', success: false, output: '', error: 'Please use build_page_index to build document index first / 请先使用 build_page_index 构建文档索引');
      }

      final result = await _pageIndexRepo!.getIndexByPath(relPath);
      if (result == null) {
        return ToolResult(toolName: 'get_document_structure', success: false, output: '', error: 'Index not found for "${_pathNote(path, relPath)}". Please call build_page_index first / 未找到"${_pathNote(path, relPath)}"的索引。请先调用 build_page_index。');
      }

      final fieldsToRemove = <String>['text'];
      if (!includeSummaries) fieldsToRemove.add('summary');

      var structure = removeFields(result.structure, fieldsToRemove) as List<dynamic>;

      // 如果有查询参数，标记相关节点并附带内容
      List<Map<String, dynamic>>? relevantSections;
      if (query != null && query.isNotEmpty) {
        relevantSections = _findRelevantSections(result.structure, query, fieldsToRemove);
      }

      // Token 预算控制：截断到大节点数
      final totalNodes = flattenTree(result.structure).length;
      if (maxNodes > 0 && structure.length > maxNodes) {
        structure = structure.sublist(0, maxNodes);
      }

      final truncatedNote = totalNodes > maxNodes && maxNodes > 0
          ? '(Truncated, showing $maxNodes/$totalNodes root nodes / 已截断，显示 $maxNodes/$totalNodes 个根节点)'
          : '';

      var output = '${result.docName} (${result.pageCount ?? result.lineCount ?? '?'} pages, $totalNodes sections) $truncatedNote\n${jsonEncode(structure)}';
      if (relevantSections != null && relevantSections.isNotEmpty) {
        output += '\n\n--- Sections related to "$query" / 与 "$query" 相关的章节 ---\n${jsonEncode(relevantSections)}';
      }

      return ToolResult(toolName: 'get_document_structure', success: true, output: output);
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'get_document_structure', success: false, output: '', error: 'Get failed: $e / 获取失败: $e');
    }
  }

  Future<ToolResult> _getPageContent(
    Map<String, dynamic> params,
    _WorkspaceInfo workspace,
  ) async {
    final path = _resolveDocPath(params);
    final pages = params['pages'] as String?;
    if (path == null || path.isEmpty || pages == null || pages.isEmpty) {
      return const ToolResult(
        toolName: 'get_page_content',
        success: false, output: '',
        error: '未指定文档且无活跃文档，或缺少 pages 参数。',
      );
    }
    final relPath = _toRelativePath(path);
    _setActiveDoc(path, relPath);

    try {
      final pageNums = parsePages(pages);
      if (pageNums.isEmpty) {
        return ToolResult(
          toolName: 'get_page_content',
          success: false, output: '',
          error: '无效的页码范围: "$pages"。使用 "5"、"5-10" 或 "3,8,12" 格式。',
        );
      }

      final isMd = relPath.toLowerCase().endsWith('.md');
      final bytes = await _safClient.readFileBytes(workspace.safUri!, relPath);
      if (bytes == null) {
        return ToolResult(
          toolName: 'get_page_content',
          success: false, output: '',
          error: '无法读取文件: ${_pathNote(path, relPath)}',
        );
      }

      if (isMd) {
        final content = utf8.decode(bytes);
        final lines = content.split('\n');
        final buf = StringBuffer();
        for (final pageNum in pageNums) {
          if (pageNum >= 1 && pageNum <= lines.length) {
            buf.writeln('--- 行 $pageNum ---');
            final start = (pageNum - 1).clamp(0, lines.length);
            final end = (start + 50).clamp(0, lines.length);
            buf.writeln(lines.sublist(start, end).join('\n'));
            buf.writeln();
          }
        }
        return ToolResult(toolName: 'get_page_content', success: true, output: buf.toString());
      }

      // PDF: 使用索引定位 + 渲染页面获取内容
      await _ensurePageIndexEngine();
      final result = await _pageIndexRepo?.getIndexByPath(relPath);
      final allNodes = result != null ? flattenTree(result.structure) : [];

      // 写临时文件一次，循环渲染各页面
      String? tmpPath;
      try {
        final tmpDir = await getTemporaryDirectory();
        tmpPath = '${tmpDir.path}/_pc_${relPath.split('/').last}';
        await File(tmpPath).writeAsBytes(bytes);
      } catch (_) {}

      final buf = StringBuffer();
      for (final pageNum in pageNums) {
        bool hasContent = false;

        final covering = allNodes.where(
          (n) => n.startIndex <= pageNum && n.endIndex >= pageNum,
        ).toList();

        buf.writeln('--- 第 $pageNum 页 ---');
        if (covering.isNotEmpty) {
          hasContent = true;
          for (final node in covering) {
            buf.write('[${node.title}]');
            if (node.summary != null) buf.write(' ${node.summary}');
            buf.writeln();
          }
        }

        if (tmpPath != null) {
          try {
            final pngBytes = await PdfNativeBridge.renderPageBytes(tmpPath, pageNum - 1);
            if (pngBytes != null && _minimaxClient != null) {
              final pageB64 = base64.encode(pngBytes);
              final ocr = await _minimaxClient!.vision(pageB64,
                  'Transcribe all visible text from this document page faithfully. '
                  'Preserve paragraph structure. For tables, align with spaces.');
              if (ocr.isNotEmpty) {
                hasContent = true;
                final truncated = ocr.length > 8000
                    ? '${ocr.substring(0, 8000)}...[截断]'
                    : ocr;
                buf.writeln(truncated);
              }
            }
          } catch (_) {}
        }

        if (!hasContent) {
          buf.writeln('(该页无索引信息，使用 convertFile $path 查看)');
        }
        buf.writeln();
      }

      try { if (tmpPath != null) await File(tmpPath).delete(); } catch (_) {}

      return ToolResult(toolName: 'get_page_content', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'get_page_content',
        success: false, output: '',
        error: '获取页面内容失败: $e',
      );
    }
  }

  Future<ToolResult> _listIndexedDocuments() async {
    try {
      await _ensurePageIndexEngine();
      if (_pageIndexRepo == null) {
        return const ToolResult(
          toolName: 'list_indexed_documents',
          success: true,
          output: '暂无已索引的文档。使用 build_page_index 为文档建立索引。',
        );
      }

      final indices = await _pageIndexRepo!.listIndices();
      if (indices.isEmpty) {
        return const ToolResult(
          toolName: 'list_indexed_documents',
          success: true,
          output: '暂无已索引的文档。使用 build_page_index 为文档建立索引。',
        );
      }

      final buf = StringBuffer();
      buf.writeln('已索引文档 (${indices.length}):');
      for (final idx in indices) {
        final typeLabel = idx.docType.toUpperCase();
        final sizeLabel = idx.pageCount != null
            ? '${idx.pageCount}页'
            : idx.lineCount != null
                ? '${idx.lineCount}行'
                : '';
        buf.write('  - ${idx.docName} [$typeLabel $sizeLabel]');
        if (idx.docDescription != null) {
          buf.write(' — ${idx.docDescription}');
        }
        buf.writeln();
      }
      return ToolResult(
        toolName: 'list_indexed_documents',
        success: true,
        output: buf.toString(),
      );
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'list_indexed_documents',
        success: false, output: '',
        error: '获取文档列表失败: $e',
      );
    }
  }

  Future<ToolResult> _searchDocuments(Map<String, dynamic> params) async {
    final query = params['query'] as String?;
    if (query == null || query.trim().isEmpty) {
      return ToolResult(toolName: 'search_documents', success: false, output: '', error: _missingParamError('search_documents'));
    }
    try {
      await _ensurePageIndexEngine();
      if (_pageIndexRepo == null) {
        return const ToolResult(toolName: 'search_documents', success: true, output: 'No indexed documents yet / 暂无已索引文档。');
      }
      final results = await _pageIndexRepo!.searchAcrossIndices(query.trim());
      if (results.isEmpty) {
        return ToolResult(toolName: 'search_documents', success: true, output: 'No matching sections found for "$query" in any indexed document / 未在任何已索引文档中找到与 "$query" 匹配的章节。');
      }
      final buf = StringBuffer();
      buf.writeln('Search "$query" results (${results.length} items) / 搜索 "$query" 结果 (${results.length} 条):');
      String? currentDoc;
      for (final r in results) {
        if (r['doc'] != currentDoc) { currentDoc = r['doc'] as String; buf.writeln('\n📄 $currentDoc'); }
        buf.write('  [${r['node_id']}] ${r['title']} (${r['start']}-${r['end']})');
        if (r['summary'] != null) buf.write(' — ${r['summary']}');
        buf.writeln();
      }
      return ToolResult(toolName: 'search_documents', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'search_documents', success: false, output: '', error: 'Search failed: $e / 搜索失败: $e');
    }
  }

  /// 在树结构中查找与查询相关的章节
  List<Map<String, dynamic>> _findRelevantSections(
    List<TreeNode> nodes, String query, List<String> fieldsToRemove,
  ) {
    final q = query.toLowerCase();
    final results = <Map<String, dynamic>>[];
    void search(List<TreeNode> ns) {
      for (final n in ns) {
        if (n.title.toLowerCase().contains(q) || (n.summary?.toLowerCase().contains(q) ?? false)) {
          final m = n.toJson();
          for (final f in fieldsToRemove) { m.remove(f); }
          m.remove('nodes'); // 不展示子树，避免膨胀
          results.add(m);
        }
        if (n.nodes != null) search(n.nodes!);
      }
    }
    search(nodes);
    return results.take(20).toList(); // 最多 20 条防 token 爆炸
  }

  /// 一站式读取章节：通过标题或查询匹配到章节，直接返回其内容
  Future<ToolResult> _readSection(Map<String, dynamic> params, _WorkspaceInfo workspace) async {
    final path = _resolveDocPath(params);
    final query = params['query'] as String?;
    final sectionTitle = params['section'] as String?;
    if (path == null || path.isEmpty) {
      return const ToolResult(toolName: 'read_section', success: false, output: '', error: 'No document specified and no active document / 未指定文档且无活跃文档。');
    }
    if ((query == null || query.isEmpty) && (sectionTitle == null || sectionTitle.isEmpty)) {
      return const ToolResult(toolName: 'read_section', success: false, output: '', error: 'Missing query or section param / 缺少 query 或 section 参数。');
    }
    final relPath = _toRelativePath(path);
    _setActiveDoc(path, relPath);

    try {
      await _ensurePageIndexEngine();
      final result = await _pageIndexRepo?.getIndexByPath(relPath);
      if (result == null) {
        return const ToolResult(toolName: 'read_section', success: false, output: '', error: 'Please run build_page_index first / 请先 build_page_index。');
      }

      final searchTerm = (sectionTitle ?? query!).toLowerCase();
      final allNodes = flattenTree(result.structure);
      final matches = allNodes.where((n) =>
        n.title.toLowerCase().contains(searchTerm) ||
        (n.summary?.toLowerCase().contains(searchTerm) ?? false)
      ).toList();

      if (matches.isEmpty) {
        return ToolResult(toolName: 'read_section', success: true, output: 'No matching sections found for "$searchTerm". Use get_document_structure to view full outline / 未找到与 "$searchTerm" 匹配的章节。可调用 get_document_structure 查看完整目录。');
      }

      final buf = StringBuffer();
      buf.writeln('Found ${matches.length} matching sections / 找到 ${matches.length} 个匹配章节:\n');
      for (final node in matches.take(5)) {
        buf.writeln('## ${node.title} (${node.startIndex}-${node.endIndex})');
        if (node.summary != null) buf.writeln('> ${node.summary}');

        // Read actual content of this section / 读取该章节的实际内容
        if (result.docType == 'markdown') {
          buf.writeln('(Use get_page_content pages="${node.startIndex}-${node.endIndex}" to read full content / 使用 get_page_content pages="${node.startIndex}-${node.endIndex}" 读取完整内容)');
        } else {
          buf.writeln('(Use get_page_content pages="${node.startIndex}-${node.endIndex}" to read this section / 使用 get_page_content pages="${node.startIndex}-${node.endIndex}" 读取此节)');
        }
        buf.writeln();
      }
      return ToolResult(toolName: 'read_section', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'read_section', success: false, output: '', error: 'Read section failed: $e / 读取章节失败: $e');
    }
  }

  /// 关闭当前活跃文档
  Future<ToolResult> _closeDocument() async {
    final doc = _activeDocumentPath ?? '(无)';
    _activeDocumentPath = null;
    _activeDocumentRelPath = null;
    return ToolResult(toolName: 'close_document', success: true, output: 'Document closed: $doc / 已关闭文档: $doc');
  }

  Future<ToolResult> _deletePageIndex(Map<String, dynamic> params) async {
    final path = _resolveDocPath(params);
    if (path == null || path.isEmpty) {
      return const ToolResult(toolName: 'delete_page_index', success: false, output: '', error: 'No document specified and no active document / 未指定文档且无活跃文档。');
    }
    final relPath = _toRelativePath(path);
    try {
      await _ensurePageIndexEngine();
      await _pageIndexRepo?.deleteIndexByPath(relPath);
      if (_activeDocumentRelPath == relPath) { _activeDocumentPath = null; _activeDocumentRelPath = null; }
      return ToolResult(toolName: 'delete_page_index', success: true, output: 'Deleted page index for "${_pathNote(path, relPath)}" / 已删除 "${_pathNote(path, relPath)}" 的页面索引。');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(
        toolName: 'delete_page_index',
        success: false, output: '',
        error: 'Delete index failed: $e / 删除索引失败: $e',
      );
    }
  }

  Future<ToolResult> _notificationRead(Map<String, dynamic> params) async {
    try {
      final client = NotificationListenerClient();
      final isGranted = await client.isPermissionGranted();
      if (!isGranted) {
        return const ToolResult(toolName: 'notification_read', success: false, output: '',
            error: 'Notification listener permission not granted, please enable in system settings / 通知监听权限未授予，请在系统设置中开启');
      }
      final notifs = await client.getRecentNotifications(limit: params['limit'] as int? ?? 50);
      if (notifs.isEmpty) return const ToolResult(toolName: 'notification_read', success: true, output: 'No recent notifications / 无最近通知');
      final buf = StringBuffer();
      for (final n in notifs) {
        final ts = n['timestamp'] as int? ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(ts > 0 ? ts : DateTime.now().millisecondsSinceEpoch);
        final timeStr = '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        buf.writeln('[$timeStr] ${n['appName']} (${n['packageName']})');
        buf.writeln('  ${n['title']}: ${n['text']}');
        buf.writeln();
      }
      return ToolResult(toolName: 'notification_read', success: true, output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'notification_read', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _notificationPost(Map<String, dynamic> params) async {
    try {
      final title = params['title'] as String?;
      final body = params['body'] as String?;
      if (title == null || title.isEmpty) return const ToolResult(toolName: 'notification_post', success: false, output: '', error: 'Missing title / 缺少 title');
      if (body == null || body.isEmpty) return const ToolResult(toolName: 'notification_post', success: false, output: '', error: 'Missing body / 缺少 body');
      final client = NotificationListenerClient();
      await client.postNotification(title: title, body: body);
      return const ToolResult(toolName: 'notification_post', success: true, output: '通知已发布');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'notification_post', success: false, output: '', error: e.toString());
    }
  }

  /// 快递物流追踪 — 快递100 API
  Future<ToolResult> _expressTrack(Map<String, dynamic> params) async {
    try {
      final trackingNumber = params['trackingNumber'] as String?;
      if (trackingNumber == null || trackingNumber.trim().isEmpty) {
        return const ToolResult(toolName: 'express_track', success: false, output: '', error: '缺少快递单号');
      }
      final num = trackingNumber.trim();
      if (num.length < 6 || num.length > 32) {
        return const ToolResult(toolName: 'express_track', success: false, output: '', error: '单号长度应在6-32位之间');
      }

      final com = (params['companyCode'] as String?)?.trim() ?? '';
      final phone = (params['phone'] as String?)?.trim() ?? '';

      final settings = SettingsRepository();
      final customer = await settings.getKuaidi100Customer();
      final key = await settings.getKuaidi100Key();

      if (customer.isEmpty || key.isEmpty) {
        return const ToolResult(toolName: 'express_track', success: false, output: '',
          error: '快递100未配置。请在设置中填入快递100的 customer 和 key（申请地址：https://api.kuaidi100.com）');
      }

      final client = Kuaidi100Client(customer: customer, key: key);
      final result = await client.queryFormatted(num, com: com, phone: phone);

      return ToolResult(toolName: 'express_track', success: true, output: result);
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'express_track', success: false, output: '',
        error: '快递查询失败: $e');
    }
  }

  /// 快递订阅监控
  Future<ToolResult> _expressSubscribe(Map<String, dynamic> params) async {
    try {
      final trackingNumber = params['trackingNumber'] as String?;
      if (trackingNumber == null || trackingNumber.trim().isEmpty) {
        return const ToolResult(toolName: 'express_subscribe', success: false, output: '', error: '缺少快递单号');
      }
      final num = trackingNumber.trim();
      if (num.length < 6 || num.length > 32) {
        return const ToolResult(toolName: 'express_subscribe', success: false, output: '', error: '单号长度应在6-32位之间');
      }

      final com = (params['companyCode'] as String?)?.trim() ?? '';
      final phone = (params['phone'] as String?)?.trim() ?? '';

      final settings = SettingsRepository();
      final customer = await settings.getKuaidi100Customer();
      final key = await settings.getKuaidi100Key();

      if (customer.isEmpty || key.isEmpty) {
        return const ToolResult(toolName: 'express_subscribe', success: false, output: '',
          error: '快递100未配置。请在设置中填入快递100的 customer 和 key');
      }

      final callbackUrl = (await settings.getKuaidi100CallbackUrl()).trim();

      final client = Kuaidi100Client(customer: customer, key: key);
      final result = await client.subscribeFormatted(num, com: com, phone: phone,
          callbackUrl: callbackUrl.isNotEmpty ? callbackUrl : null);

      // 本地保存订阅记录
      if (result.startsWith('✅')) {
        await settings.addKuaidi100Subscription({
          'num': num,
          'com': com,
          'phone': phone,
          'subscribedAt': DateTime.now().toIso8601String(),
        });
      }

      // 如果有回调服务器，提示推送已配置
      final suffix = callbackUrl.isNotEmpty
          ? '\n\n📡 状态变化将推送到: $callbackUrl'
          : '\n\n💡 暂未配置回调服务器。可稍后用 express_check_subscriptions 批量查询已订阅的快递，或定期用 express_track 手动查询。';

      return ToolResult(toolName: 'express_subscribe', success: true, output: '$result$suffix');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'express_subscribe', success: false, output: '',
        error: '快递订阅失败: $e');
    }
  }

  /// 快递地图轨迹
  Future<ToolResult> _expressMap(Map<String, dynamic> params) async {
    try {
      final num = (params['trackingNumber'] as String?)?.trim();
      final com = (params['companyCode'] as String?)?.trim();
      final from = (params['from'] as String?)?.trim();
      final to = (params['to'] as String?)?.trim();
      final phone = (params['phone'] as String?)?.trim() ?? '';

      if (num == null || num.isEmpty) return const ToolResult(toolName: 'express_map', success: false, output: '', error: '缺少快递单号');
      if (com == null || com.isEmpty) return const ToolResult(toolName: 'express_map', success: false, output: '', error: '地图轨迹需要指定快递公司编码');
      if (from == null || from.isEmpty) return const ToolResult(toolName: 'express_map', success: false, output: '', error: '缺少发件地址');
      if (to == null || to.isEmpty) return const ToolResult(toolName: 'express_map', success: false, output: '', error: '缺少收件地址');

      final settings = SettingsRepository();
      final customer = await settings.getKuaidi100Customer();
      final key = await settings.getKuaidi100Key();

      if (customer.isEmpty || key.isEmpty) {
        return const ToolResult(toolName: 'express_map', success: false, output: '',
          error: '快递100未配置。请在设置中填入快递100的 customer 和 key');
      }

      final client = Kuaidi100Client(customer: customer, key: key);
      final result = await client.mapTrackFormatted(num, com, from: from, to: to, phone: phone);

      return ToolResult(toolName: 'express_map', success: true, output: result);
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'express_map', success: false, output: '',
        error: '地图轨迹查询失败: $e');
    }
  }

  /// 批量查询已订阅快递
  Future<ToolResult> _expressCheckSubscriptions(Map<String, dynamic> params) async {
    try {
      final limit = (params['limit'] as int?) ?? 10;

      final settings = SettingsRepository();
      final subs = await settings.getKuaidi100Subscriptions();

      if (subs.isEmpty) {
        return const ToolResult(toolName: 'express_check_subscriptions', success: true,
          output: '目前没有订阅的快递。用 express_subscribe 订阅快递单号后，可以用此功能批量查看。');
      }

      final customer = await settings.getKuaidi100Customer();
      final key = await settings.getKuaidi100Key();
      if (customer.isEmpty || key.isEmpty) {
        return const ToolResult(toolName: 'express_check_subscriptions', success: false, output: '',
          error: '快递100未配置');
      }

      final buf = StringBuffer();
      buf.writeln('📋 已订阅 ${subs.length} 个快递，查询最近 $limit 个:');
      buf.writeln();

      final client = Kuaidi100Client(customer: customer, key: key);
      int checked = 0;

      for (final sub in subs.take(limit)) {
        final num = sub['num'] as String? ?? '';
        final com = sub['com'] as String? ?? '';
        if (num.isEmpty) continue;
        checked++;

        try {
          final result = await client.queryFormatted(num, com: com);
          // 只取前两行（单号+公司+状态），不输出完整轨迹
          final lines = result.split('\n');
          for (var i = 0; i < lines.length && i < 6; i++) {
            buf.writeln(lines[i]);
          }
          buf.writeln('---');
        } catch (e) {
          print('[ToolExecutor] error: \$e');
          buf.writeln('📦 $num: 查询失败 ($e)');
          buf.writeln('---');
        }
      }

      if (checked == 0) {
        buf.writeln('无有效订阅记录');
      }

      return ToolResult(toolName: 'express_check_subscriptions', success: true,
        output: buf.toString());
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'express_check_subscriptions', success: false, output: '',
        error: '批量查询失败: $e');
    }
  }

  /// 设备屏幕截图 + 离线 OCR
  Future<ToolResult> _screenCapture(Map<String, dynamic> params) async {
    try {
      // 1. Ensure OCR model is loaded
      await PdfOcrBridge.ensureLoaded();

      // 2. Capture screenshot
      final captureClient = ScreenCaptureClient();
      final imagePath = await captureClient.capture();

      // 3. OCR the screenshot
      final ocrBridge = PdfOcrBridge();
      final result = await ocrBridge.recognizeFile(imagePath);
      if (!result.hasText) {
        return const ToolResult(toolName: 'screen_capture', success: true,
          output: '截图完成，但屏幕上没有可识别的文字。');
      }
      return ToolResult(toolName: 'screen_capture', success: true,
        output: result.text);
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        return const ToolResult(toolName: 'screen_capture', success: false, output: '',
          error: '用户拒绝了屏幕录制权限，请重新尝试。');
      }
      return ToolResult(toolName: 'screen_capture', success: false, output: '',
        error: '截图失败: ${e.message}');
    } catch (e) {
      print('[ToolExecutor] error: \$e');
      return ToolResult(toolName: 'screen_capture', success: false, output: '',
        error: '截图OCR失败: $e');
    }
  }

}
