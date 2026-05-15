import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/audio_player.dart';
import '../domain/music_history_item.dart';
import '../data/music_history_repository.dart';

class MusicHistoryPage extends StatefulWidget {
  const MusicHistoryPage({super.key});
  @override
  State<MusicHistoryPage> createState() => _MusicHistoryPageState();
}

class _MusicHistoryPageState extends State<MusicHistoryPage> {
  final _repository = MusicHistoryRepository();
  List<MusicHistoryItem> _items = [];
  bool _isLoading = true;
  bool _manageMode = false;

  @override
  void initState() { super.initState(); _loadHistory(); }

  Future<void> _loadHistory() async {
    final items = await _repository.getHistory();
    if (mounted) setState(() { _items = items; _isLoading = false; });
  }

  Future<void> _deleteItem(MusicHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PixelTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixelTheme.radiusLg),
          side: const BorderSide(color: PixelTheme.pixelBorder, width: 2),
        ),
        title: const Text('删除记录', style: TextStyle(fontFamily: 'monospace', fontSize: 16)),
        content: const Text('确定要删除这条音乐记录吗？', style: TextStyle(fontFamily: 'monospace')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(fontFamily: 'monospace'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(fontFamily: 'monospace', color: PixelTheme.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await _repository.deleteFromHistory(item.id, item.localPath);
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? PixelTheme.darkBase : PixelTheme.background;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final secColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('音乐历史', style: TextStyle(fontFamily: 'monospace')),
        centerTitle: true, backgroundColor: bgColor, foregroundColor: textColor, elevation: 0,
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
                  child: Text(_manageMode ? '完成' : '管理',
                    style: TextStyle(fontSize: 12, color: _manageMode ? PixelTheme.primary : secColor)),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.music_note_outlined, size: 64, color: secColor.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('暂无生成记录', style: TextStyle(fontFamily: 'monospace', fontSize: 16, color: textColor)),
                  const SizedBox(height: 8),
                  Text('生成的音乐会保存在这里', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: secColor)),
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: PixelTheme.primary),
                    child: const Text('返回', style: TextStyle(color: Colors.white))),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(12), itemCount: _items.length,
                  itemBuilder: (ctx, index) => _buildCard(_items[index], isDark, secColor)),
    );
  }

  Widget _buildCard(MusicHistoryItem item, bool isDark, Color secColor) {
    final cardColor = isDark ? PixelTheme.darkSurface : PixelTheme.surface;
    final borderColor = isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder;
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(PixelTheme.radiusMd), border: Border.all(color: borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE91E63), Color(0xFF9C27B0)]), borderRadius: BorderRadius.circular(PixelTheme.radiusSm)),
            child: const Icon(Icons.music_note, color: Colors.white, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.prompt, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
            const SizedBox(height: 4),
            Row(children: [
              if (item.formattedDuration.isNotEmpty) ...[Text(item.formattedDuration, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: PixelTheme.primary)), const SizedBox(width: 8)],
              if (item.isInstrumental) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant, borderRadius: BorderRadius.circular(4)), child: Text('纯音乐', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: secColor))),
              const SizedBox(width: 8),
              Text(item.formattedDate, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: secColor)),
            ]),
          ])),
          if (_manageMode)
            GestureDetector(onTap: () => _deleteItem(item),
              child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.black12, shape: BoxShape.circle),
                child: const Icon(Icons.delete, size: 20, color: PixelTheme.error))),
        ]),
        const SizedBox(height: 10),
        AudioPlayerWidget(localPath: item.localPath, title: item.prompt),
      ]),
    );
  }
}
