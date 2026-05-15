import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/video_result_player.dart';
import '../../../shared/utils/snackbar_utils.dart';
import '../data/video_history_repository.dart';
import '../domain/video_history_item.dart';

class VideoHistoryPage extends StatefulWidget {
  const VideoHistoryPage({super.key});

  @override
  State<VideoHistoryPage> createState() => _VideoHistoryPageState();
}

class _VideoHistoryPageState extends State<VideoHistoryPage> {
  final _repository = VideoHistoryRepository();
  List<VideoHistoryItem> _items = [];
  bool _manageMode = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final items = await _repository.getHistory();
    if (mounted) setState(() => _items = items);
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

  void _playVideo(String url, bool isDark) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [
            VideoResultPlayer(videoUrl: url),
            Positioned(
              top: 8, right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.close, color: Colors.white, size: 18)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _deleteItem(VideoHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dk = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: dk ? PixelTheme.darkSurface : PixelTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PixelTheme.radiusLg),
            side: BorderSide(color: dk ? PixelTheme.darkBorderSubtle : PixelTheme.pixelBorder, width: 2),
          ),
          title: Text('删除记录', style: TextStyle(fontFamily: 'monospace', fontSize: 16, color: dk ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
          content: Text('确定要删除这条视频生成记录吗？', style: TextStyle(fontFamily: 'monospace', color: dk ? PixelTheme.darkSecondaryText : PixelTheme.textPrimary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('取消', style: TextStyle(fontFamily: 'monospace', color: dk ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(fontFamily: 'monospace', color: PixelTheme.error))),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _repository.deleteFromHistory(item.id);
      _loadHistory();
    }
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
        title: Text('视频历史', style: TextStyle(fontFamily: 'monospace', color: textColor)),
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
                    color: _manageMode ? PixelTheme.primary.withValues(alpha: 0.15) : (isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _manageMode ? (isDark ? PixelTheme.darkPrimary : PixelTheme.primary) : (isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder)),
                  ),
                  child: Text(
                    _manageMode ? '完成' : '管理',
                    style: TextStyle(fontSize: 12, color: _manageMode ? (isDark ? PixelTheme.darkPrimary : PixelTheme.primary) : (isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_outlined, size: 64, color: secondaryTextColor.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      Text('暂无生成记录', style: TextStyle(fontFamily: 'monospace', fontSize: 16, color: textColor)),
                      const SizedBox(height: 8),
                      Text('生成的视频链接会自动保存在这里', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: secondaryTextColor)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(backgroundColor: isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
                        child: const Text('返回', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (ctx, index) {
                    final item = _items[index];
                    return _buildCard(item, isDark, secondaryTextColor);
                  },
                ),
    );
  }

  Widget _buildCard(VideoHistoryItem item, bool isDark, Color secondaryColor) {
    final cardColor = isDark ? PixelTheme.darkSurface : PixelTheme.surface;
    final borderColor = isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder;

    return GestureDetector(
      onTap: _manageMode ? null : () {
        if (item.videoUrl != null) _playVideo(item.videoUrl!, isDark);
      },
      onLongPress: _manageMode ? null : () {
        if (item.videoUrl != null) {
          showModalBottomSheet(
            context: context,
            enableDrag: true,
            backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (ctx) {
              final dk2 = Theme.of(ctx).brightness == Brightness.dark;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 32, height: 4, margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
                      ListTile(
                        leading: Icon(Icons.play_circle_fill, color: dk2 ? PixelTheme.darkPrimary : PixelTheme.primary),
                        title: Text('播放视频', style: TextStyle(fontFamily: 'monospace', color: dk2 ? PixelTheme.darkPrimaryText : null)),
                        onTap: () { Navigator.pop(ctx); _playVideo(item.videoUrl!, isDark); },
                      ),
                      ListTile(
                        leading: Icon(Icons.open_in_browser, color: dk2 ? PixelTheme.darkSecondaryText : null),
                        title: Text('在浏览器中打开', style: TextStyle(fontFamily: 'monospace', color: dk2 ? PixelTheme.darkPrimaryText : null)),
                        onTap: () { Navigator.pop(ctx); launchUrl(Uri.parse(item.videoUrl!), mode: LaunchMode.externalApplication); },
                      ),
                      ListTile(
                        leading: Icon(Icons.download, color: dk2 ? PixelTheme.darkSecondaryText : null),
                        title: Text('下载到本地', style: TextStyle(fontFamily: 'monospace', color: dk2 ? PixelTheme.darkPrimaryText : null)),
                        onTap: () { Navigator.pop(ctx); _downloadVideo(item.videoUrl!); },
                      ),
                      ListTile(
                        leading: Icon(Icons.copy, color: dk2 ? PixelTheme.darkSecondaryText : null),
                        title: Text('复制视频链接', style: TextStyle(fontFamily: 'monospace', color: dk2 ? PixelTheme.darkPrimaryText : null)),
                        onTap: () {
                          Navigator.pop(ctx);
                          Clipboard.setData(ClipboardData(text: item.videoUrl!));
                          showSnackBar(context, '链接已复制');
                        },
                      ),
                      Divider(color: dk2 ? PixelTheme.darkBorderSubtle : null),
                      ListTile(
                        leading: const Icon(Icons.delete_outline, color: PixelTheme.error),
                        title: const Text('删除记录', style: TextStyle(fontFamily: 'monospace', color: PixelTheme.error)),
                        onTap: () { Navigator.pop(ctx); _deleteItem(item); },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: PixelTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
              ),
              child: const Icon(Icons.play_circle_fill, color: PixelTheme.primary, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.formattedDuration.isNotEmpty) ...[
                        Text(item.formattedDuration, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: PixelTheme.primary)),
                        const SizedBox(width: 8),
                      ],
                      if (item.resolution != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(item.resolution!, style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(item.formattedDate, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: secondaryColor)),
                      if (item.templateId != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)]),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('模板', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!_manageMode && item.videoUrl != null)
              Icon(Icons.chevron_right, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted, size: 20),
            if (_manageMode)
              GestureDetector(
                onTap: () => _deleteItem(item),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: isDark ? PixelTheme.darkElevated : Colors.black12, shape: BoxShape.circle),
                  child: const Icon(Icons.delete, size: 20, color: PixelTheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
