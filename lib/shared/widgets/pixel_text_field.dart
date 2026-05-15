import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../utils/responsive.dart';

class PixelTextField extends StatefulWidget {

  const PixelTextField({
    required this.controller, super.key,
    this.hintText,
    this.maxLines = 1,
    this.onAttachmentTap,
    this.onSendTap,
    this.onOptimizeTap,
    this.onCameraTap,
    this.onImageTap,
    this.onFileTap,
    this.onTTSTap,
    this.onVoiceResult,
    this.onVoicePartial,
    this.onVoiceStart,
    this.voiceEnabled = true,
    this.isLoading = false,
    this.isGenerating = false,
    this.onStopTap,
  });
  final TextEditingController controller;
  final String? hintText;
  final int maxLines;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onSendTap;
  final VoidCallback? onOptimizeTap;
  final VoidCallback? onCameraTap;
  final VoidCallback? onImageTap;
  final VoidCallback? onFileTap;
  final VoidCallback? onTTSTap;
  final void Function(String text)? onVoiceResult;
  final void Function(String partial)? onVoicePartial;
  final VoidCallback? onVoiceStart;
  final bool voiceEnabled;
  final bool isLoading;
  final bool isGenerating;
  final VoidCallback? onStopTap;

  @override
  State<PixelTextField> createState() => _PixelTextFieldState();
}

class _PixelTextFieldState extends State<PixelTextField> {
  @override
  Widget build(BuildContext context) {
    final maxInputHeight = ResponsiveHelper.inputMaxHeight(context);
    return Container(
      decoration: BoxDecoration(
        color: PixelTheme.surfaceVariant,
        border: Border.all(color: PixelTheme.pixelBorder.withValues(alpha: 0.5), width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.maxLines > 1)
            Container(
              constraints: BoxConstraints(
                maxHeight: maxInputHeight,
              ),
              child: TextField(
                controller: widget.controller,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            )
          else
            TextField(
              controller: widget.controller,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => widget.onSendTap?.call(),
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: widget.hintText,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: PixelTheme.pixelBorder.withValues(alpha: 0.3), width: 1)),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.horizontalPadding(context),
              vertical: 4,
            ),
            child: Row(
              children: [
                _PixelIconButton(
                  icon: Icons.camera_alt,
                  onTap: widget.onCameraTap,
                  tooltip: '拍照上传',
                ),
                const SizedBox(width: 8),
                _PixelIconButton(
                  icon: Icons.image,
                  onTap: widget.onImageTap,
                  tooltip: '添加图片',
                ),
                const SizedBox(width: 8),
                _PixelIconButton(
                  icon: Icons.attach_file,
                  onTap: widget.onFileTap,
                  tooltip: '添加文件',
                ),
                const SizedBox(width: 8),
                // TODO: 替换为本地离线ASR按钮
                const Icon(Icons.mic_none, size: 20, color: PixelTheme.textMuted),
                const Spacer(),
                if (widget.isGenerating)
                  _PixelIconButton(
                    icon: Icons.stop,
                    onTap: widget.onStopTap,
                    tooltip: '停止生成',
                    isPrimary: true,
                    isDestructive: true,
                  )
                else if (widget.isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onOptimizeTap != null)
                        _PixelIconButton(
                          icon: Icons.auto_fix_high,
                          onTap: widget.onOptimizeTap,
                          tooltip: '优化提示词',
                        ),
                      if (widget.onOptimizeTap != null && widget.onTTSTap != null)
                        const SizedBox(width: 4),
                      if (widget.onTTSTap != null)
                        _PixelIconButton(
                          icon: Icons.record_voice_over,
                          onTap: widget.onTTSTap,
                          tooltip: '语音合成',
                        ),
                      const SizedBox(width: 4),
                      _PixelIconButton(
                        icon: Icons.send,
                        onTap: widget.onSendTap,
                        tooltip: '发送',
                        isPrimary: true,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PixelIconButton extends StatefulWidget {

  const _PixelIconButton({
    required this.icon,
    required this.tooltip, this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool isPrimary;
  final bool isDestructive;

  @override
  State<_PixelIconButton> createState() => _PixelIconButtonState();
}

class _PixelIconButtonState extends State<_PixelIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = widget.isDestructive ? PixelTheme.error : (widget.isPrimary ? PixelTheme.primary : Colors.transparent);
    final borderColor = widget.isDestructive ? PixelTheme.error : (widget.isPrimary ? PixelTheme.primary : PixelTheme.pixelBorder);
    final defaultIconColor = widget.isPrimary ? PixelTheme.background : PixelTheme.textPrimary;
    final highlightColor = widget.isDestructive
        ? PixelTheme.error.withValues(alpha: 0.7)
        : (isDark ? PixelTheme.darkPrimary : PixelTheme.primary);
    final iconColor = _isPressed ? highlightColor : defaultIconColor;

    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: widget.onTap != null ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: widget.onTap != null ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: widget.onTap != null ? () => setState(() => _isPressed = false) : null,
        borderRadius: BorderRadius.circular(8),
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: 1.5,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}
