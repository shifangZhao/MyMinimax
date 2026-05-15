import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../memory/data/memory_cache.dart';
import '../../memory/data/memory_entry.dart';
import '../../memory/data/memory_budget_controller.dart';
import '../../../core/api/time_offset_service.dart';
import '../../../core/tools/trend_tools.dart';

enum SafetyProfile { safe, standard, permissive }

class _InferenceTier {
  const _InferenceTier({required this.name, required this.maxTokens, required this.thinkingBudget});
  final String name;
  final int maxTokens;
  final int thinkingBudget;
}

class SettingsRepository {
  static const _apiKeyKey = 'minimax_api_key';
  static const _apiKeyStandardKey = 'minimax_api_key_standard';
  static const _activeApiKeyTypeKey = 'minimax_active_api_key_type';
  static const _modelKey = 'minimax_model';
  static const _baseUrlKey = 'minimax_base_url';
  static const _safUriKey = 'saf_tree_uri';
  static const _themeModeKey = 'app_theme_mode';
  static const _languageKey = 'app_language';
  static const _temperatureKey = 'minimax_temperature';
  static const _toolChoiceKey = 'minimax_tool_choice';
  static const _conciseModeKey = 'concise_mode';
  static const _ttsModelKey = 'tts_model';
  static const _ttsVoiceKey = 'tts_voice';
  static const _ttsEnabledKey = 'tts_enabled';
  static const _userAvatarKey = 'user_avatar_path';
  static const _agentAvatarKey = 'agent_avatar_path';
  static const _kuaidi100CustomerKey = 'kuaidi100_customer';
  static const _kuaidi100KeyKey = 'kuaidi100_key';
  static const _kuaidi100CallbackKey = 'kuaidi100_callback_url';
  static const _kuaidi100SubsKey = 'kuaidi100_subscriptions';
  static const _amapApiKeyKey = 'amap_api_key';
  static const _amapNativeApiKeyKey = 'amap_native_api_key';
  static const _mcpServersKey = 'mcp_servers_config';

  static const defaultModel = 'MiniMax-M2.7';
  static const defaultBaseUrl = 'https://api.minimaxi.com';
  static const defaultRole = '你是用户的个人智能助手。你的能力和偏好会随着与用户的交流动态调整。';

  static const availableModels = [
    'MiniMax-M2.7',
    'MiniMax-M2.7-highspeed',
    'MiniMax-M2.5',
    'MiniMax-M2.5-highspeed',
    'MiniMax-M2.1',
    'MiniMax-M2.1-highspeed',
    'MiniMax-M2',
  ];

  Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey) ?? '';
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
  }

  Future<String> getApiKeyStandard() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyStandardKey) ?? '';
  }

  Future<void> setApiKeyStandard(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyStandardKey, key);
  }

  Future<String> getKuaidi100Customer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kuaidi100CustomerKey) ?? '';
  }
  Future<void> setKuaidi100Customer(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kuaidi100CustomerKey, value);
  }
  Future<String> getKuaidi100Key() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kuaidi100KeyKey) ?? '';
  }
  Future<void> setKuaidi100Key(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kuaidi100KeyKey, value);
  }

  Future<String> getKuaidi100CallbackUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kuaidi100CallbackKey) ?? '';
  }
  Future<void> setKuaidi100CallbackUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kuaidi100CallbackKey, value);
  }

  /// 订阅列表：JSON 数组 [{num, com, phone, subscribedAt}]
  Future<List<Map<String, dynamic>>> getKuaidi100Subscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kuaidi100SubsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is List) return list.cast<Map<String, dynamic>>();
    } catch (_) {}
    return [];
  }
  Future<void> addKuaidi100Subscription(Map<String, dynamic> sub) async {
    final list = await getKuaidi100Subscriptions();
    list.removeWhere((s) => s['num'] == sub['num']);
    list.insert(0, sub);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kuaidi100SubsKey, jsonEncode(list));
  }
  Future<void> removeKuaidi100Subscription(String num) async {
    final list = await getKuaidi100Subscriptions();
    list.removeWhere((s) => s['num'] == num);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kuaidi100SubsKey, jsonEncode(list));
  }

  Future<String> getAmapApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_amapApiKeyKey) ?? '';
  }

  Future<void> setAmapApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_amapApiKeyKey, key);
  }

  Future<String> getAmapNativeApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_amapNativeApiKeyKey) ?? '';
  }

  Future<void> setAmapNativeApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_amapNativeApiKeyKey, key);
  }

  Future<String> getActiveApiKeyType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeApiKeyTypeKey) ?? 'token';
  }

  Future<void> setActiveApiKeyType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeApiKeyTypeKey, type);
  }

  Future<String> getActiveApiKey() async {
    final type = await getActiveApiKeyType();
    if (type == 'standard') {
      return getApiKeyStandard();
    }
    return getApiKey();
  }

  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modelKey) ?? defaultModel;
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelKey, model);
  }

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  Future<bool> isConfigured() async {
    final apiKey = await getActiveApiKey();
    return apiKey.isNotEmpty;
  }

  // SAF 外部存储授权 URI
  Future<String> getSafUri() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_safUriKey) ?? '';
  }

  Future<void> setSafUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    if (uri.isEmpty) {
      await prefs.remove(_safUriKey);
    } else {
      await prefs.setString(_safUriKey, uri);
    }
  }

  Future<void> clearSafUri() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_safUriKey);
  }

  // 主题模式
  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeModeKey) ?? 'system';
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      case ThemeMode.system:
        value = 'system';
        break;
    }
    await prefs.setString(_themeModeKey, value);
  }

  Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? 'zh';
  }

  Future<void> setLanguage(String locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, locale);
  }

  // ── 推理参数（MiniMax 最佳实践） ──

  static const double defaultTemperature = 1.0;
  static const String defaultToolChoice = 'auto';

  // 推理挡位定义（思考预算 = maxTokens × 35%）
  static const String _inferenceTierKey = 'inference_tier';

  static const List<_InferenceTier> inferenceTiers = [
    _InferenceTier(name: '普通',   maxTokens: 4096,  thinkingBudget: 1434),
    _InferenceTier(name: '中等',   maxTokens: 8192,  thinkingBudget: 2867),
    _InferenceTier(name: '高强度', maxTokens: 16384, thinkingBudget: 5734),
    _InferenceTier(name: '极限',   maxTokens: 32768, thinkingBudget: 11469),
  ];

  static const int defaultInferenceTier = 2; // 高强度

  Future<double> getTemperature() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_temperatureKey) ?? defaultTemperature;
  }

  Future<void> setTemperature(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_temperatureKey, value);
  }

  Future<int> getMaxTokens() async {
    final tier = await getInferenceTier();
    final safeTier = tier.clamp(0, inferenceTiers.length - 1);
    return inferenceTiers[safeTier].maxTokens;
  }

  Future<int> getThinkingBudget() async {
    final tier = await getInferenceTier();
    final safeTier = tier.clamp(0, inferenceTiers.length - 1);
    return inferenceTiers[safeTier].thinkingBudget;
  }

  Future<int> getInferenceTier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_inferenceTierKey) ?? defaultInferenceTier;
  }

  Future<void> setInferenceTier(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_inferenceTierKey, index);
  }

  Future<String> getToolChoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_toolChoiceKey) ?? defaultToolChoice;
  }

  Future<void> setToolChoice(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_toolChoiceKey, value);
  }

  Future<bool> getConciseMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_conciseModeKey) ?? false;
  }

  Future<void> setConciseMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_conciseModeKey, value);
  }

  /// 使用 TimeOffsetService 缓存的偏差修正设备时间，无需逐次调 API。
  String _buildTimeSection() {
    final service = TimeOffsetService.instance;
    final buf = StringBuffer();
    buf.writeln('【当前时间】');

    if (service.isCalibrated) {
      final now = service.now();
      final weekday = service.weekday ?? '';
      final timezone = service.timezone ?? DateTime.now().timeZoneName;
      buf.writeln('现在时刻：${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日 $weekday '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}（$timezone）');
    } else {
      // Fallback: device local time (API never calibrated)
      final now = DateTime.now();
      const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
      final tzName = now.timeZoneName;
      buf.writeln('现在时刻：${now.year}年${now.month}月${now.day}日 星期${weekdays[now.weekday - 1]} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}（$tzName）');
    }

    buf.writeln('你回复中所有日期、星期、时间计算必须基于以上时间，不要凭训练数据猜测。');
    buf.writeln('用户说"今天""昨天""明天""本周""上周""下周""这个月"等相对时间，一律根据上面的时刻推算。');
    return buf.toString();
  }

  // ── 结构化系统提示词（Anthropic content block 数组，支持 cache_control） ──
  /// 将系统提示词拆分为静态块（含 cache_control 断点）和动态块。
  /// MiniMax 缓存按 tools → system → messages 前缀匹配，
  /// 静态内容放在前面并标记 cache_control，动态内容追加在后方。
  Future<List<Map<String, dynamic>>> buildSystemContent({
    String? browserTitle,
    String? browserUrl,
    int browserTabCount = 0,
    String? messageQuery,
  }) async {
    final safUri = await getSafUri();
    final blocks = <Map<String, dynamic>>[];

    // ── Block 1: 静态核心（cache_control 断点 → 以下全部进入缓存） ──
    final conciseMode = await getConciseMode();
    final staticBuf = StringBuffer();

    staticBuf.writeln(defaultRole);
    staticBuf.writeln();

    staticBuf.writeln('【规则】');
    staticBuf.writeln('1. 说真话 — 拿不准就查（浏览器/工具/记忆）。查到用，查不到说"不确定"。数字、日期、URL 宁缺毋滥，编一个错的比承认不知道糟糕得多。');
    staticBuf.writeln('   来源标注：回答中涉及的事实，标注来源——[记忆]=用户画像，[查证]=浏览器/工具验证，没标=你自己知道的。');
    staticBuf.writeln('2. 说人话 — 微信怎么聊你就怎么回，别做客服做朋友。有立场不端水。不确定就说"不确定"。');
    staticBuf.writeln('3. 说到位 — 多问多答逐一回应，模糊就反问。多步任务做完再汇报。记住用户说过的偏好和话题，别回头又问。');
    staticBuf.writeln('4. 不说坐标 — 绝不要输出经纬度数字（如39.9, 116.4）。用地址、地名、地标、区域来描述位置。');
    staticBuf.writeln();

    staticBuf.writeln('【记忆规则 — 这些场景必须立刻调用 memory_change 存入记忆，不能仅靠上下文】');
    staticBuf.writeln('用户告知自己的信息 → category=fact/static：名字、年龄、职业、住址、兴趣、健康等');
    staticBuf.writeln('用户给你（智能体）起名字 → category=dynamic key=agentName value=名字。如"以后叫你小助手"→存入 agentName。这是你自己的称呼，不是用户的称呼。');
    staticBuf.writeln('用户说你怎么称呼他/她（用户本人） → category=dynamic key=namePreference value=称呼。如"叫我老板就行"→存入 namePreference。这是对用户的称呼，不是你自己的身份。');
    staticBuf.writeln('用户带尊称 → category=dynamic key=userTitle value=尊称。如"叫我王老师"→ namePreference=王, userTitle=老师。');
    staticBuf.writeln('用户表达偏好 → category=preference：回答风格(answerStyle)、详细程度(detailLevel)、格式(formatPreference)、语气(tone)、视觉风格(visualPreference)。');
    staticBuf.writeln('用户提出规则/禁忌 → category=notice：沟通规则(communicationRules)、禁止事项(prohibitedItems)、其他要求(otherRequirements)。');
    staticBuf.writeln('长期兴趣爱好 → category=interest。短期/临时兴趣 → dynamic:shortTermInterests。');
    staticBuf.writeln('用户的知识背景 → category=dynamic key=knowledgeBackground。如"计算机专业""初中物理水平"。控制解释的技术深度。');
    staticBuf.writeln('用户的行为习惯 → category=dynamic key=behaviorHabits。如"每天早上查天气""喜欢先看结论再看细节"。');
    staticBuf.writeln('用户的当前身份 → category=dynamic key=currentIdentity（注意：这是用户的身份，不是你自己的）。如"大学生""创业者""后端工程师"。');
    staticBuf.writeln('nativeLanguage(母语)是 static 不可变的，usingLanguage(当前使用语言)是 dynamic 可变的。');
    staticBuf.writeln('不需要用户说"记住"——任何个人信息、偏好、约定都是记忆，主动存入。');
    staticBuf.writeln();

    staticBuf.writeln('【输出格式】');
    staticBuf.writeln('标题不加 emoji 前缀。状态用文字（已完成/待优化），不用符号。段落 2-3 句换行。');
    staticBuf.writeln();

    if (conciseMode) {
      staticBuf.writeln('【精简模式】');
      staticBuf.writeln('去掉客套话和问候语。给结论 + 要点。不要"当然可以""让我来帮你""希望这能帮到你"。');
      staticBuf.writeln();
    }

    staticBuf.writeln('【工具目录 — 全部始终可用，无需激活】');
    staticBuf.writeln('基础: 时间/天气/搜索/定位/反问用户');
    staticBuf.writeln('记忆: 查看/搜索/添加/删除用户记忆');
    staticBuf.writeln('文件: 读写/列出/移动/删除/搜索/索引');
    staticBuf.writeln('文档: 生成 Word/Excel/PPT/PDF/EPUB，格式转换');
    staticBuf.writeln('地图: 地点搜索/路线规划(驾车/公交/步行/骑行)/实时路况/静态图标注');
    staticBuf.writeln('浏览器: 网页操控/内容提取/截图/表单填写。含 browser_extract_design(提取参考站设计)→browser_load_html(渲染预览)');
    staticBuf.writeln('设计生成: generate_page。自由模式(freestyle:true)→无参考纯文字描述自动生成。参考模式(extraction)→先browser_extract_design提取参考站风格再传入。生成后必须browser_load_html预览+browser_screenshot截图');
    staticBuf.writeln('手机: 通讯录/日历/短信/电话/通知/悬浮窗/截屏');
    staticBuf.writeln('热搜: 各平台实时热搜榜单/话题分析');
    staticBuf.writeln('快递: 物流查询/订阅追踪/地图轨迹');
    staticBuf.writeln('定时: 定时提醒/任务管理');
    staticBuf.writeln('技能: 动态加载/卸载专业能力模块');
    staticBuf.writeln('编排: 复杂多步任务自动拆解并行执行');
    staticBuf.writeln();

    staticBuf.writeln(TrendTools.buildPlatformTable());

    blocks.add({
      'type': 'text',
      'text': staticBuf.toString(),
      'cache_control': {'type': 'ephemeral'},
    });

    // ── Block 2+: 动态内容（不缓存，追加在断点之后） ──

    final timeSection = _buildTimeSection();
    blocks.add({'type': 'text', 'text': timeSection});

    final memoryPrompt = await _buildMemorySection(messageQuery);
    if (memoryPrompt.isNotEmpty) {
      blocks.add({'type': 'text', 'text': memoryPrompt});
    }

    final behaviorSection = await _buildBehaviorSection();
    if (behaviorSection.isNotEmpty) {
      blocks.add({'type': 'text', 'text': behaviorSection});
    }

    if (safUri.isNotEmpty) {
      blocks.add({
        'type': 'text',
        'text': '【工作目录】$safUri\n文件 path 填相对路径。读不受限，写/删/生成仅在该目录内。',
      });
    }

    const homeUrl = 'https://cn.bing.com';
    final browserActive = browserUrl != null && browserUrl.isNotEmpty && browserUrl != 'about:blank' && browserUrl != homeUrl;
    if (browserActive) {
      final browserBuf = StringBuffer();
      browserBuf.writeln('【浏览器状态】');
      browserBuf.writeln('当前: ${browserTitle ?? '未知'} ($browserUrl)');
      if (browserTabCount > 1) {
        browserBuf.writeln('标签数: $browserTabCount');
      }
      browserBuf.writeln('可用 browser_get_content / browser_execute_js 交互。事实性内容用 browser_navigate 查证。');
      blocks.add({'type': 'text', 'text': browserBuf.toString()});
    }

    return blocks;
  }

  /// 将结构化 system content blocks 拍平为字符串（用于 lens 注入后的拼接等场景）
  static String flattenSystemContent(List<Map<String, dynamic>> blocks) {
    return blocks
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('\n');
  }

  // 构建系统提示词（扁平字符串，向后兼容旧版 sendMessageStream）
  Future<String> buildSystemPrompt({
    String? browserTitle,
    String? browserUrl,
    int browserTabCount = 0,
    String? messageQuery,
  }) async {
    final safUri = await getSafUri();
    final buffer = StringBuffer();

    // 当前时间
    final timeSection = _buildTimeSection();
    buffer.write(timeSection);
    buffer.writeln();

    // 核心身份
    buffer.writeln(defaultRole);
    buffer.writeln();

    // 规则
    buffer.writeln('【规则】');
    buffer.writeln('1. 说真话 — 拿不准就查（浏览器/工具/记忆）。查到用，查不到说"不确定"。数字、日期、URL 宁缺毋滥，编一个错的比承认不知道糟糕得多。');
    buffer.writeln('   来源标注：回答中涉及的事实，标注来源——[记忆]=用户画像，[查证]=浏览器/工具验证，没标=你自己知道的。');
    buffer.writeln('2. 说人话 — 微信怎么聊你就怎么回，别做客服做朋友。有立场不端水。不确定就说"不确定"。');
    buffer.writeln('3. 说到位 — 多问多答逐一回应，模糊就反问。多步任务做完再汇报。记住用户说过的偏好和话题，别回头又问。');
    buffer.writeln();

    // 输出格式
    buffer.writeln('【输出格式】');
    buffer.writeln('标题不加 emoji 前缀。状态用文字（已完成/待优化），不用符号。段落 2-3 句换行。');
    buffer.writeln();

    // 精简模式
    final conciseMode = await getConciseMode();
    if (conciseMode) {
      buffer.writeln('【精简模式】');
      buffer.writeln('去掉客套话和问候语。给结论 + 要点。不要"当然可以""让我来帮你""希望这能帮到你"。');
      buffer.writeln();
    }

    // 工具目录
    buffer.writeln('【工具目录】');
    buffer.writeln('basic（始终可用）: getCurrentTime, getWeather, webSearch, fetchUrl, ask, location_get, memory_change, memory_list, memory_search, memory_delete, city_policy_lookup');
    buffer.writeln('按需激活（activate_tools 叠加，-前缀移除，[] 重置）：');
    buffer.writeln('- trend: 热搜榜单');
    buffer.writeln('- map: 地图/导航/路况');
    buffer.writeln('- file: 文件读写/文档生成/索引');
    buffer.writeln('- phone: 通讯录/日历/短信/电话/通知/截屏');
    buffer.writeln('- cron: 定时任务');
    buffer.writeln('- browser: 浏览器操控');
    buffer.writeln('- express: 快递追踪');
    buffer.writeln('- train: 火车票查询');
    buffer.writeln('- generation: 页面生成');
    buffer.writeln();

    // 热搜平台参考表
    buffer.writeln(TrendTools.buildPlatformTable());

    // 用户记忆
    final memoryPrompt = await _buildMemorySection(messageQuery);
    if (memoryPrompt.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(memoryPrompt);
    }

    // 行为指令
    final behaviorSection = await _buildBehaviorSection();
    if (behaviorSection.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(behaviorSection);
    }

    // 工作目录
    if (safUri.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('【工作目录】$safUri');
      buffer.writeln('文件 path 填相对路径。读不受限，写/删/生成仅在该目录内。');
    }

    // 浏览器上下文
    const homeUrl = 'https://cn.bing.com';
    final browserActive = browserUrl != null && browserUrl.isNotEmpty && browserUrl != 'about:blank' && browserUrl != homeUrl;
    if (browserActive) {
      buffer.writeln();
      buffer.writeln('【浏览器状态】');
      buffer.writeln('当前: ${browserTitle ?? '未知'} ($browserUrl)');
      if (browserTabCount > 1) {
        buffer.writeln('标签数: $browserTabCount');
      }
      buffer.writeln('可用 browser_get_content / browser_execute_js 交互。事实性内容用 browser_navigate 查证。');
    }

    return buffer.toString();
  }

  /// 构建定时任务专用的系统提示词。
  /// 强调自主执行、不需要用户参与，工具可用（与主智能体同等能力）。
  Future<String> buildTaskSystemPrompt() async {
    final buffer = StringBuffer();

    // 当前时间
    final timeSection = _buildTimeSection();
    buffer.write(timeSection);
    buffer.writeln();

    buffer.writeln(defaultRole);
    buffer.writeln();
    buffer.writeln('【定时任务 — 自主执行模式】');
    buffer.writeln('你收到的是一个预设定的定时任务，将在你的控制下自动执行。');
    buffer.writeln('规则：');
    buffer.writeln('1. 自主判断并执行需要的步骤，不需要用户参与');
    buffer.writeln('2. 如果需要实时信息，优先使用专用工具（天气、搜索等）；无法使用工具时凭知识回答');
    buffer.writeln('3. 回复以结论为主，不需要汇报过程');
    buffer.writeln('4. 如果任务无法完成，说明原因即可');

    // 用户记忆
    final memoryPrompt = await _buildMemorySection();
    if (memoryPrompt.isNotEmpty) {
      buffer.writeln();
      buffer.write(memoryPrompt);
    }

    return buffer.toString();
  }

  /// 定时任务系统提示词（结构化，含 cache_control）
  Future<List<Map<String, dynamic>>> buildTaskSystemContent() async {
    final blocks = <Map<String, dynamic>>[];

    // 静态核心（cache_control 断点）
    final staticBuf = StringBuffer();
    staticBuf.writeln(defaultRole);
    staticBuf.writeln();
    staticBuf.writeln('【定时任务 — 自主执行模式】');
    staticBuf.writeln('你收到的是一个预设定的定时任务，将在你的控制下自动执行。');
    staticBuf.writeln('规则：');
    staticBuf.writeln('1. 自主判断并执行需要的步骤，不需要用户参与');
    staticBuf.writeln('2. 如果需要实时信息，优先使用专用工具（天气、搜索等）；无法使用工具时凭知识回答');
    staticBuf.writeln('3. 回复以结论为主，不需要汇报过程');
    staticBuf.writeln('4. 如果任务无法完成，说明原因即可');
    blocks.add({
      'type': 'text',
      'text': staticBuf.toString(),
      'cache_control': {'type': 'ephemeral'},
    });

    // 动态：时间 + 记忆
    blocks.add({'type': 'text', 'text': _buildTimeSection()});
    final memoryPrompt = await _buildMemorySection();
    if (memoryPrompt.isNotEmpty) {
      blocks.add({'type': 'text', 'text': memoryPrompt});
    }

    return blocks;
  }

  /// 包装定时任务消息为任务格式
  static String wrapTaskMessage(String title, String desc) {
    if (desc.isNotEmpty) {
      return '【定时任务】$title\n任务说明：$desc\n\n请执行此任务。';
    }
    return '【定时任务】$title\n\n请执行此任务。';
  }

  /// 构建热搜平台ID参考表，注入系统提示词。
  /// 模型调用 getTrendingTopics / searchTrendingTopics / getHistoricalTrends / analyzeTopic 时，
  /// platformIds 参数必须从下表中取 id（括号内为中文名，方便理解）。
  Future<String> _buildMemorySection([String? query]) async {
    try {
      final cache = MemoryCache.instance;
      await cache.load();
      final budget = MemoryBudgetController();

      if (query != null && query.isNotEmpty) {
        // 主路径：retrieveRelevant 多信号评分（含语义搜索），再按预算裁剪
        final relevant = await cache.retrieveRelevant(query, topK: 20);
        if (relevant.isNotEmpty) {
          final trimmed = budget.select(relevant);
          return _formatMemoryEntries(trimmed);
        }
      }

      // 降级：无 query 或 retrieveRelevant 为空 → 优先关键类别，再补最近记忆，按预算裁剪
      final all = List<MemoryEntry>.from(cache.allActive);
      final critical = <String>{'static', 'dynamic', 'preference', 'notice'};
      final priority = all.where((e) => critical.contains(e.category)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final rest = all.where((e) => !critical.contains(e.category)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final fallback = [...priority, ...rest].take(40).toList();
      if (fallback.isNotEmpty) {
        final trimmed = budget.select(fallback);
        return _formatMemoryEntries(trimmed);
      }

      return cache.toSystemPrompt(query ?? '');
    } catch (_) {
      return '';
    }
  }

  /// 将行为类记忆转译为显式的覆盖指令。
  ///
  /// 读取 [dynamic:agentName]、[dynamic:namePreference]、[preference:*]、[notice:*]
  /// 等关键记忆，输出直接的"你必须遵守"的指令，确保 AI 真正按用户设定的方式行动。
  Future<String> _buildBehaviorSection() async {
    try {
      final cache = MemoryCache.instance;
      await cache.load();

      final directives = <String>[];
      final notices = cache.getByType('notice');

      // ── 身份覆盖 ──
      final agentName = cache.get('dynamic', 'agentName');
      if (agentName != null && agentName.isNotEmpty) {
        directives.add('你的智能体名称是「$agentName」。所有自称（我、本助手等）统一用此名称。回答中的署名也用此名。');
      }

      final userTitle = cache.get('dynamic', 'userTitle');
      final namePref = cache.get('dynamic', 'namePreference');
      if (namePref != null && namePref.isNotEmpty) {
        final title = userTitle ?? '';
        final address = title.isNotEmpty ? '$title$namePref' : namePref;
        directives.add('【对用户的称呼】用户希望被你称为「$address」。注意：这是用户的名字，不是你（智能体）的名字。每次提到或称呼用户时用此称呼，不要用"用户""主人"等泛指。');
      } else if (userTitle != null && userTitle.isNotEmpty) {
        directives.add('对用户的尊称是「$userTitle」，在称呼用户时加上此尊称。');
      }

      // ── 风格偏好 ──
      final prefMap = cache.getByType('preference');
      if (prefMap.containsKey('answerStyle') && prefMap['answerStyle']!.isNotEmpty) {
        final v = prefMap['answerStyle']!;
        directives.add('回答风格偏好：「$v」——你的回复必须符合此风格，这是用户明确要求的。');
      }
      if (prefMap.containsKey('detailLevel') && prefMap['detailLevel']!.isNotEmpty) {
        final v = prefMap['detailLevel']!;
        directives.add('内容详细程度：「$v」。例如"详细"意味着充分展开说明，"简洁"意味着只给结论。');
      }
      if (prefMap.containsKey('formatPreference') && prefMap['formatPreference']!.isNotEmpty) {
        final v = prefMap['formatPreference']!;
        directives.add('输出格式偏好：「$v」。优先使用此格式组织回答。');
      }
      if (prefMap.containsKey('tone') && prefMap['tone']!.isNotEmpty) {
        final v = prefMap['tone']!;
        directives.add('语气风格：「$v」——所有对话遵循此语气。');
      }
      if (prefMap.containsKey('visualPreference') && prefMap['visualPreference']!.isNotEmpty) {
        final v = prefMap['visualPreference']!;
        directives.add('视觉风格偏好：「$v」——生成页面/图表/PPT 等视觉内容时优先使用此风格。');
      }

      // ── 规则/禁忌（notice 类型全部转译） ──
      for (final entry in notices.entries) {
        final label = switch (entry.key) {
          'communicationRules' => '沟通规则',
          'prohibitedItems' => '禁止事项',
          'otherRequirements' => '其他要求',
          String k => k,
        };
        directives.add('$label：${entry.value}');
      }

      // ── 动态画像中可影响行为的字段 ──
      final usingLang = cache.get('dynamic', 'usingLanguage');
      if (usingLang != null && usingLang.isNotEmpty) {
        directives.add('用户当前使用的语言是「$usingLang」。用此语言回复用户。');
      }
      final currentId = cache.get('dynamic', 'currentIdentity');
      if (currentId != null && currentId.isNotEmpty) {
        directives.add('用户当前身份：$currentId。根据此身份调整回答的视角和专业程度。');
      }
      final habits = cache.get('dynamic', 'behaviorHabits');
      if (habits != null && habits.isNotEmpty) {
        directives.add('用户行为习惯：$habits。考虑此习惯来安排互动方式。');
      }
      final shortGoals = cache.get('dynamic', 'shortTermGoals');
      if (shortGoals != null && shortGoals.isNotEmpty) {
        directives.add('用户短期目标：$shortGoals。主动帮助用户推进此目标。');
      }
      final shortInterests = cache.get('dynamic', 'shortTermInterests');
      if (shortInterests != null && shortInterests.isNotEmpty) {
        directives.add('用户当前兴趣：$shortInterests。可以围绕此兴趣提供信息和建议。');
      }
      final knowledge = cache.get('dynamic', 'knowledgeBackground');
      if (knowledge != null && knowledge.isNotEmpty) {
        directives.add('用户知识背景：$knowledge。据此调整解释的技术深度。');
      }

      if (directives.isEmpty) return '';

      final buf = StringBuffer();
      buf.writeln('【行为配置 — 动态指令】');
      buf.writeln('以下指令基于用户设定的记忆生成，你必须严格遵守，覆盖所有默认行为：');
      for (final d in directives) {
        buf.writeln('- $d');
      }
      buf.writeln();
      buf.writeln('用户随时可以修改以上任何设置。当用户更改时，立即更新记忆并遵循新指令。');
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  /// 将 MemoryRetriever 返回的记忆列表格式化为系统提示。
  String _formatMemoryEntries(List<MemoryEntry> entries) {
    if (entries.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('【用户记忆】');

    for (final mem in entries) {
      final age = DateTime.now().difference(mem.createdAt);
      final ageStr = age.inDays > 30
          ? '${age.inDays ~/ 30}月前'
          : age.inDays > 0
              ? '${age.inDays}天前'
              : '今天';
      buf.writeln('  - [$ageStr][${mem.confidence}] ${mem.content}');
    }

    buf.writeln();
    return buf.toString();
  }

  /// 快速放过：只过滤纯寒暄/闲聊/代码/文件操作，其余全部注入选路规则
  static bool _mightNeedNetworkTools(String? message) {
    if (message == null || message.isEmpty) return false;
    final m = message.trim();
    // 长度 > 30 或包含问号 → 大概率有实质需求，直接放过
    if (m.length > 30 || m.contains('？') || m.contains('?')) return true;
    // URL 特征 → 放过
    if (RegExp(r'https?://|www\.').hasMatch(m)) return true;
    // 纯寒暄/语气词 → 过滤（很短且无实质内容）
    if (RegExp(r'^[你好呀啊嗯哦嗨哈谢拜再见早晚安]+[!！。.]*$').hasMatch(m)) return false;
    return true; // 其余全部放过
  }

  // ===== Safety Profile =====

  static const _safetyProfileKey = 'safety_profile';
  static const _enabledSkillsKey = 'enabled_skills';

  Future<SafetyProfile> getSafetyProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_safetyProfileKey) ?? 'standard';
    return SafetyProfile.values.firstWhere(
      (p) => p.name == name,
      orElse: () => SafetyProfile.standard,
    );
  }

  Future<void> setSafetyProfile(SafetyProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_safetyProfileKey, profile.name);
  }

  Future<List<String>> getEnabledSkillNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_enabledSkillsKey) ?? '';
    if (raw.isEmpty) return const ['FlutterHelper', 'document-analysis'];
    return raw.split(',').where((s) => s.isNotEmpty).toList();
  }

  Future<void> setEnabledSkillNames(List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_enabledSkillsKey, names.join(','));
  }

  /// 风险评审阈值（根据当前 SafetyProfile）
  Future<double> getRiskReviewThreshold() async {
    final profile = await getSafetyProfile();
    switch (profile) {
      case SafetyProfile.safe: return 0.25;
      case SafetyProfile.standard: return 0.35;
      case SafetyProfile.permissive: return 0.60;
    }
  }

  Future<double> getRiskConfirmThreshold() async {
    final profile = await getSafetyProfile();
    switch (profile) {
      case SafetyProfile.safe: return 0.40;
      case SafetyProfile.standard: return 0.60;
      case SafetyProfile.permissive: return 0.85;
    }
  }

  Future<double> getRiskBlockThreshold() async {
    final profile = await getSafetyProfile();
    switch (profile) {
      case SafetyProfile.safe: return 0.60;
      case SafetyProfile.standard: return 0.85;
      case SafetyProfile.permissive: return 0.95;
    }
  }

  // ── TTS 播报 ──

  Future<String> getTtsModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ttsModelKey) ?? 'speech-2.8-hd';
  }
  Future<void> setTtsModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ttsModelKey, model);
  }

  Future<String> getTtsVoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ttsVoiceKey) ?? 'female-qn-qingse';
  }
  Future<void> setTtsVoice(String voice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ttsVoiceKey, voice);
  }

  Future<bool> getTtsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ttsEnabledKey) ?? false;
  }
  Future<void> setTtsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ttsEnabledKey, enabled);
  }

  // ── 头像 ──

  Future<String> getUserAvatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userAvatarKey) ?? '';
  }

  Future<void> setUserAvatarPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path.isEmpty) {
      await prefs.remove(_userAvatarKey);
    } else {
      await prefs.setString(_userAvatarKey, path);
    }
  }

  Future<String> getAgentAvatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_agentAvatarKey) ?? '';
  }

  Future<void> setAgentAvatarPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path.isEmpty) {
      await prefs.remove(_agentAvatarKey);
    } else {
      await prefs.setString(_agentAvatarKey, path);
    }
  }

  // ── 热点趋势 ──

  static const _trendsKeywordsKey = 'trends_keywords';

  Future<String> getTrendsKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_trendsKeywordsKey) ?? '';
  }

  Future<void> setTrendsKeywords(String content) async {
    final prefs = await SharedPreferences.getInstance();
    if (content.isEmpty) {
      await prefs.remove(_trendsKeywordsKey);
    } else {
      await prefs.setString(_trendsKeywordsKey, content);
    }
  }

  // ── MCP 服务器手动配置 ──

  Future<List<Map<String, dynamic>>> getMcpServersConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mcpServersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addMcpServer(Map<String, dynamic> server) async {
    final servers = await getMcpServersConfig();
    final existingIndex = servers.indexWhere((s) => s['name'] == server['name']);
    if (existingIndex >= 0) {
      servers[existingIndex] = server;
    } else {
      servers.add(server);
    }
    await _saveMcpServers(servers);
  }

  Future<void> removeMcpServer(String name) async {
    final servers = await getMcpServersConfig();
    servers.removeWhere((s) => s['name'] == name);
    await _saveMcpServers(servers);
  }

  Future<void> _saveMcpServers(List<Map<String, dynamic>> servers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mcpServersKey, jsonEncode(servers));
  }
}
