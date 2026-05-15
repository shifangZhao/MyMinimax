import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../features/chat/domain/chat_message.dart';

enum MessageAction {
  edit,
  retry,
  branch,
  delete,
  copy,
  backtrack,
}

class MessageActionSheet extends StatelessWidget {

  const MessageActionSheet({
    required this.message, required this.isLastUserMessage, required this.onAction, super.key,
  });
  final ChatMessage message;
  final bool isLastUserMessage;
  final void Function(MessageAction action) onAction;

  static void show({
    required BuildContext context,
    required ChatMessage message,
    required bool isLastUserMessage,
    required void Function(MessageAction action) onAction,
  }) {
    showModalBottomSheet(
      context: context,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MessageActionSheet(
        message: message,
        isLastUserMessage: isLastUserMessage,
        onAction: onAction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.isUser;
    final isAssistant = message.isAssistant;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(PixelTheme.radiusLg)),
      ),
      padding: const EdgeInsets.only(bottom: 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isUser ? Icons.person : Icons.smart_toy,
                    size: 18,
                    color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isUser ? '用户消息操作' : '助手消息操作',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (isUser) ...[
              _ActionTile(
                icon: Icons.edit,
                label: '编辑消息',
                subtitle: '修改此消息并重新生成回复',
                color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary,
                onTap: () {
                  Navigator.pop(context);
                  HapticFeedback.lightImpact();
                  onAction(MessageAction.edit);
                },
              ),
              if (!isLastUserMessage) ...[
                _ActionTile(
                  icon: Icons.refresh,
                  label: '从此处重新生成',
                  subtitle: '保留此消息，重新生成后续回复',
                  color: isDark ? PixelTheme.darkAccent : PixelTheme.accent,
                  onTap: () {
                    Navigator.pop(context);
                    HapticFeedback.lightImpact();
                    onAction(MessageAction.retry);
                  },
                ),
              ],
              _ActionTile(
                icon: Icons.call_split,
                label: '从此处创建分支',
                subtitle: '创建一个新的对话分支',
                color: isDark ? PixelTheme.darkSecondary : PixelTheme.secondary,
                onTap: () {
                  Navigator.pop(context);
                  HapticFeedback.lightImpact();
                  onAction(MessageAction.branch);
                },
              ),
              if (!isLastUserMessage)
                _ActionTile(
                  icon: Icons.delete_outline,
                  label: '删除此处之后的消息',
                  subtitle: '回溯到此消息（可撤销）',
                  color: PixelTheme.error,
                  onTap: () {
                    Navigator.pop(context);
                    HapticFeedback.mediumImpact();
                    onAction(MessageAction.backtrack);
                  },
                ),
            ],
            if (isAssistant) ...[
              _ActionTile(
                icon: Icons.refresh,
                label: '重新生成回复',
                subtitle: '重新生成此AI回复',
                color: isDark ? PixelTheme.darkAccent : PixelTheme.accent,
                onTap: () {
                  Navigator.pop(context);
                  HapticFeedback.lightImpact();
                  onAction(MessageAction.retry);
                },
              ),
              _ActionTile(
                icon: Icons.call_split,
                label: '从此处创建分支',
                subtitle: '创建一个新的对话分支',
                color: isDark ? PixelTheme.darkSecondary : PixelTheme.secondary,
                onTap: () {
                  Navigator.pop(context);
                  HapticFeedback.lightImpact();
                  onAction(MessageAction.branch);
                },
              ),
              _ActionTile(
                icon: Icons.copy,
                label: '复制全部内容',
                subtitle: '将此回复复制到剪贴板',
                color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  HapticFeedback.lightImpact();
                  onAction(MessageAction.copy);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
