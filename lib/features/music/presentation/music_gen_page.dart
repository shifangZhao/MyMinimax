import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../app/theme.dart';
import '../../../app/app.dart' show navigationIndexProvider, quotaInfoProvider, MinimaxClient;
import '../../../shared/utils/snackbar_utils.dart';
import '../../../shared/widgets/audio_player.dart';
import '../../../shared/widgets/model_dropdown.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/error_card.dart';
import '../../../shared/widgets/settings_warning_card.dart';
import '../../../shared/widgets/generate_button.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../chat/presentation/chat_page.dart' show minimaxClientProvider, settingsChangedProvider;
import '../../settings/data/settings_repository.dart';
import '../domain/music_history_item.dart';
import '../data/music_history_repository.dart';

class MusicGenPage extends ConsumerStatefulWidget {
  const MusicGenPage({super.key});
  @override
  ConsumerState<MusicGenPage> createState() => _MusicGenPageState();
}

class _MusicGenPageState extends ConsumerState<MusicGenPage> {
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  final _promptController = TextEditingController();
  final _lyricsController = TextEditingController();
  bool _hasLyrics = false;
  bool _autoLyrics = false;
  bool _isInstrumental = true;
  bool _isLoading = false;
  bool _isPreprocessing = false;
  bool _isGeneratingLyrics = false;
  bool _isConfigured = false;
  String? _currentTaskId;
  String? _musicUrl;
  String? _error;
  String? _referenceAudioBase64;
  int? _musicDuration;
  int? _musicBitrate;
  String _status = '';
  Timer? _statusTimer;
  final _historyRepo = MusicHistoryRepository();
  List<MusicHistoryItem> _history = [];
  String? _activeHistoryId;
  String _playerTitle = '';
  final Set<String> _expandedHistoryIds = {};
  bool _manageMode = false; // 管理模式：显示编辑/删除按钮
  String? _editingId; // 正在内联编辑的历史项 id
  final _editController = TextEditingController();
  String? _currentLocalPath;
  String? _currentLyrics;

  void _setStatus(String msg, {Duration duration = const Duration(seconds: 3)}) {
    _statusTimer?.cancel();
    if (mounted) setState(() => _status = msg);
    if (msg.isNotEmpty) {
      _statusTimer = Timer(duration, () {
        if (mounted) setState(() => _status = '');
      });
    }
  }
  String _selectedModel = 'music-2.6';
  final _musicModels = ['music-2.6', 'music-2.6-free', 'music-cover', 'music-cover-free'];
  bool _useTwoStepCover = false;
  String? _coverFeatureId;

  @override
  void initState() {
    super.initState();
    _checkConfigured();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final list = await _historyRepo.getHistory();
    if (mounted) setState(() => _history = list);
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _editController.dispose();
    super.dispose();
  }

  Future<void> _checkConfigured() async {
    final settings = SettingsRepository();
    final configured = await settings.isConfigured();
    if (mounted) setState(() => _isConfigured = configured);
  }

  void _onModelChanged(String model) => setState(() {_selectedModel = model; _coverFeatureId = null; _lyricsController.clear();});
  void _onHasLyrics(bool? v) => setState(() {_hasLyrics = v ?? false; if (_hasLyrics) {_autoLyrics = false; _isInstrumental = false;} else {_isInstrumental = true;} });
  void _onLyricsMode(bool autoMode) => setState(() {_autoLyrics = autoMode; _isInstrumental = !autoMode; _hasLyrics = false;});
  void _onTwoStepCover(bool? v) => setState(() => _useTwoStepCover = v ?? false);

  Future<void> _pickReferenceAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'wma'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;
      final bytes = await File(file.path!).readAsBytes();
      if (mounted) setState(() {_referenceAudioBase64 = base64Encode(bytes); _coverFeatureId = null; _lyricsController.clear();});
    } catch (e) {
      print('[music] error: \$e');
      if (mounted) setState(() => _error = '选择音频失败: $e');
    }
  }

  Future<void> _preprocessCover() async {
    if (_referenceAudioBase64 == null) return;
    setState(() {_isPreprocessing = true; _error = null; _status = '正在预处理...';});
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final result = await client.coverPreprocess(model: _selectedModel, audioBase64: _referenceAudioBase64);
      if (mounted) setState(() {_coverFeatureId = result.coverFeatureId; _lyricsController.text = result.formattedLyrics; _isPreprocessing = false;}); _setStatus('预处理完成，可修改歌词后生成', duration: const Duration(seconds: 5));
    } catch (e) {
      print('[music] error: \$e');
      if (mounted) setState(() {_error = '预处理失败: $e'; _isPreprocessing = false; _status = '';});
    }
  }

  Future<void> _generateLyrics() async {
    if (_promptController.text.trim().isEmpty && _lyricsController.text.isEmpty) {
      setState(() => _error = '请先输入音乐描述或已有歌词');
      return;
    }
    setState(() {_isGeneratingLyrics = true; _error = null;});
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final result = await client.generateLyrics(mode: _lyricsController.text.isNotEmpty ? 'edit' : 'write_full_song', prompt: _promptController.text.trim().isNotEmpty ? _promptController.text.trim() : null, lyrics: _lyricsController.text.isNotEmpty ? _lyricsController.text : null);
      if (mounted) setState(() {_lyricsController.text = result.lyrics; _hasLyrics = true; _isGeneratingLyrics = false;}); _setStatus('歌词已生成: ${result.songTitle}', duration: const Duration(seconds: 5));
    } catch (e) {
      print('[music] error: \$e');
      if (mounted) setState(() {_error = '歌词生成失败: $e'; _isGeneratingLyrics = false;});
    }
  }

  Future<void> _generateMusic() async {
    if (!_isConfigured) {
      showSnackBar(context, '请先在设置中配置 API Key', isError: true);
      return;
    }
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    setState(() {_isLoading = true; _error = null; _musicUrl = null; _status = '正在生成...';});
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final result = await client.musicGenerate(prompt: prompt, lyrics: _hasLyrics ? _lyricsController.text : null, autoLyrics: _autoLyrics, isInstrumental: _isInstrumental, model: _selectedModel, audioBase64: _useTwoStepCover ? null : _referenceAudioBase64);
      if (result.audioUrl != null || result.audioBase64 != null) {
        setState(() {_musicUrl = result.audioUrl ?? result.audioBase64; _musicDuration = result.duration; _musicBitrate = result.bitrate; _isLoading = false;}); _setStatus('完成!');
        _saveToHistory(result.audioUrl ?? result.audioBase64!);
        return;
      }
      _currentTaskId = result.taskId;
      if (_currentTaskId != null) {
        _pollTaskStatus();
      } else {
        setState(() {_error = '无法获取任务ID'; _isLoading = false;});
      }
    } catch (e) {
      print('[music] error: \$e');
      setState(() {_error = e.toString(); _isLoading = false; _status = '';});
    }
    // 刷新 token 配额
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

  Future<void> _saveToHistory(String audioUrl) async {
    try {
      final localPath = await _historyRepo.addToHistory(
        audioUrl: audioUrl,
        prompt: _promptController.text.trim(),
        lyrics: _hasLyrics ? _lyricsController.text : null,
        model: _selectedModel,
        duration: _musicDuration,
        bitrate: _musicBitrate,
        isInstrumental: _isInstrumental,
      );
      if (mounted) setState(() { _currentLocalPath = localPath; _currentLyrics = _hasLyrics ? _lyricsController.text : null; _playerTitle = '最新生成'; _activeHistoryId = null; });
      await _loadHistory();
    } catch (e) {
      debugPrint('Save history failed: $e');
    }
  }

  Future<void> _deleteHistoryItem(MusicHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除「${item.prompt}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: PixelTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _historyRepo.deleteFromHistory(item.id, item.localPath);
    if (_activeHistoryId == item.id) setState(() { _activeHistoryId = null; _currentLocalPath = null; _currentLyrics = null; _playerTitle = ''; });
    await _loadHistory();
  }

  void _cancelInlineEdit() {
    setState(() => _editingId = null);
  }

  Future<void> _saveInlineEdit(MusicHistoryItem item) async {
    final newTitle = _editController.text.trim();
    if (newTitle.isEmpty || newTitle == item.prompt) {
      _cancelInlineEdit();
      return;
    }
    await _historyRepo.updatePrompt(item.id, newTitle);
    _cancelInlineEdit();
    await _loadHistory();
  }

  Future<void> _pollTaskStatus() async {
    while (_currentTaskId != null && _isLoading) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        await ref.read(minimaxClientProvider.notifier).loadFromSettings();
        final client = ref.read(minimaxClientProvider);
        final status = await client.getTaskStatus(_currentTaskId!);
        if (mounted) {
          setState(() => _status = '状态: ${status.status}');
          if (status.status == 'completed') {
            final url = status.result?['music_url'] as String?;
            setState(() {_musicUrl = url; _isLoading = false;}); _setStatus('完成!');
            if (url != null) _saveToHistory(url);
            break;
          } else if (status.status == 'failed') {
            setState(() {_error = '音乐生成失败'; _isLoading = false; _status = '';});
            break;
          }
        }
      } catch (e) {}
        print('[music] error: \$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsChangedProvider, (prev, next) => _checkConfigured());
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          PageHeader(icon: Icons.music_note_outlined, title: ref.watch(i18nProvider)?.t('music.title') ?? '音乐生成'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!_isConfigured)
                  SettingsWarningCard(
                    onNavigateToSettings: () => ref.read(navigationIndexProvider.notifier).state = 4,
                  ),
                _buildModelCard(),
                const SizedBox(height: 20),
                GenerateButton(
                  label: '生成音乐',
                  icon: Icons.music_note,
                  onPressed: _generateMusic,
                  isLoading: _isLoading,
                ),
                if (_error != null) ...[const SizedBox(height: 16), ErrorCard(message: _error!)],
                if (_currentLocalPath != null || _musicUrl != null) ...[const SizedBox(height: 28), _buildResultCard()],
                if (_history.isNotEmpty) ...[const SizedBox(height: 28), _buildHistorySection()],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildModelCard() {
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    final textSecondary = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    return ModernCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ModelDropdown(
          label: '选择模型',
          selectedModel: _selectedModel,
          models: _musicModels,
          modelDescriptions: const {
            'music-2.6': '以声传情：翻唱入心，器乐入魂',
            'music-2.6-free': '限免版，RPM较低，需要标准密钥',
            'music-cover': '基于参考音频生成翻唱版本',
            'music-cover-free': '限免版，RPM较低，需要标准密钥',
          },
          onChanged: _onModelChanged,
        ),
        const SizedBox(height: 20),
        if (_selectedModel.startsWith('music-cover')) ...[
          _buildCoverSection(),
          const SizedBox(height: 20),
        ],
        const SectionTitle(title: '音乐描述'),
        const SizedBox(height: 10),
        TextField(controller: _promptController, minLines: 1, maxLines: 6, style: TextStyle(fontSize: 14, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary), decoration: InputDecoration(hintText: '描述音乐风格和主题...', hintStyle: TextStyle(color: textMuted), border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusMd)))),
        const SizedBox(height: 16),
        Row(children: [
          _buildCheckbox('包含歌词', _hasLyrics, _onHasLyrics),
          const Spacer(),
          SizedBox(
            width: 180,
            child: _buildLyricsModeToggle(),
          ),
        ]),
        if (_hasLyrics) ...[const SizedBox(height: 12), _buildLyricsSection()],
      ]),
    );
  }

  Widget _buildCoverSection() {
    final textSecondary = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle(title: '参考音频'),
      const SizedBox(height: 8),
      Text('上传参考音频（6秒-6分钟，最大50MB）用于翻唱', style: TextStyle(fontSize: 12, color: textSecondary)),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _isLoading ? null : _pickReferenceAudio,
        icon: Icon(_referenceAudioBase64 != null ? Icons.check : Icons.upload_file, size: 18, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
        label: Text(_referenceAudioBase64 != null ? '已选择音频' : '上传参考音频'),
        style: OutlinedButton.styleFrom(foregroundColor: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary, side: BorderSide(color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary), padding: const EdgeInsets.symmetric(vertical: 12)),
      ),
      const SizedBox(height: 16),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
        _buildCheckbox('两步翻唱', _useTwoStepCover, _onTwoStepCover),
        Text('先预处理提取歌词', style: TextStyle(fontSize: 11, color: textSecondary)),
      ]),
      if (_useTwoStepCover) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: (_referenceAudioBase64 != null && !_isPreprocessing) ? _preprocessCover : null,
            icon: _isPreprocessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.auto_fix_high, size: 18, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
            label: Text(_isPreprocessing ? '处理中...' : '预处理音频'),
            style: OutlinedButton.styleFrom(foregroundColor: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary, side: BorderSide(color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary), padding: const EdgeInsets.symmetric(vertical: 12)),
          )),
          if (_coverFeatureId != null) ...[const SizedBox(width: 12), Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: PixelTheme.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.check_circle, size: 20, color: PixelTheme.success))],
        ]),
        if (_coverFeatureId != null) ...[const SizedBox(height: 12), TextField(controller: _lyricsController, maxLines: 6, style: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary), decoration: InputDecoration(hintText: '可修改歌词...', hintStyle: TextStyle(color: textMuted), border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusMd))))],
      ],
    ]);
  }

  Widget _buildLyricsSection() {
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _lyricsController, maxLines: 6, style: TextStyle(fontSize: 14, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary), decoration: InputDecoration(hintText: '输入歌词...', hintStyle: TextStyle(color: textMuted), border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusMd)))),
      const SizedBox(height: 10),
      Row(children: [
        OutlinedButton(
          onPressed: _isGeneratingLyrics ? null : _generateLyrics,
          style: OutlinedButton.styleFrom(foregroundColor: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary, side: BorderSide(color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary), padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
          child: _isGeneratingLyrics ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('AI写词', style: TextStyle(fontSize: 12)),
        ),
        if (_status.contains('歌词已生成')) ...[const SizedBox(width: 10), Icon(Icons.check_circle, size: 16, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.success)],
      ]),
    ]);
  }

  Widget _buildLyricsModeToggle() {
    if (_hasLyrics) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: _isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = (constraints.maxWidth - 6) / 2;
          return Stack(
            children: [
              // 滑动背景指示器
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: _autoLyrics ? 0 : segmentWidth,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: PixelTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: PixelTheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // 选项文字
              Row(
                children: [
                  Expanded(child: _buildToggleSegment('AI生成歌词', _autoLyrics, () => _onLyricsMode(true))),
                  Expanded(child: _buildToggleSegment('纯音乐', _isInstrumental, () => _onLyricsMode(false))),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToggleSegment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
          ),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(duration: const Duration(milliseconds: 200), width: 22, height: 22, decoration: BoxDecoration(gradient: value ? PixelTheme.primaryGradient : null, color: value ? null : Colors.transparent, borderRadius: BorderRadius.circular(6), border: Border.all(color: value ? Colors.transparent : (_isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted), width: 2)), child: value ? const Icon(Icons.check, size: 14, color: Colors.white) : null),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 14, color: value ? PixelTheme.primary : (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary), fontWeight: value ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }

  Widget _buildResultCard() {
    return AudioPlayerWidget(
      audioUrl: _currentLocalPath == null ? _musicUrl : null,
      localPath: _currentLocalPath,
      title: _playerTitle.isNotEmpty ? _playerTitle : (_status.isNotEmpty ? _status : null),
      lyrics: _currentLyrics,
    );
  }

  Widget _buildHistorySection() {
    final textSecondary = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: SectionTitle(title: '历史记录')),
        GestureDetector(
          onTap: () => setState(() => _manageMode = !_manageMode),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _manageMode ? PixelTheme.primary.withValues(alpha: 0.15) : (_isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _manageMode ? PixelTheme.primary : (_isDark ? PixelTheme.darkBorderSubtle : PixelTheme.pixelBorder)),
            ),
            child: Text(_manageMode ? '完成' : '管理', style: TextStyle(fontSize: 12, color: _manageMode ? PixelTheme.primary : textSecondary)),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      ..._history.map((item) => _buildHistoryItem(item)),
    ]);
  }

  Widget _buildHistoryItem(MusicHistoryItem item) {
    final isActive = _activeHistoryId == item.id;
    final isExpanded = _expandedHistoryIds.contains(item.id);
    final exists = File(item.localPath).existsSync();
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    final primaryColor = _isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    final surfaceVariant = _isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Colors.transparent, PixelTheme.error]),
          borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        if (_manageMode) return false;
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除确认'),
            content: Text('确定要删除「${item.prompt}」吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: PixelTheme.error))),
            ],
          ),
        );
        return result ?? false;
      },
      onDismissed: (_) => _deleteHistoryItem(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: isActive ? BoxDecoration(
          borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
          border: Border.all(color: PixelTheme.accent, width: 1.5),
        ) : null,
        child: ModernCard(
          child: Column(children: [
          // Header row — always visible
          InkWell(
            onTap: exists ? () {
              setState(() {
                _currentLocalPath = item.localPath;
                _currentLyrics = item.lyrics;
                _musicUrl = null;
                _playerTitle = item.prompt;
                _activeHistoryId = item.id;
              });
            } : null,
            borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: isActive ? PixelTheme.accentGradient : null,
                    color: isActive ? null : surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(isActive ? Icons.volume_up : Icons.play_arrow, color: isActive ? Colors.white : primaryColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_editingId == item.id)
                      TextField(
                        controller: _editController,
                        autofocus: true,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _saveInlineEdit(item),
                      )
                    else
                      Text(item.prompt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isActive ? PixelTheme.accent : textPrimary)),
                    const SizedBox(height: 4),
                    Row(children: [
                      _buildTag(item.model),
                      const SizedBox(width: 8),
                      Text(item.formattedDate, style: TextStyle(fontSize: 11, color: textMuted)),
                      if (item.formattedDuration.isNotEmpty) ...[const SizedBox(width: 8), Icon(Icons.timer, size: 12, color: textMuted), const SizedBox(width: 2), Text(item.formattedDuration, style: TextStyle(fontSize: 11, color: textMuted))],
                    ]),
                  ]),
                ),
                if (item.lyrics != null && item.lyrics!.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => setState(() {
                      if (isExpanded) { _expandedHistoryIds.remove(item.id); } else { _expandedHistoryIds.add(item.id); }
                    }),
                    child: AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more, size: 20, color: textMuted),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          // 管理模式操作栏
          if (_manageMode)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_editingId == item.id) {
                        _saveInlineEdit(item);
                      } else {
                        _cancelInlineEdit();
                        setState(() {
                          _editingId = item.id;
                          _editController.text = item.prompt;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_editingId == item.id ? Icons.check : Icons.edit, size: 14, color: primaryColor),
                        const SizedBox(width: 4),
                        Text(_editingId == item.id ? '保存' : '编辑', style: TextStyle(fontSize: 12, color: primaryColor)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _cancelInlineEdit();
                      _deleteHistoryItem(item);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: PixelTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: PixelTheme.error.withValues(alpha: 0.2)),
                      ),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.delete, size: 14, color: PixelTheme.error),
                        SizedBox(width: 4),
                        Text('删除', style: TextStyle(fontSize: 12, color: PixelTheme.error)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          // Expandable detail section
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Divider(height: 0.5,
                  color: PixelTheme.dividerFor(_isDark)),
                const SizedBox(height: 10),
                if (item.lyrics != null && item.lyrics!.isNotEmpty) ...[
                  Text('歌词:', style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(item.lyrics!, style: TextStyle(fontSize: 12, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary))),
                  const SizedBox(height: 8),
                ],
                Row(children: [
                  _buildTag(item.model),
                  if (item.bitrate != null) ...[const SizedBox(width: 8), _buildTag('${item.bitrate}kbps')],
                  if (item.isInstrumental) ...[const SizedBox(width: 8), _buildTag('纯音乐')],
                ]),
              ]),
            ),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ]),
      ),
    ),
    );
  }

  Widget _buildTag(String text) {
    final tagColor = _isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 10, color: tagColor)),
    );
  }
}
