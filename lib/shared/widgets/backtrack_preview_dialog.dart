import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../features/chat/domain/chat_message.dart';

class BacktrackPreviewSheet extends StatelessWidget {

  const BacktrackPreviewSheet({
    required this.targetMessage, required this.messagesAfterCount, super.key,
    this.filesRolledBack = 0,
    this.canUndo = true,
  });
  final ChatMessage targetMessage;
  final int messagesAfterCount;
  final int filesRolledBack;
  final bool canUndo;

  static Future<bool?> show({
    required BuildContext context,
    required ChatMessage targetMessage,
    required int messagesAfterCount,
    int filesRolledBack = 0,
    bool canUndo = true,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BacktrackPreviewSheet(
        targetMessage: targetMessage,
        messagesAfterCount: messagesAfterCount,
        filesRolledBack: filesRolledBack,
        canUndo: canUndo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(PixelTheme.radiusLg)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: (isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.restore, size: 22, color: PixelTheme.warning),
                  const SizedBox(width: 8),
                  Text(
                    '回溯到此消息',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Target message preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
                      border: Border.all(
                        color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '保留到此处：',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          targetMessage.content.length > 120
                              ? '${targetMessage.content.substring(0, 120)}...'
                              : targetMessage.content,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ImpactRow(
                    icon: Icons.chat_bubble_outline,
                    label: '将丢弃消息',
                    value: '$messagesAfterCount 条',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  if (filesRolledBack > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ImpactRow(
                        icon: Icons.file_copy,
                        label: '将回滚文件',
                        value: '$filesRolledBack 个',
                        isDark: isDark,
                        isWarning: true,
                      ),
                    ),
                  // Info note
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? PixelTheme.warning.withValues(alpha: 0.08)
                          : PixelTheme.warning.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
                      border: Border.all(
                        color: PixelTheme.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: PixelTheme.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            canUndo ? '此操作可以通过撤销按钮恢复' : '此操作不可撤销',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
                        ),
                        side: BorderSide(
                          color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder,
                        ),
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PixelTheme.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
                        ),
                      ),
                      child: const Text(
                        '确认回溯',
                        style: TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {

  const _ImpactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.isWarning = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isWarning ? PixelTheme.error : (isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isWarning ? PixelTheme.error : (isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText),
          ),
        ),
      ],
    );
  }
}
