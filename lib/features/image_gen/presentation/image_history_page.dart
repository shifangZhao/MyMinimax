import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/utils/image_base64.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme.dart';
import '../../../shared/utils/snackbar_utils.dart';
import '../data/image_history_repository.dart';
import '../domain/image_history_item.dart';

class ImageHistoryPage extends StatefulWidget {
  const ImageHistoryPage({super.key});

  @override
  State<ImageHistoryPage> createState() => _ImageHistoryPageState();
}

class _ImageHistoryPageState extends State<ImageHistoryPage> {
  final _repository = ImageHistoryRepository();
  List<ImageHistoryItem> _items = [];
  bool _isLoading = true;
  bool _manageMode = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final items = await _repository.getHistory();
    if (mounted) setState(() { _items = items; _isLoading = false; });
  }

  Future<void> _deleteItem(ImageHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PixelTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixelTheme.radiusLg),
          side: const BorderSide(color: PixelTheme.pixelBorder, width: 2),
        ),
        title: const Text('删除记录', style: TextStyle(fontFamily: 'monospace', fontSize: 16)),
        content: const Text('确定要删除这条生成记录吗？图片数据将永久丢失。', style: TextStyle(fontFamily: 'monospace')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(fontFamily: 'monospace'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(fontFamily: 'monospace', color: PixelTheme.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await _repository.deleteFromHistory(item.id);
      _loadHistory();
    }
  }

  // ─── 全屏预览（支持左右滑动） ──────────────────────────

  void _showFullImage(ImageHistoryItem item, int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) => _FullImagePreview(
        item: item,
        initialIndex: initialIndex,
      ),
    );
  }

  // ─── 长按选项 ──────────────────────────────────────────

  void _showOptions(ImageHistoryItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final firstImage = item.images.first;
    final isUrl = !(firstImage.startsWith('data:') || firstImage.startsWith('/9j'));

    showModalBottomSheet(
      context: context,
      enableDrag: true,
      backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('查看大图', style: TextStyle(fontFamily: 'monospace')),
                onTap: () { Navigator.pop(ctx); _showFullImage(item, 0); },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('保存图片', style: TextStyle(fontFamily: 'monospace')),
                onTap: () { Navigator.pop(ctx); _saveImage(firstImage); },
              ),
              if (isUrl) ...[
                ListTile(
                  leading: const Icon(Icons.open_in_browser),
                  title: const Text('在浏览器中打开', style: TextStyle(fontFamily: 'monospace')),
                  onTap: () { Navigator.pop(ctx); launchUrl(Uri.parse(firstImage), mode: LaunchMode.externalApplication); },
                ),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('复制图片链接', style: TextStyle(fontFamily: 'monospace')),
                  onTap: () { Navigator.pop(ctx); Clipboard.setData(ClipboardData(text: firstImage)); showSnackBar(context, '链接已复制'); },
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: PixelTheme.error),
                title: const Text('删除记录', style: TextStyle(fontFamily: 'monospace', color: PixelTheme.error)),
                onTap: () { Navigator.pop(ctx); _deleteItem(item); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveImage(String img) async {
    try {
      final Uint8List bytes;
      String ext;
      if (img.startsWith('data:')) {
        bytes = ImageBase64.decodeAny(img);
        ext = img.contains('image/png') ? 'png' : 'jpg';
      } else if (img.startsWith('/9j')) {
        bytes = ImageBase64.decodeAny(img);
        ext = 'jpg';
      } else {
        final dio = Dio();
        final response = await dio.get(img, options: Options(responseType: ResponseType.bytes));
        bytes = Uint8List.fromList(response.data);
        ext = 'png';
      }
      final directory = await getTemporaryDirectory();
      final filename = 'image_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes);
      if (mounted) {
        showSnackBar(context, '已保存到: ${file.path}');
      }
    } catch (e) {
      print('[image] error: \$e');
      if (mounted) {
        showSnackBar(context, '保存失败: $e', isError: true);
      }
    }
  }

  Widget _buildImageWidget(String img) {
    if (img.startsWith('data:') || img.startsWith('/9j')) {
      final base64 = img.startsWith('data:') ? img.substring(img.indexOf(',') + 1) : img;
      return Image.memory(ImageBase64.decodeAny(base64), fit: BoxFit.cover);
    }
    return Image.network(img, fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(color: PixelTheme.surfaceVariant, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
      },
      errorBuilder: (_, __, ___) => Container(color: PixelTheme.surfaceVariant, child: const Center(child: Icon(Icons.broken_image, color: PixelTheme.textMuted))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? PixelTheme.darkBase : PixelTheme.background;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('图像历史', style: TextStyle(fontFamily: 'monospace')),
        centerTitle: true,
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        actions: [
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _manageMode = !_manageMode),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _manageMode ? PixelTheme.primary.withValues(alpha: 0.15) : PixelTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _manageMode ? PixelTheme.primary : PixelTheme.pixelBorder),
                  ),
                  child: Text(
                    _manageMode ? '完成' : '管理',
                    style: TextStyle(fontSize: 12, color: _manageMode ? PixelTheme.primary : secondaryTextColor),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? _buildEmptyState(isDark, textColor, secondaryTextColor)
              : _buildGrid(isDark, secondaryTextColor),
    );
  }

  Widget _buildEmptyState(bool isDark, Color textColor, Color secondaryTextColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: secondaryTextColor.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('暂无生成记录', style: TextStyle(fontFamily: 'monospace', fontSize: 16, color: textColor)),
          const SizedBox(height: 8),
          Text('生成的图片会自动保存在这里', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: secondaryTextColor)),
          const SizedBox(height: 24),
          GradientButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(bool isDark, Color secondaryTextColor) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.75,
      ),
      itemCount: _items.length,
      itemBuilder: (ctx, index) {
        final item = _items[index];
        return _buildHistoryCard(item, isDark, secondaryTextColor);
      },
    );
  }

  Widget _buildHistoryCard(ImageHistoryItem item, bool isDark, Color secondaryTextColor) {
    final cardColor = isDark ? PixelTheme.darkSurface : PixelTheme.surface;
    final borderColor = isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder;

    return GestureDetector(
      onTap: _manageMode ? null : () => _showFullImage(item, 0),
      onLongPress: _manageMode ? null : () => _showOptions(item),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
          border: Border.all(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 缩略图区域
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: _buildImageWidget(item.images.first),
                  ),
                ),
                // 信息区域
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            item.imageCountLabel,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: PixelTheme.primary),
                          ),
                          const Spacer(),
                          Text(
                            item.formattedDate,
                            style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 管理模式：删除覆盖层
            if (_manageMode)
              Positioned(
                top: 6, right: 6,
                child: GestureDetector(
                  onTap: () => _deleteItem(item),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete, size: 18, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 全屏预览组件（支持 PageView 左右滑动） ─────────────────

class _FullImagePreview extends StatefulWidget {

  const _FullImagePreview({required this.item, required this.initialIndex});
  final ImageHistoryItem item;
  final int initialIndex;

  @override
  State<_FullImagePreview> createState() => _FullImagePreviewState();
}

class _FullImagePreviewState extends State<_FullImagePreview> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildImageWidget(String img) {
    if (img.startsWith('data:') || img.startsWith('/9j')) {
      final base64 = img.startsWith('data:') ? img.substring(img.indexOf(',') + 1) : img;
      return Image.memory(ImageBase64.decodeAny(base64), fit: BoxFit.contain);
    }
    return Image.network(img, fit: BoxFit.contain,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)));
      },
      errorBuilder: (_, __, ___) => Container(color: Colors.black, child: const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48))),
    );
  }

  void _showImageActions(String img) {
    final isUrl = !(img.startsWith('data:') || img.startsWith('/9j'));

    showModalBottomSheet(
      context: context,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt, color: Colors.white),
                  title: const Text('保存图片', style: TextStyle(color: Colors.white)),
                  onTap: () { Navigator.pop(ctx); _saveCurrentImage(img); },
                ),
                if (isUrl) ...[
                  ListTile(
                    leading: const Icon(Icons.open_in_browser, color: Colors.white),
                    title: const Text('在浏览器中打开', style: TextStyle(color: Colors.white)),
                    onTap: () { Navigator.pop(ctx); launchUrl(Uri.parse(img), mode: LaunchMode.externalApplication); },
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy, color: Colors.white),
                    title: const Text('复制图片链接', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: img));
                      showSnackBar(context, '链接已复制');
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.item.images;

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图片 PageView
            GestureDetector(
              onTap: () {}, // 阻止点击图片关闭
              onLongPress: () => _showImageActions(images[_currentIndex]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _currentIndex = i),
                    itemBuilder: (_, i) => _buildImageWidget(images[i]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 页码指示器
            if (images.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _currentIndex ? PixelTheme.primary : Colors.grey.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            if (images.length > 1) ...[
              const SizedBox(height: 4),
              Text(
                '${_currentIndex + 1} / ${images.length}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveCurrentImage(String img) async {
    try {
      final Uint8List bytes;
      String ext;
      if (img.startsWith('data:')) {
        bytes = ImageBase64.decodeAny(img);
        ext = img.contains('image/png') ? 'png' : 'jpg';
      } else if (img.startsWith('/9j')) {
        bytes = ImageBase64.decodeAny(img);
        ext = 'jpg';
      } else {
        final dio = Dio();
        final response = await dio.get(img, options: Options(responseType: ResponseType.bytes));
        bytes = Uint8List.fromList(response.data);
        ext = 'png';
      }
      final directory = await getTemporaryDirectory();
      final filename = 'image_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes);
      if (mounted) {
        showSnackBar(context, '已保存到: ${file.path}');
      }
    } catch (e) {
      print('[image] error: \$e');
      if (mounted) {
        showSnackBar(context, '保存失败: $e', isError: true);
      }
    }
  }
}
