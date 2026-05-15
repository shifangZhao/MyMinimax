import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../app/theme.dart';
import '../../../app/app.dart' show navigationIndexProvider, quotaInfoProvider;
import '../../../shared/utils/snackbar_utils.dart';
import '../../../shared/widgets/model_dropdown.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/error_card.dart';
import '../../../shared/widgets/settings_warning_card.dart';
import '../../../shared/widgets/generate_button.dart';
import '../../../shared/widgets/expandable_card.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/api/minimax_client.dart';
import '../../chat/presentation/chat_page.dart' show minimaxClientProvider, settingsChangedProvider;
import '../../settings/data/settings_repository.dart';
import '../domain/speech_history_item.dart';
import '../data/speech_history_repository.dart';
import 'tts_settings_page.dart';

class SpeechPage extends ConsumerStatefulWidget {
  const SpeechPage({super.key});
  @override
  ConsumerState<SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends ConsumerState<SpeechPage> {
  final _textController = TextEditingController(text: '欢迎使用 MiniMax AI助手');
  String _selectedVoice = 'female-qn-qingse';
  static const _speechModels = ['speech-2.8-hd', 'speech-2.8-turbo', 'speech-2.6-hd', 'speech-2.6-turbo', 'speech-02-hd', 'speech-02-turbo'];
  String _selectedModel = _speechModels.first;
  double _speed = 1.0;
  bool _isLoading = false;
  bool _isConfigured = false;
  bool _isLoadingVoices = false;
  String? _audioUrl;
  String? _error;
  String _asyncStatus = ''; // 异步任务状态提示
  List<VoiceInfo> _voiceList = [];
  List<VoiceInfo> _filteredVoices = [];
  List<VoiceInfo> _chineseVoices = [];
  List<VoiceInfo> _englishVoices = [];
  List<VoiceInfo> _clonedVoices = [];
  List<VoiceInfo> _generatedVoices = [];
  bool _cloningExpanded = false;
  bool _isUploadingClone = false;
  String? _cloneVoiceFileId;
  bool _isUploadingPrompt = false;
  String? _promptAudioFileId;
  bool _isCloning = false;
  final _voiceIdController = TextEditingController();
  final _promptTextController = TextEditingController();
  String? _clonedVoiceId;
  String? _demoAudioUrl;
  bool _isDesigning = false;
  bool _designingExpanded = false;
  final _designPromptController = TextEditingController();
  final _designPreviewTextController = TextEditingController();
  String? _designedVoiceId;
  String? _designedTrialAudioHex;

  // 历史记录
  final _historyRepo = SpeechHistoryRepository();
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  List<SpeechHistoryItem> _history = [];
  String? _editingHistoryId;
  String? _localAudioPath;

  @override
  void initState() {
    super.initState();
    _checkConfigured();
    _loadHistory();
  }

  @override
  void dispose() {
    _textController.dispose();
    _voiceIdController.dispose();
    _promptTextController.dispose();
    _designPromptController.dispose();
    _designPreviewTextController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await _historyRepo.getHistory();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _checkConfigured() async {
    final settings = SettingsRepository();
    final configured = await settings.isConfigured();
    if (mounted) {
      setState(() => _isConfigured = configured);
      if (configured) _loadVoices();
    }
  }

  void _onModelChanged(String model) => setState(() => _selectedModel = model);
  void _onVoiceSelected(String voiceId) => setState(() => _selectedVoice = voiceId);
  void _toggleCloningExpanded() => setState(() => _cloningExpanded = !_cloningExpanded);
  void _toggleDesigningExpanded() => setState(() => _designingExpanded = !_designingExpanded);

  Future<void> _loadVoices() async {
    setState(() => _isLoadingVoices = true);
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final result = await client.getVoiceListAll();
      if (mounted) {
        final allVoices = result.allVoices;
        final chinese = allVoices.where((v) => RegExp(r'[一-鿿]').hasMatch(v.voiceName)).toList();
        final english = allVoices.where((v) => !RegExp(r'[一-鿿]').hasMatch(v.voiceName)).toList();
        setState(() {_voiceList = allVoices; _chineseVoices = chinese; _englishVoices = english; _clonedVoices = result.clonedVoices; _generatedVoices = result.generatedVoices; _filteredVoices = allVoices;});
      }
    } catch (e, stack) {
      debugPrint('Voice load error: $e\n$stack');
    } finally {
      if (mounted) setState(() => _isLoadingVoices = false);
    }
  }

  Future<void> _uploadCloneVoice() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'm4a', 'wav']);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;
      setState(() => _isUploadingClone = true);
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final fileId = await client.uploadCloneVoiceAudio(file.path!);
      if (mounted) setState(() {_cloneVoiceFileId = fileId; _isUploadingClone = false;});
    } catch (e) {
      print('[speech] error: \$e');
      if (mounted) setState(() => _isUploadingClone = false);
      showSnackBar(context, '上传失败: $e', isError: true);
    }
  }

  Future<void> _uploadPromptAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'm4a', 'wav']);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;
      setState(() => _isUploadingPrompt = true);
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final fileId = await client.uploadPromptAudio(file.path!);
      if (mounted) setState(() {_promptAudioFileId = fileId; _isUploadingPrompt = false;});
    } catch (e) {
      print('[speech] error: \$e');
      if (mounted) setState(() => _isUploadingPrompt = false);
      showSnackBar(context, '上传失败: $e', isError: true);
    }
  }

  Future<void> _startVoiceClone() async {
    if (_cloneVoiceFileId == null || _voiceIdController.text.isEmpty) return;
    setState(() => _isCloning = true);
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final result = await client.voiceClone(fileId: _cloneVoiceFileId!, voiceId: _voiceIdController.text.trim(), promptAudioFileId: _promptAudioFileId, promptText: _promptTextController.text.trim().isNotEmpty ? _promptTextController.text.trim() : null, model: _selectedModel);
      if (mounted) setState(() {_clonedVoiceId = _voiceIdController.text.trim(); _demoAudioUrl = result.demoAudioUrl; _isCloning = false;});
    } catch (e) {
      print('[speech] error: \$e');
      if (mounted) setState(() => _isCloning = false);
      showSnackBar(context, '复刻失败: $e', isError: true);
    }
  }

  Future<void> _startVoiceDesign() async {
    if (_designPromptController.text.isEmpty || _designPreviewTextController.text.isEmpty) return;
    setState(() => _isDesigning = true);
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final result = await client.voiceDesign(prompt: _designPromptController.text.trim(), previewText: _designPreviewTextController.text.trim());
      if (mounted) setState(() {_designedVoiceId = result.voiceId; _designedTrialAudioHex = result.trialAudioHex; _isDesigning = false;});
    } catch (e) {
      print('[speech] error: \$e');
      if (mounted) setState(() => _isDesigning = false);
      showSnackBar(context, '设计失败: $e', isError: true);
    }
  }

  void _editHistoryItem(SpeechHistoryItem item) {
    _textController.text = item.text;
    setState(() {
      _selectedVoice = item.voiceId;
      _selectedModel = item.model;
      _speed = item.speed;
      _editingHistoryId = item.id;
      _audioUrl = null;
      _localAudioPath = null;
      _error = null;
    });
  }

  Future<void> _deleteHistoryItem(SpeechHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除语音'),
        content: Text('确定删除 "${item.shortText}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: PixelTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _historyRepo.deleteFromHistory(item.id);
    await _loadHistory();
    if (_editingHistoryId == item.id) {
      setState(() => _editingHistoryId = null);
    }
  }

  Future<void> _deleteVoice(VoiceInfo voice) async {
    final isCloned = _clonedVoices.any((v) => v.voiceId == voice.voiceId);
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('删除音色'), content: Text('确定删除音色 "${voice.voiceName}" 吗？删除后无法恢复。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: PixelTheme.error)))]));
    if (confirmed != true) return;
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      await client.deleteVoice(voice.voiceId, isCloned ? 'voice_cloning' : 'voice_generation');
      await _loadVoices();
    } catch (e) {
      print('[speech] error: \$e');
      if (mounted) showSnackBar(context, '删除失败: $e', isError: true);
    }
  }

  Future<void> _synthesize() async {
    if (!_isConfigured) {showSnackBar(context, '请先在设置中配置 API Key', isError: true); return;}
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_selectedVoice.isEmpty) {showSnackBar(context, '请选择一个音色', isError: true); return;}
    setState(() {_isLoading = true; _error = null; _audioUrl = null; _localAudioPath = null; _asyncStatus = '创建异步任务...';});
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);

      // 1. 创建异步任务
      final result = await client.speechSynthesizeAsync(
        text: text,
        model: _selectedModel,
        voiceId: _selectedVoice,
        speed: _speed,
      );
      if (mounted) setState(() => _asyncStatus = '任务已创建，处理中...');

      // 2. 轮询直到完成
      String? downloadUrl;
      const maxPolls = 150; // 最多等 5 分钟
      for (var i = 0; i < maxPolls; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final status = await client.getSpeechAsyncTaskStatus(result.taskId);

        if (status.isFailed) {
          throw MinimaxApiException('Speech synthesis task failed / 语音合成任务失败', statusCode: -1);
        }
        if (status.isExpired) {
          throw MinimaxApiException('Speech synthesis task expired / 语音合成任务已过期', statusCode: -1);
        }
        if (status.isSuccess) {
          if (mounted) setState(() => _asyncStatus = 'Downloading audio... / 下载音频中...');

          if (status.fileId != null) {
            final file = await client.downloadFile(status.fileId!);
            downloadUrl = file.downloadUrl;
          } else if (result.fileId != null) {
            final file = await client.downloadFile(result.fileId!);
            downloadUrl = file.downloadUrl;
          }

          if (downloadUrl == null || downloadUrl.isEmpty) {
            throw MinimaxApiException('Unable to get audio download link / 无法获取音频下载链接', statusCode: -1);
          }
          break;
        }
        // Processing: continue polling / 继续轮询
        if (mounted && i % 5 == 0) {
          setState(() => _asyncStatus = 'Processing... / 处理中... (${(i * 2) ~/ 60}m${(i * 2) % 60}s)');
        }
      }

      if (downloadUrl == null) {
        throw MinimaxApiException('Speech synthesis timeout, please retry / 语音合成超时，请重试', statusCode: -1);
      }

      // 3. 下载音频到本地
      final dio = Dio();
      final response = await dio.get(downloadUrl, options: Options(responseType: ResponseType.bytes));
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'speech_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(response.data is Uint8List ? response.data : Uint8List.fromList(List<int>.from(response.data)));
      final localPath = file.path;

      if (mounted) setState(() => _asyncStatus = '完成');

      // 查找音色名称
      final voiceName = _voiceList.where((v) => v.voiceId == _selectedVoice).firstOrNull?.voiceName ?? _selectedVoice;

      // 持久化保存
      await _historyRepo.addToHistory(
        text: text,
        voiceId: _selectedVoice,
        voiceName: voiceName,
        model: _selectedModel,
        speed: _speed,
        audioUrl: localPath,
      );
      await _loadHistory();

      if (mounted) {
        setState(() {
          _audioUrl = downloadUrl;
          _localAudioPath = localPath;
          _editingHistoryId = null;
          _asyncStatus = '';
        });
      }
    } catch (e) {
      print('[speech] error: \$e');
      if (mounted) setState(() { _error = e.toString(); _asyncStatus = ''; });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    _refreshQuota();
  }

  /// 刷新 token 配额
  Future<void> _refreshQuota() async {
    try {
      final settings = SettingsRepository();
      final apiKey = await settings.getActiveApiKey();
      if (apiKey.isEmpty) return;

      final baseUrl = await settings.getBaseUrl();
      final client = MinimaxClient(apiKey: apiKey, baseUrl: baseUrl);
      final quota = await client.getQuota();
      if (mounted) {
        ref.read(quotaInfoProvider.notifier).setQuota(quota);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsChangedProvider, (prev, next) => _checkConfigured());
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          PageHeader(icon: Icons.mic_outlined, title: ref.watch(i18nProvider)?.t('speech.title') ?? '语音合成'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!_isConfigured)
                  SettingsWarningCard(onNavigateToSettings: () => ref.read(navigationIndexProvider.notifier).state = 4),
                _buildModelCard(),
                const SizedBox(height: 16),
                _buildTextCard(),
                const SizedBox(height: 16),
                _buildVoiceCard(),
                const SizedBox(height: 16),
                _buildCloningCard(),
                const SizedBox(height: 16),
                _buildDesignCard(),
                const SizedBox(height: 16),
                GenerateButton(
                  label: '开始合成',
                  icon: Icons.volume_up,
                  onPressed: _synthesize,
                  isLoading: _isLoading,
                ),
                if (_asyncStatus.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ModernCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_asyncStatus, style: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary))),
                    ]),
                  ),
                ],
                if (_error != null) ...[const SizedBox(height: 16), ErrorCard(message: _error!)],
                if (_history.isNotEmpty) ...[const SizedBox(height: 28), _buildHistorySection()],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildModelCard() {
    return ModernCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ModelDropdown(
          label: '选择模型',
          selectedModel: _selectedModel,
          models: _speechModels,
          modelDescriptions: const {
            'speech-2.8-hd': '高清语音，2.8版本',
            'speech-2.8-turbo': '快速语音，2.8版本',
            'speech-2.6-hd': '高清语音，2.6版本',
            'speech-2.6-turbo': '快速语音，2.6版本',
            'speech-02-hd': '语音02 高清版',
            'speech-02-turbo': '语音02 快速版',
          },
          onChanged: _onModelChanged,
        ),
      ]),
    );
  }

  Widget _buildTextCard() {
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    return ModernCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle(title: '合成文本'),
        const SizedBox(height: 10),
        TextField(controller: _textController, minLines: 1, maxLines: 6, style: TextStyle(fontSize: 14, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary), decoration: InputDecoration(hintText: '输入要转换为语音的文本...', hintStyle: TextStyle(color: textMuted), border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusMd)))),
      ]),
    );
  }

  Widget _buildVoiceCard() {
    final textSecondary = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    return ModernCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle(title: '音色选择'),
        const SizedBox(height: 12),
        if (_isLoadingVoices)
          Center(child: CircularProgressIndicator(strokeWidth: 2, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary))
        else if (_filteredVoices.isEmpty)
          Text('无法加载音色列表，使用默认值', style: TextStyle(fontSize: 12, color: textSecondary))
        else ...[
          if (_chineseVoices.isNotEmpty) _buildVoiceSection('中文', _chineseVoices),
          if (_chineseVoices.isNotEmpty && _englishVoices.isNotEmpty) const SizedBox(height: 8),
          if (_englishVoices.isNotEmpty) _buildVoiceSection('英文', _englishVoices),
          if (_clonedVoices.isNotEmpty) ...[const SizedBox(height: 8), _buildVoiceSection('复刻音色', _clonedVoices, deletable: true)],
          if (_generatedVoices.isNotEmpty) ...[const SizedBox(height: 8), _buildVoiceSection('AI 音色', _generatedVoices)],
        ],
        if (_clonedVoiceId != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: PixelTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(PixelTheme.radiusSm)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.check_circle, size: 16, color: PixelTheme.success),
                const SizedBox(width: 8),
                Expanded(child: Text('复刻成功: $_clonedVoiceId', style: TextStyle(fontSize: 12, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary))),
              ]),
              if (_demoAudioUrl != null && _demoAudioUrl!.isNotEmpty) ...[const SizedBox(height: 8), SelectableText('试听音频: $_demoAudioUrl', style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary))],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildCloningCard() {
    final secondaryTextColor = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    return ExpandableCard(
      expanded: _cloningExpanded,
      onToggle: _toggleCloningExpanded,
      header: Row(children: [
        Icon(Icons.content_copy, size: 18, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
        const SizedBox(width: 8),
        Text('音色复刻', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
      ]),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('1. 上传复刻音频（10秒-5分钟，mp3/m4a/wav，最大20MB）', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
        const SizedBox(height: 8),
        if (_cloneVoiceFileId != null)
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: PixelTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(PixelTheme.radiusSm)), child: Row(children: [const Icon(Icons.check_circle, size: 16, color: PixelTheme.success), const SizedBox(width: 8), Expanded(child: Text('已上传: $_cloneVoiceFileId', style: const TextStyle(fontSize: 12, color: PixelTheme.success))), TextButton(onPressed: () => setState(() => _cloneVoiceFileId = null), child: const Text('清除', style: TextStyle(fontSize: 12)))]))
        else
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _isUploadingClone ? null : _uploadCloneVoice, icon: _isUploadingClone ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file, size: 18), label: Text(_isUploadingClone ? '上传中...' : '上传复刻音频'), style: OutlinedButton.styleFrom(foregroundColor: PixelTheme.primary, side: const BorderSide(color: PixelTheme.primary), padding: const EdgeInsets.symmetric(vertical: 12)))),
        const SizedBox(height: 16),
        Text('2. 上传示例音频（<8秒，mp3/m4a/wav，最大20MB）可提升相似度', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
        const SizedBox(height: 8),
        if (_promptAudioFileId != null)
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: PixelTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(PixelTheme.radiusSm)), child: Row(children: [const Icon(Icons.check_circle, size: 16, color: PixelTheme.success), const SizedBox(width: 8), Expanded(child: Text('已上传: $_promptAudioFileId', style: const TextStyle(fontSize: 12, color: PixelTheme.success))), TextButton(onPressed: () => setState(() => _promptAudioFileId = null), child: const Text('清除', style: TextStyle(fontSize: 12)))]))
        else
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _isUploadingPrompt ? null : _uploadPromptAudio, icon: _isUploadingPrompt ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file, size: 18), label: Text(_isUploadingPrompt ? '上传中...' : '上传示例音频'), style: OutlinedButton.styleFrom(foregroundColor: PixelTheme.primary, side: const BorderSide(color: PixelTheme.primary), padding: const EdgeInsets.symmetric(vertical: 12)))),
        const SizedBox(height: 16),
        Text('3. 开始复刻', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
        const SizedBox(height: 8),
        TextField(controller: _voiceIdController, style: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary), decoration: InputDecoration(hintText: '自定义音色ID（8-256字符，首字符为字母）', hintStyle: TextStyle(color: textMuted, fontSize: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusSm)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
        const SizedBox(height: 8),
        TextField(controller: _promptTextController, style: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary), maxLines: 2, decoration: InputDecoration(hintText: '示例文本（可选，示例音频对应的文字）', hintStyle: TextStyle(color: textMuted, fontSize: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusSm)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: GradientButton(onPressed: (_cloneVoiceFileId != null && _voiceIdController.text.isNotEmpty && !_isCloning) ? _startVoiceClone : null, isLoading: _isCloning, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_isCloning ? Icons.hourglass_empty : Icons.content_copy, color: Colors.white, size: 18), const SizedBox(width: 8), Text(_isCloning ? '复刻中...' : '开始复刻')]))),
      ]),
    );
  }

  Widget _buildDesignCard() {
    final secondaryTextColor = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    return ExpandableCard(
      expanded: _designingExpanded,
      onToggle: _toggleDesigningExpanded,
      header: Row(children: [
        Icon(Icons.auto_awesome, size: 18, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
        const SizedBox(width: 8),
        Text('AI音色设计', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
      ]),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('描述想要的音色特征', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
        const SizedBox(height: 8),
        TextField(controller: _designPromptController, style: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary), decoration: InputDecoration(hintText: '例如：温柔的年轻女性声音', hintStyle: TextStyle(color: textMuted, fontSize: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusSm)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
        const SizedBox(height: 8),
        TextField(controller: _designPreviewTextController, style: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary), decoration: InputDecoration(hintText: '预览文本', hintStyle: TextStyle(color: textMuted, fontSize: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusSm)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: GradientButton(onPressed: (_designPromptController.text.isNotEmpty && _designPreviewTextController.text.isNotEmpty && !_isDesigning) ? _startVoiceDesign : null, isLoading: _isDesigning, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_isDesigning ? Icons.hourglass_empty : Icons.auto_awesome, color: Colors.white, size: 18), const SizedBox(width: 8), Text(_isDesigning ? '设计中...' : '开始设计')]))),
      ]),
    );
  }

  Widget _buildVoiceSection(String title, List<VoiceInfo> voices, {bool deletable = false}) {
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final primaryColor = _isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    final selected = voices.where((v) => v.voiceId == _selectedVoice).firstOrNull;
    final selectedName = selected?.voiceName ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
      onTap: () => _showVoicePicker(title, voices, deletable: deletable),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: _isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textPrimary)),
          const SizedBox(width: 8),
          Text('(${voices.length})', style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
          const Spacer(),
          Flexible(child: Text(selectedName, style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 16, color: _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
        ]),
      ),
    );
  }

  void _showVoicePicker(String title, List<VoiceInfo> voices, {bool deletable = false}) {
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final textSecondary = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (ctx, scrollController) => Column(children: [
            // 手柄
            Container(margin: const EdgeInsets.only(top: 10), width: 36, height: 4, decoration: BoxDecoration(color: _isDark ? PixelTheme.darkBorderDefault : Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary)),
            ),
            // 搜索
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                autofocus: true,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: InputDecoration(
                  hintText: '搜索音色...',
                  hintStyle: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                  prefixIcon: Icon(Icons.search, size: 20, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                  filled: true,
                  fillColor: _isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => setSheetState(() => searchQuery = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: voices.length,
                itemBuilder: (_, i) {
                  final v = voices[i];
                  if (searchQuery.isNotEmpty && !v.voiceName.toLowerCase().contains(searchQuery.toLowerCase())) {
                    return const SizedBox.shrink();
                  }
                  final isSelected = _selectedVoice == v.voiceId;
                  return ListTile(
                    dense: true,
                    leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, size: 20, color: isSelected ? (_isDark ? PixelTheme.darkPrimary : PixelTheme.primary) : textSecondary),
                    title: Text(v.voiceName, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? (_isDark ? PixelTheme.darkPrimary : PixelTheme.primary) : textPrimary)),
                    subtitle: Text(v.voiceId, style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
                    trailing: deletable ? IconButton(icon: Icon(Icons.close, size: 16, color: textSecondary), onPressed: () { _deleteVoice(v); Navigator.pop(ctx); }) : null,
                    onTap: () {
                      _onVoiceSelected(v.voiceId);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }


  Widget _buildResultCard() {
    final voiceName = _voiceList.where((v) => v.voiceId == _selectedVoice).firstOrNull?.voiceName ?? _selectedVoice;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ModernCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部：音色 + 倍速 + 模型
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(voiceName, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${_speed}x  ·  $_selectedModel', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          // 微信风格的语音播放条
          _VoiceMessageBar(
            audioUrl: _audioUrl,
            localPath: _localAudioPath,
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          // 底部操作
          Row(children: [
            _buildActionChip(Icons.edit_outlined, '编辑', () => _editHistoryItem(SpeechHistoryItem(
              id: _editingHistoryId ?? '',
              text: _textController.text.trim(),
              voiceId: _selectedVoice,
              voiceName: voiceName,
              model: _selectedModel,
              speed: _speed,
              audioUrl: _audioUrl!,
              createdAt: DateTime.now(),
            )), isDark),
            const Spacer(),
            _buildActionChip(Icons.replay, '重新合成', () {
              _synthesize();
            }, isDark),
          ]),
        ],
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: isDark ? PixelTheme.darkSecondary : PixelTheme.secondary),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText)),
      ]),
    );
  }

  Widget _buildActionChip(IconData icon, String label, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary)),
        ]),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle(title: '历史记录'),
      const SizedBox(height: 12),
      ...List.generate(_history.length, (i) {
        final item = _history[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i < _history.length - 1 ? 10 : 0),
          child: _buildHistoryCard(item),
        );
      }),
    ]);
  }

  Widget _buildHistoryCard(SpeechHistoryItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 需要下载到本地才能用 _VoiceMessageBar 播放
    final localPath = item.audioUrl;
    return ModernCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.shortText,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText)),
                const SizedBox(height: 4),
                Row(children: [
                  _buildMetaChip(Icons.record_voice_over, item.voiceName.isNotEmpty ? item.voiceName : item.voiceId, isDark),
                  const SizedBox(width: 6),
                  Text(item.formattedDate, style: TextStyle(fontSize: 10, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
                ]),
              ]),
            ),
            GestureDetector(
              onTap: () => _deleteHistoryItem(item),
              child: Icon(Icons.delete_outline, size: 16, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
            ),
          ]),
          const SizedBox(height: 10),
          _VoiceMessageBar(
            audioUrl: item.audioUrl,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

// ─── 微信风格语音消息条 ──────────────────────────────────────────

class _VoiceMessageBar extends StatefulWidget {

  const _VoiceMessageBar({required this.isDark, this.audioUrl, this.localPath});
  final String? audioUrl;
  final String? localPath;
  final bool isDark;

  @override
  State<_VoiceMessageBar> createState() => _VoiceMessageBarState();
}

class _VoiceMessageBarState extends State<_VoiceMessageBar>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _posSub, _stateSub, _durSub;
  late AnimationController _waveAnim;

  String? get _path => widget.localPath;
  String? get _url => widget.audioUrl;

  @override
  void initState() {
    super.initState();
    _waveAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _posSub = _player.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) { setState(() => _playerState = s); _syncWave(); }
    });
    _durSub = _player.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); });
  }

  void _syncWave() {
    if (_playerState == PlayerState.playing) {
      _waveAnim.repeat(reverse: true);
    } else {
      _waveAnim.stop(); _waveAnim.reset();
    }
  }

  @override
  void dispose() {
    _posSub?.cancel(); _stateSub?.cancel(); _durSub?.cancel();
    _waveAnim.dispose(); _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
      return;
    }

    // 优先用本地文件播放
    if (_path != null) {
      final file = File(_path!);
      if (await file.exists()) {
        await _player.play(DeviceFileSource(_path!));
        return;
      }
    }

    // 没有 path 但 url 是本地文件路径，也当本地文件播
    if (_url != null && _url!.isNotEmpty) {
      final file = File(_url!);
      if (await file.exists()) {
        await _player.play(DeviceFileSource(_url!));
        return;
      }
    }

    // 尝试从 URL 处理
    if (_url == null || _url!.isEmpty) return;

    final url = _url!;

    // data URL：解码保存为临时文件后播放
    if (url.startsWith('data:')) {
      try {
        final base64Data = url.split(',').last;
        final bytes = base64Decode(base64Data);
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/speech_tmp_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await file.writeAsBytes(bytes);
        await _player.play(DeviceFileSource(file.path));
      } catch (_) {}
      return;
    }

    // 相对路径：补全为完整 URL
    final fullUrl = (url.startsWith('/') || !url.startsWith('http'))
        ? 'https://api.minimax.chat$url'
        : url;

    try {
      await _player.play(UrlSource(fullUrl));
    } catch (_) {
      // UrlSource 失败时下载到本地再播放
      try {
        final dio = Dio();
        final response = await dio.get(fullUrl, options: Options(responseType: ResponseType.bytes));
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/speech_tmp_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await file.writeAsBytes(response.data is Uint8List ? response.data : Uint8List.fromList(List<int>.from(response.data)));
        await _player.play(DeviceFileSource(file.path));
      } catch (_) {}
    }
  }

  String _fmt(Duration d) {
    final m = d.inSeconds ~/ 60;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.isDark;
    final isPlaying = _playerState == PlayerState.playing;
    final accent = d ? PixelTheme.darkAccent : PixelTheme.accent;
    final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: isPlaying ? accent.withValues(alpha: 0.08) : (d ? PixelTheme.darkElevated : const Color(0xFFF8F9FB)),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isPlaying ? accent.withValues(alpha: 0.3) : (d ? PixelTheme.darkBorderSubtle : const Color(0xFFE5E7EB))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 32, height: 32,
            decoration: BoxDecoration(color: isPlaying ? accent : accent.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 18, color: isPlaying ? Colors.white : accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedBuilder(
              animation: _waveAnim,
              builder: (_, __) {
                return CustomPaint(
                  size: const Size(double.infinity, 24),
                  painter: _WaveformPainter(progress: progress, animValue: _waveAnim.value, isPlaying: isPlaying, accent: accent, isDark: d),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _duration.inMilliseconds > 0 ? _fmt(_duration) : '--:--',
            style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()], color: d ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
          ),
        ]),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {

  _WaveformPainter({required this.progress, required this.animValue, required this.isPlaying, required this.accent, required this.isDark});
  final double progress;
  final double animValue;
  final bool isPlaying;
  final Color accent;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const barCount = 24;
    final barWidth = size.width / (barCount * 2);
    final centerY = size.height / 2;
    final playedBars = (progress * barCount).round().clamp(0, barCount);

    for (var i = 0; i < barCount; i++) {
      final baseRatio = _envelope(i, barCount);
      final animBoost = isPlaying ? (0.3 * (1.0 - animValue) + 0.4 * animValue) * baseRatio : 0.0;
      final h = (baseRatio * 0.8 + animBoost) * size.height;
      final x = i * (barWidth * 2) + barWidth / 2;
      final r = Rect.fromCenter(center: Offset(x, centerY), width: barWidth * 0.8, height: h.clamp(2.0, size.height));
      paint.color = i < playedBars ? accent : accent.withValues(alpha: isDark ? 0.18 : 0.12);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), paint);
    }
  }

  double _envelope(int i, int total) {
    final x = (i - total / 2).abs() / (total / 2);
    final variation = (i % 3 == 0) ? 0.7 : (i % 5 == 0) ? 1.3 : 1.0;
    return (0.25 + (1.0 - x) * 0.75) * variation;
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      progress != old.progress || animValue != old.animValue || isPlaying != old.isPlaying;
}
