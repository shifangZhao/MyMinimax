// ignore_for_file: avoid_dynamic_calls

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/utils/image_base64.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import '../../../app/theme.dart';
import '../../../core/permission/permission_manager.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/utils/snackbar_utils.dart';
import '../../../shared/utils/file_utils.dart';
import '../../../app/app.dart' show navigationIndexProvider;
import '../../../shared/widgets/model_dropdown.dart';
import '../../../shared/widgets/expandable_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/error_card.dart';
import '../../../shared/widgets/settings_warning_card.dart';
import '../../../shared/widgets/generate_button.dart';
import '../../chat/presentation/chat_page.dart' show minimaxClientProvider, settingsChangedProvider;
import '../../settings/data/settings_repository.dart';
import '../data/image_history_repository.dart';
import 'image_history_page.dart';

final _ratioOptions = ['1:1', '16:9', '9:16', '4:3', '3:4'];

class ImageGenPage extends ConsumerStatefulWidget {
  const ImageGenPage({super.key});

  @override
  ConsumerState<ImageGenPage> createState() => _ImageGenPageState();
}

class _ImageGenPageState extends ConsumerState<ImageGenPage> {
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  final _promptController = TextEditingController();
  List<String> _generatedImages = [];
  bool _isLoading = false;
  bool _isProcessingImage = false;
  bool _isConfigured = false;
  String? _error;
  String _selectedModel = 'image-01';
  String? _referenceImageBase64;
  String _selectedRatio = '16:9';
  String _selectedCount = '1';
  bool _promptOptimizer = false;
  bool _aigcWatermark = false;
  bool _referenceExpanded = false;
  int _successCount = 0;
  int _failedCount = 0;

  final _countOptions = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];
  final _imageHistoryRepo = ImageHistoryRepository();

  @override
  void initState() {
    super.initState();
    _checkConfigured();
  }

  Future<void> _checkConfigured() async {
    final settings = SettingsRepository();
    final configured = await settings.isConfigured();
    if (mounted) setState(() => _isConfigured = configured);
  }

  Future<void> _pickReferenceImage() async {
    try {
      final ok = await PermissionManager().request(context, AppPermission.storage);
      if (!ok) return;
      final picker = ImagePicker();
      final picker2 = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 85);
      if (picker2 == null) return;
      setState(() => _isProcessingImage = true);
      final bytes = await picker2.readAsBytes();
      final sizeError = FileUtils.validateFileSize(bytes.length, AttachmentType.image);
      if (sizeError != null) {
        if (mounted) setState(() { _error = sizeError; _isProcessingImage = false; });
        return;
      }
      final formatError = FileUtils.validateImageFormat(bytes);
      if (formatError != null) {
        if (mounted) setState(() { _error = formatError; _isProcessingImage = false; });
        return;
      }
      final mime = picker2.mimeType ?? 'image/jpeg';
      if (mounted) {
        setState(() { _referenceImageBase64 = ImageBase64.encode(bytes); _isProcessingImage = false; });
      }
    } catch (e) {
      print('[image] error: \$e');
      if (mounted) setState(() { _error = '选择图片失败: $e'; _isProcessingImage = false; });
    }
  }

  void _onRatioChanged(String ratio) => setState(() => _selectedRatio = ratio);
  void _onCountChanged(String count) => setState(() => _selectedCount = count);
  void _onModelChanged(String model) => setState(() => _selectedModel = model);
  void _onOptimizerChanged(bool v) => setState(() => _promptOptimizer = v);
  void _onWatermarkChanged(bool v) => setState(() => _aigcWatermark = v);
  void _clearReferenceImage() => setState(() => _referenceImageBase64 = null);

  Future<void> _generateImage() async {
    if (!_isConfigured) {
      showSnackBar(context, '请先在设置中配置 API Key', isError: true);
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _generatedImages = [];
    });

    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);

      dynamic result;
      if (_referenceImageBase64 != null) {
        result = await client.imageToImage(
          imageBase64: _referenceImageBase64!,
          prompt: prompt,
          model: _selectedModel,
          ratio: _selectedRatio,
          n: int.parse(_selectedCount),
          promptOptimizer: _promptOptimizer,
          aigcWatermark: _aigcWatermark,
        );
      } else {
        result = await client.imageGenerate(
          prompt,
          model: _selectedModel,
          ratio: _selectedRatio,
          n: int.parse(_selectedCount),
          promptOptimizer: _promptOptimizer,
          aigcWatermark: _aigcWatermark,
        );
      }

      setState(() {
        _generatedImages = result.base64Images.isNotEmpty
            ? result.base64Images
            : result.imageUrls;
        _successCount = result.successCount;
        _failedCount = result.failedCount;
        _isLoading = false;
      });

      if (_generatedImages.isNotEmpty) {
        _imageHistoryRepo.addToHistory(
          prompt: prompt,
          model: _selectedModel,
          ratio: _selectedRatio,
          images: _generatedImages,
        );
      }
    } catch (e) {
      print('[image] error: \$e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsChangedProvider, (prev, next) => _checkConfigured());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Column(
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
                        const Icon(Icons.image_outlined, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '图像生成',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      icon: Icon(Icons.photo_library_outlined, size: 20,
                        color: isDark ? PixelTheme.darkSecondaryText : (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageHistoryPage()));
                      },
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ]),
              ),
              Divider(height: 0.5, thickness: 0.5,
                color: PixelTheme.dividerFor(isDark)),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isConfigured)
                    SettingsWarningCard(
                      onNavigateToSettings: () => ref.read(navigationIndexProvider.notifier).state = 4,
                    ),

                  ModernCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ModelDropdown(
                          label: '选择模型',
                          selectedModel: _selectedModel,
                          models: const ['image-01', 'image-01-live'],
                          modelDescriptions: const {
                            'image-01': '画面表现细腻，支持文生图和图生图',
                            'image-01-live': '手绘、卡通等画风增强，支持文生图和图生图',
                          },
                          onChanged: _onModelChanged,
                        ),
                        const SizedBox(height: 20),
                        ExpandableCard(
                          expanded: _referenceExpanded,
                          onToggle: () => setState(() => _referenceExpanded = !_referenceExpanded),
                          header: Row(children: [
                            const Icon(Icons.person_add, size: 18, color: PixelTheme.primary),
                            const SizedBox(width: 8),
                            Text('人像参考图片（可选）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
                          ]),
                          content: _buildReferenceImagePickerContent(),
                        ),
                        const SizedBox(height: 20),
                        const SectionTitle(title: '提示词'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _promptController,
                          minLines: 1,
                          maxLines: 6,
                          style: TextStyle(fontSize: 14, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: '描述你想要生成的图片...',
                            hintStyle: TextStyle(color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusMd)),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ModelDropdown(
                          label: '图片比例',
                          selectedModel: _selectedRatio,
                          models: _ratioOptions,
                          onChanged: _onRatioChanged,
                        ),
                        const SizedBox(height: 20),
                        ModelDropdown(
                          label: '生成数量',
                          selectedModel: _selectedCount,
                          models: _countOptions,
                          onChanged: _onCountChanged,
                        ),
                        const SizedBox(height: 20),
                        _buildToggleRow('优化提示词', '自动优化提示词效果', _promptOptimizer, _onOptimizerChanged),
                        const SizedBox(height: 12),
                        _buildToggleRow('AI水印', '在图片中添加水印', _aigcWatermark, _onWatermarkChanged),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  GenerateButton(
                    label: '生成图片',
                    icon: Icons.auto_awesome,
                    onPressed: _generateImage,
                    isLoading: _isLoading,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    ErrorCard(message: _error!),
                  ],

                  if (_generatedImages.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Row(children: [
                      const SectionTitle(title: '生成结果', fontSize: 18),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _successCount > 0 ? PixelTheme.success.withValues(alpha: 0.15) : PixelTheme.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '成功 $_successCount / 失败 $_failedCount',
                          style: TextStyle(
                            fontSize: 12,
                            color: _successCount > 0 ? PixelTheme.success : PixelTheme.error,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _buildImageGrid(),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildToggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title: title),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 11, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary))),
          ],
        ),
      ),
      Switch(value: value, onChanged: onChanged, activeThumbColor: PixelTheme.primary),
    ]);
  }

  Widget _buildReferenceImagePickerContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: PixelTheme.surfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
          ),
          child: Text(
            '上传单人正面照片作为人物参考，生成保持该人物特征的新图片',
            style: TextStyle(fontSize: 11, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickReferenceImage,
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
                : _referenceImageBase64 != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
                        child: Image.memory(ImageBase64.decodeAny(_referenceImageBase64!), fit: BoxFit.cover),
                      )
                    : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add, size: 28, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text('上传', style: TextStyle(fontSize: 11, color: (_isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary))),
                    ],
                  ),
          ),
        ),
        if (_referenceImageBase64 != null)
          TextButton(onPressed: _clearReferenceImage, child: const Text('清除')),
      ],
    );
  }

  int _currentImagePage = 0;

  Widget _buildImageGrid() {
    if (_generatedImages.length == 1) {
      final img = _generatedImages.first;
      return GestureDetector(
        onTap: () => _showImageDialog(img),
        onLongPress: () => _showImageOptions(img),
        child: AspectRatio(
          aspectRatio: 1,
          child: _buildImageItem(img),
        ),
      );
    }

    return Column(children: [
      SizedBox(
        height: 280,
        child: PageView.builder(
          onPageChanged: (i) => setState(() => _currentImagePage = i),
          itemCount: _generatedImages.length,
          controller: PageController(viewportFraction: 0.85),
          itemBuilder: (ctx, i) {
            final img = _generatedImages[i];
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 8, right: i == _generatedImages.length - 1 ? 0 : 8),
              child: GestureDetector(
                onTap: () => _showImageDialog(img),
                onLongPress: () => _showImageOptions(img),
                child: _buildImageItem(img),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_generatedImages.length, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentImagePage == i ? 8 : 6,
          height: _currentImagePage == i ? 8 : 6,
          decoration: BoxDecoration(
            color: _currentImagePage == i ? PixelTheme.primary : (_isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
            shape: BoxShape.circle,
          ),
        )),
      ),
    ]);
  }

  Widget _buildImageItem(String img) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        child: img.startsWith('data:') || img.startsWith('/9j')
            ? Image.memory(ImageBase64.decodeAny(img), fit: BoxFit.cover)
            : Image.network(img, fit: BoxFit.cover, loadingBuilder: (ctx, child, loading) {
                if (loading == null) return child;
                return Container(
                  color: PixelTheme.surfaceVariant,
                  child: const Center(child: CometLoader()),
                );
              }, errorBuilder: (ctx, err, stack) {
                return Container(
                  color: PixelTheme.surfaceVariant,
                  child: Center(child: Icon(Icons.broken_image, size: 40, color: (_isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted))),
                );
              }),
      ),
    );
  }

  void _showImageDialog(String img) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(PixelTheme.radiusLg),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
                child: img.startsWith('data:') || img.startsWith('/9j')
                    ? Image.memory(ImageBase64.decodeAny(img), fit: BoxFit.contain)
                    : Image.network(img, fit: BoxFit.contain, loadingBuilder: (ctx, child, loading) {
                      if (loading == null) return child;
                      return Container(
                        width: ResponsiveHelper.previewHeight(context),
                        height: ResponsiveHelper.previewHeight(context),
                        color: PixelTheme.surfaceVariant,
                        child: const Center(child: CometLoader()),
                      );
                    }, errorBuilder: (ctx, err, stack) {
                      return Container(
                        width: ResponsiveHelper.previewHeight(context),
                        height: ResponsiveHelper.previewHeight(context),
                        color: PixelTheme.surfaceVariant,
                        child: const Center(child: Icon(Icons.broken_image, size: 40)),
                      );
                    }),
              ),
            ),
            const SizedBox(height: 20),
            GradientButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageOptions(String img) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: PixelTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: (_isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.open_in_browser, color: PixelTheme.primary),
                title: Text('在浏览器中打开', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!img.startsWith('data:')) {
                    final uri = Uri.parse(img);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.link, color: PixelTheme.primary),
                title: Text('复制图片链接', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!img.startsWith('data:')) {
                    await Clipboard.setData(ClipboardData(text: img));
                    if (mounted) {
                      showSnackBar(context, '已复制到剪贴板');
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt, color: PixelTheme.primary),
                title: Text('保存图片', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveImage(img);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveImage(String img) async {
    try {
      Uint8List? bytes;
      String filename = 'image_${DateTime.now().millisecondsSinceEpoch}';

      if (img.startsWith('data:')) {
        bytes = ImageBase64.decodeAny(img);
        filename += '.png';
      } else {
        final dio = Dio();
        final response = await dio.get<List<int>>(img, options: Options(responseType: ResponseType.bytes));
        final data = response.data;
        if (data == null) {
          setState(() => _error = '下载图片失败：响应为空');
          return;
        }
        bytes = Uint8List.fromList(data);
        filename += '.jpg';
      }

      if (Platform.isAndroid || Platform.isIOS) {
        // 保存到相册
        final ok = await PermissionManager().request(context, AppPermission.storage,
          reason: '将生成的图片保存到系统相册');
        if (!ok) return;
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$filename');
        await tempFile.writeAsBytes(bytes);
        await Gal.putImage(tempFile.path, album: 'MyMinimax');
        if (mounted) {
          showSnackBar(context, '图片已保存到相册');
        }
      } else {
        if (mounted) {
          showSnackBar(context, 'Web平台请长按图片另存为');
        }
      }
    } catch (e) {
      print('[image] error: \$e');
      if (mounted) {
        showSnackBar(context, '保存失败: $e', isError: true);
      }
    }
  }
}
