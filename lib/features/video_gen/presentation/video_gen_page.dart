// ignore_for_file: avoid_dynamic_calls

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/utils/image_base64.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../app/theme.dart';
import '../../../core/permission/permission_manager.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/utils/snackbar_utils.dart';
import '../../../shared/utils/file_utils.dart';
import '../../../shared/widgets/error_card.dart';
import '../../../shared/widgets/settings_warning_card.dart';
import '../../../shared/widgets/generate_button.dart';
import '../../../shared/widgets/chip_selector.dart';
import '../../../shared/widgets/video_result_player.dart';
import '../../../shared/widgets/model_dropdown.dart';
import '../../../app/app.dart' show navigationIndexProvider;
import '../../../core/api/minimax_client.dart' show MinimaxApiException, PlanNotSupportedException, QuotaExhaustedException;
import '../../chat/presentation/chat_page.dart' show minimaxClientProvider, settingsChangedProvider;
import '../../settings/data/settings_repository.dart';
import '../data/video_history_repository.dart';
import 'video_template_page.dart';
import 'video_history_page.dart';

class VideoGenPage extends ConsumerStatefulWidget {
  const VideoGenPage({super.key});
  @override
  ConsumerState<VideoGenPage> createState() => _VideoGenPageState();
}

class _VideoGenPageState extends ConsumerState<VideoGenPage> with WidgetsBindingObserver {
  final _promptController = TextEditingController();
  final _subjectImageUrlController = TextEditingController();
  bool _isLoading = false;
  bool _isProcessingImage = false;
  bool _isConfigured = false;
  String? _currentTaskId;
  String? _videoUrl;
  String? _error;
  String _status = '';
  String _selectedModel = 'MiniMax-Hailuo-2.3';
  String _videoMode = 't2v';
  String? _firstFrameBase64;
  String? _lastFrameBase64;
  bool _promptOptimizer = true;
  final bool _fastPretreatment = false;
  int _duration = 6;
  String _resolution = '768P';
  bool _aigcWatermark = false;
  final _imagePicker = ImagePicker();
  final _videoHistoryRepo = VideoHistoryRepository();
  final _t2vModels = ['MiniMax-Hailuo-2.3', 'MiniMax-Hailuo-02', 'T2V-01-Director', 'T2V-01'];
  final _i2vModels = ['MiniMax-Hailuo-2.3', 'MiniMax-Hailuo-2.3-Fast', 'MiniMax-Hailuo-02', 'I2V-01-Director', 'I2V-01-live', 'I2V-01'];
  final _fl2vModel = 'MiniMax-Hailuo-02';
  final _s2vModel = 'S2V-01';

  static const _modeOptions = [
    {'id': 't2v', 'label': '文生视频', 'icon': Icons.text_fields},
    {'id': 'i2v', 'label': '图生视频', 'icon': Icons.image},
    {'id': 'fl2v', 'label': '首尾帧', 'icon': Icons.compare},
    {'id': 's2v', 'label': '主体参考', 'icon': Icons.person},
  ];

  List<String> get _modelsForMode => switch (_videoMode) {
    't2v' => _t2vModels,
    'i2v' => _i2vModels,
    'fl2v' => [_fl2vModel],
    's2v' => [_s2vModel],
    _ => _t2vModels,
  };

  String _defaultModelFor(String mode) => switch (mode) {
    't2v' => 'MiniMax-Hailuo-2.3',
    'i2v' => 'MiniMax-Hailuo-2.3-Fast',
    'fl2v' => _fl2vModel,
    's2v' => _s2vModel,
    _ => 'MiniMax-Hailuo-2.3',
  };

  final Map<String, String> _modelDescriptions = {
    'MiniMax-Hailuo-2.3': '全新视频生成模型，肢体动作、面部表情、物理表现与指令遵循再度突破',
    'MiniMax-Hailuo-2.3-Fast': '图生视频模型，物理表现与指令遵循具佳，更快更优惠',
    'MiniMax-Hailuo-02': '基础视频生成模型，支持文生视频、图生视频、首尾帧视频',
    'T2V-01-Director': '文生视频导演版，更强的指令控制与画面调度能力',
    'T2V-01': '基础文生视频模型，支持文字描述生成视频',
    'I2V-01-Director': '图生视频导演版，精准控制视频生成',
    'I2V-01-live': '图生视频写实版，适合真实场景',
    'I2V-01': '基础图生视频模型，基于图片生成视频',
    'S2V-01': '主体参考视频，参考人物图片生成视频',
  };

  final _resolutionOptionsT2v = ['720P', '768P', '1080P'];
  final _resolutionOptionsI2v = ['512P', '768P', '1080P'];
  final _resolutionOptionsFl2v = ['768P', '1080P'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkConfigured();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promptController.dispose();
    _subjectImageUrlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台时保存轮询状态，回前台自动恢复
    if (state == AppLifecycleState.paused && _isLoading && _currentTaskId != null) {
      _isLoading = false;
    } else if (state == AppLifecycleState.resumed && _currentTaskId != null && !_isLoading) {
      _resumePolling();
    }
  }

  Future<void> _checkConfigured() async {
    final settings = SettingsRepository();
    final configured = await settings.isConfigured();
    if (mounted) setState(() => _isConfigured = configured);
  }

  void _onModeChanged(String mode) => setState(() {
    if (_videoMode == mode) return;
    _videoMode = mode;
    _selectedModel = _defaultModelFor(mode);
    _firstFrameBase64 = null;
    _lastFrameBase64 = null;
    _resolution = mode == 'fl2v' ? '768P' : '768P';
    _duration = 6;
  });
  void _onModelChanged(String model) => setState(() {_selectedModel = model; _resolution = '768P';});
  void _onFirstFrame(String? b64) => setState(() => _firstFrameBase64 = b64);
  void _onLastFrame(String? b64) => setState(() => _lastFrameBase64 = b64);
  void _clearFirstFrame() => setState(() => _firstFrameBase64 = null);
  void _clearLastFrame() => setState(() => _lastFrameBase64 = null);
  void _onPromptOptimizerChanged(bool v) => setState(() => _promptOptimizer = v);
  void _onWatermarkChanged(bool v) => setState(() => _aigcWatermark = v);

  Widget _buildImagePicker({required String label, required String? imageBase64, required VoidCallback onPick, required VoidCallback onClear}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: ResponsiveHelper.thumbnailSize(context),
            height: ResponsiveHelper.thumbnailSize(context),
            decoration: BoxDecoration(
              color: PixelTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
              border: Border.all(color: PixelTheme.pixelBorder),
            ),
            child: _isProcessingImage
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : imageBase64 != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(PixelTheme.radiusMd), child: Image.memory(ImageBase64.decodeAny(imageBase64), fit: BoxFit.cover))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate, size: 28, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text('上传', style: TextStyle(fontSize: 11, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                        ]),
            ),
          ),
        if (imageBase64 != null) TextButton(onPressed: onClear, child: Text('清除', style: TextStyle(color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary))),
      ],
    );
  }

  bool get _isI2VMode => _videoMode == 'i2v';

  List<String> get _currentResolutionOptions {
    if (_videoMode == 'fl2v') return _resolutionOptionsFl2v;
    if (_videoMode == 'i2v') return _resolutionOptionsI2v;
    return _resolutionOptionsT2v;
  }

  /// 当前分辨率下可用的时长（秒）。文档：仅 768P 支持 10s，其他分辨率只支持 6s
  List<int> get _validDurations {
    if (_resolution == '768P') return [6, 10];
    return [6];
  }

  Future<void> _pickImage(void Function(String?) setter) async {
    try {
      final ok = await PermissionManager().request(context, AppPermission.storage);
      if (!ok) return;
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      setState(() => _isProcessingImage = true);
      final bytes = await picked.readAsBytes();
      final sizeError = FileUtils.validateFileSize(bytes.length, AttachmentType.image);
      if (sizeError != null) {
        setState(() { _error = sizeError; _isProcessingImage = false; });
        return;
      }
      final formatError = FileUtils.validateImageFormat(bytes);
      if (formatError != null) {
        setState(() { _error = formatError; _isProcessingImage = false; });
        return;
      }
      final mime = picked.mimeType ?? 'image/jpeg';
      setState(() => _isProcessingImage = false);
      setter(ImageBase64.encode(bytes));
    } catch (e) {
      print('[video] error: \$e');
      setState(() { _error = '选择图片失败: $e'; _isProcessingImage = false; });
    }
  }

  Future<void> _generateVideo() async {
    if (!_isConfigured) {
      showSnackBar(context, '请先在设置中配置 API Key', isError: true);
      return;
    }
    final prompt = _promptController.text.trim();
    // S2V 的 prompt 为可选参数
    if (prompt.isEmpty && _videoMode != 's2v') {
      setState(() => _error = '请输入视频描述文本');
      return;
    }
    if (_isI2VMode && _firstFrameBase64 == null) {
      setState(() => _error = '图生视频模式需要上传首帧图片');
      return;
    }
    if (_videoMode == 'fl2v' && (_firstFrameBase64 == null || _lastFrameBase64 == null)) {
      setState(() => _error = '首尾帧模式需要上传首帧和尾帧图片');
      return;
    }
    if (_videoMode == 's2v' && _subjectImageUrlController.text.trim().isEmpty) {
      setState(() => _error = '主体参考模式需要提供人物图片URL');
      return;
    }
    // 模型-模式一致性校验
    final modelOk = switch (_videoMode) {
      't2v' => _t2vModels.contains(_selectedModel),
      'i2v' => _i2vModels.contains(_selectedModel),
      'fl2v' => _selectedModel == _fl2vModel,
      's2v' => _selectedModel == _s2vModel,
      _ => true,
    };
    if (!modelOk) {
      setState(() => _error = '模型与视频模式不匹配，请重新选择模式');
      return;
    }
    // 取消已有轮询防止重复
    _currentTaskId = null;
    setState(() {_isLoading = true; _error = null; _videoUrl = null; _status = '正在生成...';});
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      if (!mounted) return;
      final client = ref.read(minimaxClientProvider);
      dynamic result;
      if (_videoMode == 's2v') {
        result = await client.subjectReferenceToVideo(subjectImageUrl: _subjectImageUrlController.text.trim(), prompt: prompt, promptOptimizer: _promptOptimizer, aigcWatermark: _aigcWatermark);
      } else if (_videoMode == 'fl2v') {
        result = await client.videoGenerate(prompt, model: _selectedModel,
          firstFrameImage: _firstFrameBase64 != null ? ImageBase64.toDataUri(_firstFrameBase64!) : null,
          lastFrameImage: _lastFrameBase64 != null ? ImageBase64.toDataUri(_lastFrameBase64!) : null,
          promptOptimizer: _promptOptimizer, fastPretreatment: _fastPretreatment, duration: _duration, resolution: _resolution, aigcWatermark: _aigcWatermark);
      } else if (_firstFrameBase64 != null) {
        result = await client.imageToVideo(ImageBase64.toDataUri(_firstFrameBase64!), prompt, model: _selectedModel, promptOptimizer: _promptOptimizer, fastPretreatment: _fastPretreatment, duration: _duration, resolution: _resolution, aigcWatermark: _aigcWatermark);
      } else {
        result = await client.videoGenerate(prompt, model: _selectedModel, promptOptimizer: _promptOptimizer, fastPretreatment: _fastPretreatment, duration: _duration, resolution: _resolution, aigcWatermark: _aigcWatermark);
      }
      if (!mounted) return;
      _currentTaskId = result.taskId;
      _pollTaskStatus();
    } catch (e) {
      print('[video] error: \$e');
      if (!mounted) return;
      setState(() {_error = e.toString(); _isLoading = false; _status = '';});
    }
  }

  Future<void> _pollTaskStatus() async {
    int retryCount = 0;
    const maxRetries = 60;
    String? lastError;

    while (_currentTaskId != null && _isLoading && retryCount < maxRetries) {
      await Future.delayed(const Duration(seconds: 3));
      retryCount++;

      try {
        await ref.read(minimaxClientProvider.notifier).loadFromSettings();
        final client = ref.read(minimaxClientProvider);
        final status = await client.getTaskStatus(_currentTaskId!);
        if (!mounted) break;

        setState(() => _status = '状态: ${status.status}');

        final s = status.status.toLowerCase();
        if (s == 'success') {
          // 官方文档: 查询接口只返回 file_id，必须通过 /v1/files/retrieve 获取下载链接
          String? videoUrl;
          if (status.fileId != null && status.fileId!.isNotEmpty) {
            for (int dlRetry = 0; dlRetry < 3; dlRetry++) {
              try {
                final fileResult = await client.downloadFile(status.fileId!);
                videoUrl = _nullIfEmpty(fileResult.downloadUrl);
                if (videoUrl != null) break;
                debugPrint('[VideoGen] downloadFile 返回空 download_url (重试 $dlRetry/3)');
              } catch (e) {
                debugPrint('[VideoGen] downloadFile 异常: $e (重试 $dlRetry/3)');
              }
              if (dlRetry < 2) await Future.delayed(const Duration(seconds: 2));
            }
          }

          if (videoUrl != null && videoUrl.isNotEmpty) {
            setState(() {_videoUrl = videoUrl; _isLoading = false; _status = '完成!'; _currentTaskId = null;});
            _videoHistoryRepo.addToHistory(
              prompt: _promptController.text.trim(),
              model: _selectedModel,
              duration: _duration,
              resolution: _resolution,
              videoUrl: videoUrl,
            );
          } else {
            _currentTaskId = null;
            debugPrint('[VideoGen] 无法获取下载链接');
            debugPrint('[VideoGen] taskId=$_currentTaskId fileId=${status.fileId}');
            setState(() {
              _error = '视频已生成但无法获取下载链接\n'
                  'task_id: $_currentTaskId\n'
                  'file_id: ${status.fileId ?? "无"}\n'
                  '可在 MiniMax 控制台手动下载';
              _isLoading = false; _status = '';
            });
          }
          return;
        } else if (s == 'fail' || s == 'failed') {
          setState(() {_error = '视频生成失败'; _isLoading = false; _status = ''; _currentTaskId = null;});
          return;
        }
        // else: 'processing' / 'queued' / etc → 继续轮询
      } catch (e) {
        lastError = e.toString();
        // 致命错误（鉴权/配额/权限）立即终止
        if (_isFatalError(e)) {
          debugPrint('[VideoGen] 轮询终止: $lastError');
          if (mounted) {
            setState(() {_error = lastError!; _isLoading = false; _status = '';});
          }
          return;
        }
        // 网络瞬时错误继续重试
      }
    }

    if (retryCount >= maxRetries && _isLoading && mounted) {
      setState(() {
        _error = '视频生成超时，请稍后重试${lastError != null ? ' ($lastError)' : ''}';
        _isLoading = false;
        _status = '';
      });
    }
  }

  Future<void> _downloadVideo(String url) async {
    try {
      showSnackBar(context, '正在下载视频...', isError: false);
      final dir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${dir.path}/downloads');
      if (!await downloadsDir.exists()) await downloadsDir.create();
      final filename = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final path = '${downloadsDir.path}/$filename';
      await Dio().download(url, path);
      if (mounted) {
        showSnackBar(context, '已保存: $filename', isError: false);
      }
    } catch (e) {
      print('[video] error: \$e');
      if (mounted) showSnackBar(context, '下载失败: $e', isError: true);
    }
  }

  /// 判断错误是否需要立即终止轮询（鉴权/配额/权限）
  /// 判断是否是致命错误（不应继续重试轮询）
  bool _isFatalError(Object e) {
    if (e is MinimaxApiException) {
      // HTTP 状态码：401/403 鉴权失败
      final httpCode = e.statusCode;
      if (httpCode != null && (httpCode == 401 || httpCode == 403)) return true;
      // MiniMax 业务错误码：1004/2049 鉴权，1008 余额不足，2013 参数异常
      final apiCode = e.apiCode;
      if (apiCode != null) {
        if ([1004, 1008, 2049, 2013, 1026, 1027].contains(apiCode)) return true;
      }
      if (e is PlanNotSupportedException || e is QuotaExhaustedException) return true;
    }
    return false;
  }

  /// 空字符串视为 null
  String? _nullIfEmpty(String? s) => (s != null && s.isNotEmpty) ? s : null;

  void _cancelGeneration() {
    setState(() {
      _isLoading = false;
      _status = '已取消（后台可能仍在生成）';
    });
    // 保留 _currentTaskId，不丢弃
  }

  void _resumePolling() {
    if (_currentTaskId == null) return;
    setState(() { _isLoading = true; _status = '恢复查询...'; });
    _pollTaskStatus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsChangedProvider, (prev, next) => _checkConfigured());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!_isConfigured)
                  SettingsWarningCard(onNavigateToSettings: () => ref.read(navigationIndexProvider.notifier).state = 4),
                _buildTemplateCard(),
                const SizedBox(height: 16),

                // 视频描述输入（S2V 可选）
                _buildSectionTitle('视频描述${_videoMode == "s2v" ? "（可选）" : ""}'),
                const SizedBox(height: 8),
                TextField(
                  controller: _promptController,
                  maxLines: 4,
                  minLines: 2,
                  style: TextStyle(fontSize: 14, color: isDark ? PixelTheme.darkPrimaryText : null),
                  decoration: InputDecoration(
                    hintText: _videoMode == 's2v' ? '描述主体动作（可选）...' : '描述你想生成的视频内容...',
                    hintStyle: TextStyle(color: isDark ? PixelTheme.darkTextMuted : null),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusMd)),
                  ),
                ),
                const SizedBox(height: 16),

                // 模式选择
                _buildSectionTitle('视频模式'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _modeOptions.map((m) {
                    final active = _videoMode == m['id'];
                    return InputChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(m['icon'] as IconData, size: 16, color: active ? Colors.white : (isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                        const SizedBox(width: 6),
                        Text(m['label'] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: active ? Colors.white : (isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary))),
                      ]),
                      selected: active,
                      onSelected: (_) => _onModeChanged(m['id'] as String),
                      backgroundColor: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
                      selectedColor: isDark ? PixelTheme.darkPrimary : PixelTheme.primary,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      showCheckmark: false,
                      pressElevation: 2,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 模型选择
                _buildModelChips(_modelsForMode),
                const SizedBox(height: 12),

                // 模式特有输入
                if (_videoMode == 'i2v') ...[
                  _buildImagePicker(label: '首帧图片', imageBase64: _firstFrameBase64, onPick: () => _pickImage(_onFirstFrame), onClear: _clearFirstFrame),
                  const SizedBox(height: 12),
                ] else if (_videoMode == 'fl2v') ...[
                  Row(children: [
                    Expanded(child: _buildImagePicker(label: '首帧', imageBase64: _firstFrameBase64, onPick: () => _pickImage(_onFirstFrame), onClear: _clearFirstFrame)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildImagePicker(label: '尾帧', imageBase64: _lastFrameBase64, onPick: () => _pickImage(_onLastFrame), onClear: _clearLastFrame)),
                  ]),
                  const SizedBox(height: 12),
                ] else if (_videoMode == 's2v') ...[
                  TextField(
                    controller: _subjectImageUrlController,
                    style: TextStyle(fontSize: 14, color: isDark ? PixelTheme.darkPrimaryText : null),
                    decoration: InputDecoration(
                      labelText: '人物图片URL',
                      hintText: '输入图片URL...',
                      hintStyle: TextStyle(color: isDark ? PixelTheme.darkTextMuted : null),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusMd)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 时长选择（S2V 不支持）
                if (_videoMode != 's2v') ...[
                  _buildSectionTitle('视频时长'),
                  const SizedBox(height: 8),
                  ChipSelector<int>(
                    options: _validDurations
                        .map((d) => ChipOption(value: d, label: '$d秒'))
                        .toList(),
                    selected: _duration,
                    onChanged: (v) => setState(() => _duration = v),
                  ),
                  const SizedBox(height: 16),
                ],

                // 分辨率选择（S2V 不支持）
                if (_videoMode != 's2v') ...[
                  _buildSectionTitle('分辨率'),
                  const SizedBox(height: 8),
                  ChipSelector<String>(
                    options: _currentResolutionOptions.map((r) => ChipOption(value: r, label: r)).toList(),
                    selected: _resolution,
                  onChanged: (v) => setState(() {
                    _resolution = v;
                    if (!_validDurations.contains(_duration)) _duration = 6;
                  }),
                ),
                const SizedBox(height: 16),
                ],

                // 选项开关
                _buildToggleRow('提示词优化', _promptOptimizer, _onPromptOptimizerChanged),
                _buildToggleRow('AI水印', _aigcWatermark, _onWatermarkChanged),
                const SizedBox(height: 20),

                // 生成/取消按钮
                if (_isLoading) ...[
                  GenerateButton(label: _status, icon: Icons.hourglass_empty, isLoading: true, onPressed: null),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(onPressed: _cancelGeneration, child: Text('取消轮询', style: TextStyle(color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary))),
                  ),
                ] else if (_currentTaskId != null && _videoUrl == null && _error == null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('任务仍在后台生成中，可恢复查看结果', style: TextStyle(fontSize: 13, color: Colors.orange))),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _resumePolling,
                          child: Text('恢复', style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary)),
                        ),
                      ]),
                    ),
                  ),
                  GenerateButton(label: '生成视频', icon: Icons.movie_creation, onPressed: _generateVideo),
                ] else
                  GenerateButton(label: '生成视频', icon: Icons.movie_creation, onPressed: _generateVideo),

                // 错误和结果
                if (_error != null) ...[const SizedBox(height: 16), ErrorCard(message: _error!)],
                if (_videoUrl != null) ...[const SizedBox(height: 28), _buildResultCard(_videoUrl!)],
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary));
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final dividerColor = PixelTheme.dividerFor(isDark);
    final iconColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;

    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            const SizedBox(width: 40),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_outlined, size: 20, color: textColor),
                  const SizedBox(width: 6),
                  Text('视频生成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor, letterSpacing: 0.5)),
                ],
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: Icon(Icons.history, size: 20, color: iconColor),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VideoHistoryPage())),
                padding: EdgeInsets.zero,
              ),
            ),
          ]),
        ),
        Divider(height: 0.5, thickness: 0.5, color: dividerColor),
      ],
    );
  }

  Widget _buildTemplateCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const VideoTemplatePage())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)]), borderRadius: BorderRadius.circular(PixelTheme.radiusMd)),
        child: const Row(children: [
          Icon(Icons.auto_awesome, color: Colors.white, size: 24),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('视频模板', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            Text('使用预设模板快速生成趣味视频', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
        ]),
      ),
    );
  }

  Widget _buildModelChips(List<String> models) {
    return ModelDropdown(
      label: '选择模型',
      selectedModel: _selectedModel,
      models: models,
      modelDescriptions: _modelDescriptions,
      onChanged: _onModelChanged,
    );
  }

  Widget _buildToggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary))),
        Switch(value: value, onChanged: onChanged, activeTrackColor: PixelTheme.primary),
      ]),
    );
  }

  Widget _buildResultCard(String videoUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ModernCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 视频预览
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: VideoResultPlayer(videoUrl: videoUrl),
        ),
        const SizedBox(height: 8),
        // URL 行 + 复制按钮
        Row(children: [
          Expanded(
            child: GestureDetector(
              onLongPress: () => _showVideoActions(videoUrl),
              child: Text(
                videoUrl,
                style: TextStyle(fontSize: 11, color: (isDark ? PixelTheme.darkPrimary : PixelTheme.primary).withValues(alpha: 0.7)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: videoUrl));
              showSnackBar(context, '链接已复制');
            },
            child: Icon(Icons.copy, size: 14, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText),
          ),
        ]),
        const SizedBox(height: 2),
        Text(
          '长按可下载或复制链接',
          style: TextStyle(fontSize: 10, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
        ),
      ]),
    );
  }

  void _showVideoActions(String videoUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载到本地'),
              onTap: () { Navigator.pop(ctx); _downloadVideo(videoUrl); },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制链接'),
              onTap: () { Navigator.pop(ctx); Clipboard.setData(ClipboardData(text: videoUrl)); showSnackBar(context, '链接已复制'); },
            ),
          ]),
        ),
      ),
    );
  }
}
