import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/theme.dart';
import '../../../core/permission/permission_manager.dart';
import '../../../shared/utils/image_base64.dart';
import '../../../shared/utils/file_utils.dart';
import '../../chat/presentation/chat_page.dart';
import '../../settings/data/settings_repository.dart';
import '../data/vision_repository.dart';

final visionRepositoryProvider = Provider((ref) {
  final client = ref.watch(minimaxClientProvider);
  return VisionRepository(client: client);
});

class VisionPage extends ConsumerStatefulWidget {
  const VisionPage({super.key});

  @override
  ConsumerState<VisionPage> createState() => _VisionPageState();
}

class _VisionPageState extends ConsumerState<VisionPage> {
  String? _imageBase64;
  final _promptController = TextEditingController(text: '描述这张图片');
  String? _response;
  bool _isLoading = false;
  bool _isProcessingImage = false;
  bool _isConfigured = false;

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

  Future<void> _pickImage(ImageSource source) async {
    final perm = source == ImageSource.camera ? AppPermission.camera : AppPermission.storage;
    if (context.mounted) {
      final ok = await PermissionManager().request(context, perm);
      if (!ok) return;
    }
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: source, maxWidth: 3072, maxHeight: 3072, imageQuality: 90);
      if (image == null) return;
      setState(() => _isProcessingImage = true);
      final bytes = await image.readAsBytes();
      final sizeError = FileUtils.validateFileSize(bytes.length, AttachmentType.image);
      if (sizeError != null) {
        if (mounted) {
          setState(() => _isProcessingImage = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sizeError), backgroundColor: PixelTheme.error),
          );
        }
        return;
      }
      final formatError = FileUtils.validateImageFormat(bytes);
      if (formatError != null) {
        if (mounted) {
          setState(() => _isProcessingImage = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(formatError), backgroundColor: PixelTheme.error),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _isProcessingImage = false;
          _imageBase64 = base64Encode(bytes);
          _response = null;
        });
      }
    } catch (e) {
      print('[vision] error: \$e');
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选取图片失败: $e'), backgroundColor: PixelTheme.error),
        );
      }
    }
  }

  Future<void> _analyzeImage() async {
    if (_imageBase64 == null) return;

    if (!_isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在设置中配置 API Key', style: TextStyle(fontFamily: 'monospace')),
          backgroundColor: PixelTheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final response = await client.vision(_imageBase64!, _promptController.text);
      setState(() => _response = response);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsChangedProvider, (prev, next) => _checkConfigured());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final dividerColor = isDark ? PixelTheme.darkBorderSubtle : Colors.grey.withValues(alpha: 0.12);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 自定义顶部栏 - 44dp 紧凑高度
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  // 标题（Expanded 居中）
                  Expanded(
                    child: Text(
                      '👁️ 图像识别',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  // 占位保持对称
                  const SizedBox(width: 40),
                ],
              ),
            ),
            // 底部分割线
            Divider(height: 1, thickness: 0.5, color: dividerColor),
            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isConfigured)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: PixelTheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: PixelTheme.error, width: 2),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning, color: PixelTheme.error, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '请先在设置中配置 API Key',
                                style: TextStyle(fontFamily: 'monospace', color: PixelTheme.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('相册'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('拍照'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isProcessingImage)
                      Container(
                        width: double.infinity,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: PixelTheme.pixelBorder, width: 2),
                        ),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    if (_imageBase64 != null)
                      Container(
                        width: double.infinity,
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: PixelTheme.pixelBorder, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(
                            ImageBase64.decodeAny(_imageBase64!),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _promptController,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(hintText: '输入问题或指令...'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _imageBase64 == null || _isLoading ? null : _analyzeImage,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('🔍 分析图像'),
                      ),
                    ),
                    if (_response != null) ...[
                      const SizedBox(height: 24),
                      const Text('分析结果:', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: PixelTheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: PixelTheme.pixelBorder, width: 2),
                        ),
                        child: SelectableText(_response!, style: const TextStyle(fontFamily: 'monospace')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
