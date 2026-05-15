import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/permission/permission_manager.dart';
import '../../../shared/utils/image_base64.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../../app/theme.dart';
import '../../../app/app.dart' show navigationIndexProvider;
import '../../../shared/utils/file_utils.dart';
import '../../../shared/widgets/video_result_player.dart';
import '../../../core/api/minimax_client.dart' show MinimaxApiException, PlanNotSupportedException, QuotaExhaustedException;
import '../../chat/presentation/chat_page.dart' show minimaxClientProvider, settingsChangedProvider;
import '../../settings/data/settings_repository.dart';
import '../data/video_history_repository.dart';

class VideoTemplatePage extends ConsumerStatefulWidget {
  const VideoTemplatePage({super.key});

  @override
  ConsumerState<VideoTemplatePage> createState() => _VideoTemplatePageState();
}

class _VideoTemplatePageState extends ConsumerState<VideoTemplatePage> with WidgetsBindingObserver {
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  bool _isLoading = false;
  bool _isProcessingImage = false;
  bool _isConfigured = false;
  String? _currentTaskId;
  String? _videoUrl;
  String? _error;
  String _status = '';
  VideoTemplate? _selectedTemplate;
  String? _selectedImageBase64;
  final _videoHistoryRepo = VideoHistoryRepository();
  final _textInputs = <String, TextEditingController>{};
  final _imagePicker = ImagePicker();
  bool _aigcWatermark = false;

  final List<VideoTemplate> _templates = [
    VideoTemplate(
      id: '392753057216684038',
      name: '跳水',
      description: '上传照片，生成照片中主体完美跳水表现的视频',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.scuba_diving,
      previewUrl: 'https://filecdn.minimax.chat/public/434bb72c-3f55-4094-b06f-fb96bd41ddac.mp4',
    ),
    VideoTemplate(
      id: '393881433990066176',
      name: '吊环',
      description: '上传宠物照片，生成图中主体完成完美吊环动作的视频',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.sports_gymnastics,
      previewUrl: 'https://filecdn.minimax.chat/public/4eba7e2b-ae58-4933-965e-3dbde901ed1f.mp4',
    ),
    VideoTemplate(
      id: '393769180141805569',
      name: '绝地求生',
      description: '上传宠物图片并输入野兽种类，生成宠物野外绝地求生视频',
      requiresMedia: true,
      requiresText: true,
      icon: Icons.pets,
      previewUrl: 'https://filecdn.minimax.chat/public/ee7be27a-86e4-45ef-b1fb-829ea078624d.mp4',
    ),
    VideoTemplate(
      id: '394246956137422856',
      name: '万物皆可 labubu',
      description: '上传人物/宠物照片，生成 labubu 换脸视频',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.face,
      previewUrl: 'https://filecdn.minimax.chat/public/5d6cff91-b030-4c19-a80e-29cfed3ed56d.mp4',
    ),
    VideoTemplate(
      id: '393879757702918151',
      name: '麦当劳宠物外卖员',
      description: '上传爱宠照片，生成麦当劳宠物外卖员视频',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.delivery_dining,
      previewUrl: 'https://filecdn.minimax.chat/public/1f8061fe-f885-4778-810f-5e3a4e148deb.mp4',
    ),
    VideoTemplate(
      id: '393766210733957121',
      name: '藏族风写真',
      description: '上传面部参考图，生成藏族风视频写真',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.photo_camera,
      previewUrl: 'https://filecdn.minimax.chat/public/b7a6e34a-84bd-4f90-81a2-d9495eb19ea1.mp4',
    ),
    VideoTemplate(
      id: '394125185182695432',
      name: '生无可恋',
      description: '输入各类主角痛苦做某事，一键生成角色痛苦生活的小动画',
      requiresMedia: false,
      requiresText: true,
      icon: Icons.sentiment_very_dissatisfied,
      previewUrl: 'https://filecdn.minimax.chat/public/4f21aa52-74bd-488f-b62f-ca03fcb6ed98.mp4',
    ),
    VideoTemplate(
      id: '393857704283172864',
      name: '情书写真',
      description: '上传照片生成冬日雪景写真',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.mail,
      previewUrl: 'https://filecdn.minimax.chat/public/01f85d47-162b-4d97-856f-8ab3bf8b0101.mp4',
    ),
    VideoTemplate(
      id: '398574688191234048',
      name: '四季写真',
      description: '上传人脸照片生成四季写真',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.wb_sunny,
      previewUrl: 'https://filecdn.minimax.chat/public/571229bd-0e33-41be-80bb-716e30ba34f8.mp4',
    ),
    VideoTemplate(
      id: '393866076583718914',
      name: '女模特试穿广告',
      description: '上传服装图片，生成女模特试穿对应服装的广告',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.checkroom,
      previewUrl: 'https://filecdn.minimax.chat/public/215dc60a-8987-4fab-9041-7e2e064b3eb7.mp4',
    ),
    VideoTemplate(
      id: '393876118804459526',
      name: '男模特试穿广告',
      description: '上传服装图片，生成男模特试穿对应服装的广告',
      requiresMedia: true,
      requiresText: false,
      icon: Icons.checkroom,
      previewUrl: 'https://filecdn.minimax.chat/public/db76ea00-9919-43e9-9457-a0548430984c.mp4',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkConfigured();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _textInputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _checkConfigured() async {
    final settings = SettingsRepository();
    final configured = await settings.isConfigured();
    if (mounted) setState(() => _isConfigured = configured);
  }

  Future<void> _pickImage() async {
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
      setState(() { _selectedImageBase64 = ImageBase64.encode(bytes); _isProcessingImage = false; });
    } catch (e) {
      print('[video] error: \$e');
      setState(() { _error = '选择图片失败: $e'; _isProcessingImage = false; });
    }
  }

  void _clearImage() {
    setState(() => _selectedImageBase64 = null);
  }

  Future<void> _generateVideo() async {
    if (!_isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置 API Key'),
          backgroundColor: PixelTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusSm)),
        ),
      );
      return;
    }

    if (_selectedTemplate == null) {
      setState(() => _error = '请选择一个模板');
      return;
    }

    if (_selectedTemplate!.requiresMedia && _selectedImageBase64 == null) {
      setState(() => _error = '此模板需要上传图片');
      return;
    }

    final textValues = <String>[];
    if (_selectedTemplate!.requiresText) {
      for (final entry in _textInputs.entries) {
        if (entry.value.text.trim().isEmpty) {
          setState(() => _error = '请填写所有文本输入');
          return;
        }
        textValues.add(entry.value.text.trim());
      }
    }

    // 取消已有轮询防止重复
    _currentTaskId = null;
    setState(() {
      _isLoading = true;
      _error = null;
      _videoUrl = null;
      _status = '正在生成...';
    });

    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      if (!mounted) return;
      final client = ref.read(minimaxClientProvider);

      final result = await client.videoTemplateGeneration(
        templateId: _selectedTemplate!.id,
        textInputs: textValues.isNotEmpty ? textValues : null,
        mediaBase64Inputs: _selectedImageBase64 != null ? [_selectedImageBase64!] : null,
        callbackUrl: null,
        aigcWatermark: _aigcWatermark,
      );

      if (!mounted) return;
      _currentTaskId = result.taskId;
      _pollTaskStatus();
    } catch (e) {
      print('[video] error: \$e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _status = '';
      });
    }
  }

  Future<void> _pollTaskStatus() async {
    int retryCount = 0;
    const maxRetries = 60; // 3 分钟 (60 * 3s)
    String? lastError;

    while (_currentTaskId != null && _isLoading && retryCount < maxRetries) {
      await Future.delayed(const Duration(seconds: 3));
      retryCount++;

      try {
        await ref.read(minimaxClientProvider.notifier).loadFromSettings();
        final client = ref.read(minimaxClientProvider);
        final status = await client.getVideoTemplateTaskStatus(_currentTaskId!);

        if (!mounted) break;

        setState(() => _status = '状态: ${status.status}');

        if (status.status == 'Success' || status.status == 'success') {
          String? videoUrl = status.videoUrl;
          // 如果 videoUrl 为空，尝试通过 file_id 下载
          if ((videoUrl == null || videoUrl.isEmpty) && status.fileId != null) {
            try {
              final fileResult = await client.downloadFile(status.fileId!);
              videoUrl = fileResult.downloadUrl.isNotEmpty ? fileResult.downloadUrl : null;
            } catch (e) {
              debugPrint('[VideoTemplate] downloadFile 失败: $e');
            }
          }
          if (videoUrl != null && videoUrl.isNotEmpty) {
            setState(() {
              _videoUrl = videoUrl;
              _isLoading = false;
              _status = '完成!';
              _currentTaskId = null;
            });
            _videoHistoryRepo.addToHistory(
              prompt: _selectedTemplate?.name ?? '模板视频',
              model: _selectedTemplate?.id ?? '',
              videoUrl: videoUrl,
              templateId: _selectedTemplate?.id,
            );
          } else {
            debugPrint('[VideoTemplate] 无法获取下载链接 taskId=$_currentTaskId fileId=${status.fileId}');
            setState(() {
              _error = '视频已生成但无法获取下载链接，task_id: $_currentTaskId';
              _isLoading = false;
              _status = '';
              _currentTaskId = null;
            });
          }
          return;
        } else if (status.status == 'Fail' || status.status == 'failed') {
          setState(() {
            _error = '视频生成失败';
            _isLoading = false;
            _status = '';
            _currentTaskId = null;
          });
          return;
        }
      } catch (e) {
        lastError = e.toString();
        if (_isFatalError(e)) {
          debugPrint('[VideoTemplate] 轮询终止: $lastError');
          if (mounted) {
            setState(() {_error = lastError!; _isLoading = false; _status = '';});
          }
          return;
        }
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

  void _resumePolling() {
    if (_currentTaskId == null) return;
    setState(() { _isLoading = true; _status = '恢复查询...'; });
    _pollTaskStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isLoading && _currentTaskId != null) {
      _isLoading = false;
    } else if (state == AppLifecycleState.resumed && _currentTaskId != null && !_isLoading) {
      _resumePolling();
    }
  }

  bool _isFatalError(Object e) {
    if (e is MinimaxApiException) {
      final httpCode = e.statusCode;
      if (httpCode != null && (httpCode == 401 || httpCode == 403)) return true;
      final apiCode = e.apiCode;
      if (apiCode != null) {
        if ([1004, 1008, 2049, 2013, 1026, 1027].contains(apiCode)) return true;
      }
      if (e is PlanNotSupportedException || e is QuotaExhaustedException) return true;
    }
    return false;
  }

  void _selectTemplate(VideoTemplate template) {
    setState(() {
      _selectedTemplate = template;
      for (final c in _textInputs.values) {
        c.dispose();
      }
      _textInputs.clear();
      if (template.requiresText) {
        _textInputs['text'] = TextEditingController();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsChangedProvider, (prev, next) => _checkConfigured());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_ios_new, size: 20, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '🎭 视频模板',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: isDark ? PixelTheme.darkBorderSubtle : Colors.grey.withValues(alpha: 0.12)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isConfigured) _buildWarning(),

                    Text(
                      '选择模板',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '选择喜欢的模板，上传图片或输入文本即可生成专属视频',
                      style: TextStyle(fontSize: 12, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                    ),
                    const SizedBox(height: 16),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: _templates.length,
                      itemBuilder: (context, index) {
                        final template = _templates[index];
                        final isSelected = _selectedTemplate?.id == template.id;
                        return _buildTemplateCard(template, isSelected, key: ValueKey(template.id));
                      },
                    ),

                    if (_selectedTemplate != null) ...[
                      const SizedBox(height: 24),

                      ModernCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(_selectedTemplate!.icon, color: PixelTheme.primary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _selectedTemplate!.name,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedTemplate!.description,
                              style: TextStyle(fontSize: 13, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                            ),
                            const SizedBox(height: 16),

                            if (_selectedTemplate!.requiresMedia) ...[
                              _buildImagePicker(),
                              const SizedBox(height: 16),
                            ],

                            if (_selectedTemplate!.requiresText) ...[
                              for (final entry in _textInputs.entries)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TextField(
                                    controller: entry.value,
                                    maxLines: 2,
                                    style: TextStyle(fontSize: 14, color: isDark ? PixelTheme.darkPrimaryText : null),
                                    decoration: InputDecoration(
                                      labelText: '输入文本',
                                      hintText: '请输入内容...',
                                      hintStyle: TextStyle(color: isDark ? PixelTheme.darkTextMuted : null),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusMd)),
                                    ),
                                  ),
                                ),
                            ],

                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'AI水印',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                                      ),
                                      Text('在视频中添加水印', style: TextStyle(fontSize: 11, color: (_isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted))),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _aigcWatermark,
                                  onChanged: (v) => setState(() => _aigcWatermark = v),
                                  activeTrackColor: PixelTheme.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      if (_isLoading) ...[
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            onPressed: null,
                            isLoading: true,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.hourglass_empty, color: Colors.white, size: 20),
                                const SizedBox(width: 10),
                                Text(_status, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => setState(() { _isLoading = false; _status = '已取消（后台可能仍在生成）'; }),
                            child: Text('取消轮询', style: TextStyle(color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
                          ),
                        ),
                      ] else if (_currentTaskId != null && _videoUrl == null && _error == null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('任务仍在后台生成中', style: TextStyle(fontSize: 13, color: Colors.orange))),
                            TextButton(
                              onPressed: _resumePolling,
                              child: Text('恢复', style: TextStyle(color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary)),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            onPressed: _generateVideo,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.movie_creation, color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text('生成视频', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            onPressed: _generateVideo,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.movie_creation, color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text('生成视频', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _buildErrorCard(_error!),
                    ],

                    if (_videoUrl != null) ...[
                      const SizedBox(height: 28),
                      Text(
                        '生成结果',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary),
                      ),
                      const SizedBox(height: 14),
                      ModernCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
                                shape: BoxShape.circle,
                                border: Border.all(color: primaryColor, width: 1.5),
                              ),
                              child: Icon(Icons.check_circle, color: primaryColor, size: 48),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _status,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary),
                            ),
                            const SizedBox(height: 16),
                            VideoResultPlayer(videoUrl: _videoUrl!),
                            const SizedBox(height: 12),
                            SelectableText(
                              _videoUrl!,
                              style: TextStyle(fontSize: 12, color: primaryColor),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard(VideoTemplate template, bool isSelected, {Key? key}) {
    return GestureDetector(
      key: key,
      onTap: () => _selectTemplate(template),
      onLongPress: () => _showVideoPreview(template),
      child: Container(
        decoration: BoxDecoration(
          color: _isDark ? PixelTheme.darkSurface : PixelTheme.surface,
          borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
          border: Border.all(
            color: isSelected ? (_isDark ? PixelTheme.darkPrimary : PixelTheme.primary) : (_isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: PixelTheme.primary.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _TemplateVideoPlayer(
              previewUrl: template.previewUrl,
              icon: template.icon,
              isSelected: isSelected,
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _showVideoPreview(template),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.zoom_in, size: 16, color: Colors.white70),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                  ),
                ),
                child: Text(
                  template.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoPreview(VideoTemplate template) {
    showDialog(
      context: context,
      builder: (ctx) => _VideoPreviewDialog(template: template),
    );
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '上传图片',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: PixelTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
              border: Border.all(color: PixelTheme.pixelBorder),
            ),
            child: _isProcessingImage
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : _selectedImageBase64 != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
                        child: Image.memory(
                          ImageBase64.decodeAny(_selectedImageBase64!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 28, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text('上传', style: TextStyle(fontSize: 11, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary))),
                        ],
                      ),
          ),
        ),
        if (_selectedImageBase64 != null)
          TextButton(
            onPressed: _clearImage,
            child: Text('清除', style: TextStyle(color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
          ),
      ],
    );
  }

  Widget _buildWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PixelTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        border: Border.all(color: PixelTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: PixelTheme.error, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '请先在设置中配置 API Key',
              style: TextStyle(color: _isDark ? Colors.white : PixelTheme.error, fontWeight: FontWeight.w500),
            ),
          ),
          GradientButton(
            onPressed: () => ref.read(navigationIndexProvider.notifier).state = 4,
            child: const Text('去设置', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PixelTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        border: Border.all(color: PixelTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: PixelTheme.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(error, style: TextStyle(color: _isDark ? Colors.white : PixelTheme.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class VideoTemplate {

  VideoTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.requiresMedia,
    required this.requiresText,
    required this.icon,
    required this.previewUrl,
  });
  final String id;
  final String name;
  final String description;
  final bool requiresMedia;
  final bool requiresText;
  final IconData icon;
  final String previewUrl;
}

class _TemplateVideoPlayer extends StatefulWidget {

  const _TemplateVideoPlayer({
    required this.previewUrl,
    required this.icon,
    required this.isSelected,
  });
  final String previewUrl;
  final IconData icon;
  final bool isSelected;

  @override
  State<_TemplateVideoPlayer> createState() => _TemplateVideoPlayerState();
}

class _TemplateVideoPlayerState extends State<_TemplateVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isLoading = false;
  bool _isUserPaused = false;
  bool _isCached = false;
  String? _downloadingUrl; // 正在下载的 URL，用于防止重复/过期下载

  static final _cacheManager = DefaultCacheManager();

  @override
  void initState() {
    super.initState();
    _checkCacheThenLoad();
  }

  Future<void> _checkCacheThenLoad() async {
    // 仅选中时才初始化控制器——防止 11 个视频同时加载
    if (!widget.isSelected) return;

    final cachedFile = await _cacheManager.getFileFromCache(widget.previewUrl);
    if (cachedFile != null && cachedFile.file.existsSync()) {
      if (mounted) setState(() => _isCached = true);
      try {
        await _initFileController(cachedFile.file);
        return;
      } catch (_) {
        // 缓存文件损坏，删除后走网络播放
        await _cacheManager.removeFile(widget.previewUrl).catchError((_) {});
      }
    }
    _startPlay();
  }

  Future<void> _initFileController(File file) async {
    if (!mounted || !widget.isSelected) return;
    final oldController = _controller;
    _controller = VideoPlayerController.file(file)
      ..setLooping(true)
      ..setVolume(0);
    await _controller!.initialize();
    _onControllerReady(oldController, true);
  }

  Future<void> _initNetworkController({bool autoPlay = false}) async {
    if (!mounted || !widget.isSelected) return;
    final oldController = _controller;
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.previewUrl))
      ..setLooping(true)
      ..setVolume(0);
    await _controller!.initialize();
    _onControllerReady(oldController, autoPlay);
  }

  void _onControllerReady(VideoPlayerController? oldController, bool autoPlay) {
    if (!mounted) {
      _controller?.dispose();
      return;
    }
    oldController?.dispose();
    if (!widget.isSelected) {
      _controller!.play();
      // 延迟一帧暂停以渲染首帧缩略图
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller?.pause();
          _controller?.seekTo(Duration.zero);
        }
      });
      _isUserPaused = true;
      setState(() => _isLoading = false);
      return;
    }
    if (autoPlay) {
      _controller!.play();
    } else {
      _controller!.play();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller?.pause();
          _controller?.seekTo(Duration.zero);
        }
      });
      _isUserPaused = true;
    }
    setState(() => _isLoading = false);
  }

  @override
  void didUpdateWidget(_TemplateVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        if (_controller != null) {
          _controller!.play();
          setState(() => _isUserPaused = false);
        } else {
          _startPlay();
        }
      } else {
        // 取消选中：暂停播放并取消正在进行的下载标记
        _controller?.pause();
        _isUserPaused = false;
        _downloadingUrl = null;
      }
    }
  }

  Future<void> _startPlay() async {
    if (_controller != null) {
      _controller!.play();
      setState(() => _isUserPaused = false);
      return;
    }

    final url = widget.previewUrl;
    if (_downloadingUrl == url) return;
    _downloadingUrl = url;
    setState(() => _isLoading = true);
    try {
      await _initNetworkController(autoPlay: true);
      // 后台下载到缓存供下次使用
      _cacheManager.getSingleFile(url).then((_) {}, onError: (_) {});
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    } finally {
      if (_downloadingUrl == url) {
        _downloadingUrl = null;
      }
    }
  }

  void _togglePlay() {
    if (_controller == null) {
      _startPlay();
      return;
    }
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() => _isUserPaused = true);
    } else {
      _controller!.play();
      setState(() => _isUserPaused = false);
    }
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  bool get _isPlaying => _controller != null && _controller!.value.isPlaying;

  @override
  Widget build(BuildContext context) {
    // 视频控制器已就绪（播放中或暂停显示首帧）
    if (_controller != null && _controller!.value.isInitialized) {
      return GestureDetector(
        onTap: _togglePlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: FittedBox(fit: BoxFit.cover, child: VideoPlayer(_controller!))),
            if (!_isPlaying)
              Container(
                alignment: Alignment.center,
                color: Colors.black26,
                child: _isLoading
                    ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow, size: 28, color: Colors.white70),
                      ),
              ),
          ],
        ),
      );
    }

    // 加载中
    if (_isLoading) {
      return Container(
        color: widget.isSelected ? PixelTheme.primary.withValues(alpha: 0.15) : PixelTheme.surfaceVariant,
        child: const Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        ),
      );
    }

    // 未缓存未加载 — 静态封面
    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        color: widget.isSelected ? PixelTheme.primary.withValues(alpha: 0.15) : PixelTheme.surfaceVariant,
        child: Center(
          child: Icon(widget.icon, size: 36, color: Theme.of(context).brightness == Brightness.dark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
        ),
      ),
    );
  }
}

class _VideoPreviewDialog extends StatefulWidget {

  const _VideoPreviewDialog({required this.template});
  final VideoTemplate template;

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.template.previewUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
          _controller.setLooping(true);
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusCard)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.template.name,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (_isInitialized)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final maxH = MediaQuery.of(ctx).size.height * 0.55;
                final videoRatio = _controller.value.aspectRatio;
                final w = constraints.maxWidth;
                final h = w / videoRatio;
                final scale = h > maxH ? maxH / h : 1.0;
                return ClipRect(
                  child: SizedBox(
                    width: w * scale,
                    height: h * scale,
                    child: VideoPlayer(_controller),
                  ),
                );
              },
            )
          else
            const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(color: PixelTheme.primary)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.template.description,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
