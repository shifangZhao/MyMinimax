import 'package:flutter/material.dart';
import '../../../app/theme.dart';

enum ToolStatus { executing, success, error }

class ToolCallCard extends StatefulWidget {

  const ToolCallCard({
    required this.toolName, required this.arguments, super.key,
    this.status = ToolStatus.executing,
    this.onCancel,
  });
  final String toolName;
  final Map<String, dynamic> arguments;
  final ToolStatus status;
  final VoidCallback? onCancel;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    if (widget.status == ToolStatus.executing) {
      _startTime = DateTime.now();
    }
  }

  @override
  void didUpdateWidget(ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == ToolStatus.executing && _startTime == null) {
      _startTime = DateTime.now();
    }
  }

  String _formatDuration() {
    if (_startTime == null) return '';
    final duration = DateTime.now().difference(_startTime!);
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}秒';
    }
    return '${duration.inMinutes}分${duration.inSeconds % 60}秒';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
    final borderColor = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 400;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          constraints: const BoxConstraints(minHeight: 72),
          padding: EdgeInsets.all(isNarrow ? 8 : 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: isNarrow ? 28 : 36,
                height: isNarrow ? 28 : 36,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3A3A3A) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getToolIcon(widget.toolName),
                  size: isNarrow ? 14 : 18,
                  color: _getToolColor(widget.toolName),
                ),
              ),
              SizedBox(width: isNarrow ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getToolDisplayName(widget.toolName),
                      style: TextStyle(
                        fontSize: isNarrow ? 13 : 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isNarrow) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatArguments(widget.arguments),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black45,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (widget.status == ToolStatus.executing) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: isNarrow ? 12 : 14,
                            height: isNarrow ? 12 : 14,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PixelTheme.brandBlue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '正在执行...',
                            style: TextStyle(
                              fontSize: isNarrow ? 11 : 12,
                              color: isDark ? Colors.white60 : Colors.black45,
                            ),
                          ),
                          if (_formatDuration().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                          if (widget.onCancel != null) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: widget.onCancel,
                              child: const Text(
                                '取消',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: PixelTheme.brandBlue,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getToolIcon(String name) {
    switch (name) {
      case 'readFile':
        return Icons.description_outlined;
      case 'writeFile':
      case 'updateFile':
        return Icons.edit_document;
      case 'deleteFile':
        return Icons.delete_outline;
      case 'listFiles':
        return Icons.folder_outlined;
      case 'fetchUrl':
        return Icons.language;
      default:
        return Icons.build_outlined;
    }
  }

  Color _getToolColor(String name) {
    switch (name) {
      case 'readFile':
        return Colors.blue;
      case 'writeFile':
      case 'updateFile':
        return Colors.green;
      case 'deleteFile':
        return Colors.red;
      case 'listFiles':
        return Colors.orange;
      case 'fetchUrl':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getToolDisplayName(String name) {
    switch (name) {
      case 'readFile':
        return '读取文件';
      case 'writeFile':
        return '写入文件';
      case 'updateFile':
        return '更新文件';
      case 'deleteFile':
        return '删除文件';
      case 'listFiles':
        return '列出文件';
      case 'fetchUrl':
        return '抓取网页';
      default:
        return name;
    }
  }

  String _formatArguments(Map<String, dynamic> args) {
    if (args.isEmpty) return '（无参数）';
    return args.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
  }
}

class ToolResultCard extends StatefulWidget {

  const ToolResultCard({
    required this.toolName, required this.result, super.key,
    this.isError = false,
  });
  final String toolName;
  final String result;
  final bool isError;

  @override
  State<ToolResultCard> createState() => _ToolResultCardState();
}

class _ToolResultCardState extends State<ToolResultCard> {
  bool _isExpanded = false;
  static const _maxLines = 5;
  static const _expandedThreshold = 300;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLongResult = widget.result.length > _expandedThreshold;
    final needsTruncation = widget.result.length > _maxLines * 50;

    final bgColor = widget.isError
        ? (isDark ? const Color(0xFF2D1B1B) : const Color(0xFFFDF2F2))
        : (isDark ? const Color(0xFF1A2D1A) : const Color(0xFFF2FDF2));

    final borderColor = widget.isError
        ? (isDark ? const Color(0xFF5D3030) : const Color(0xFFE8CACA))
        : (isDark ? const Color(0xFF305D30) : const Color(0xFFCAE8CA));

    return PopScope(
      canPop: !_isExpanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isExpanded) {
          setState(() => _isExpanded = false);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.isError
                        ? (isDark ? const Color(0xFF3D2020) : const Color(0xFFFFEBEB))
                        : (isDark ? const Color(0xFF203D20) : const Color(0xFFE8FFE8)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.isError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 18,
                    color: widget.isError ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isError ? '执行失败' : '执行成功',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: widget.isError
                              ? (isDark ? const Color(0xFFFF6B6B) : const Color(0xFFDC3545))
                              : (isDark ? const Color(0xFF6BFF6B) : const Color(0xFF28A745)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildResultText(isDark, needsTruncation),
                    ],
                  ),
                ),
              ],
            ),
            if (isLongResult && !_isExpanded) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _isExpanded = true),
                child: const Text(
                  '展开全部',
                  style: TextStyle(
                    fontSize: 12,
                    color: PixelTheme.brandBlue,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultText(bool isDark, bool needsTruncation) {
    final displayText = _isExpanded || !needsTruncation
        ? widget.result
        : '${widget.result.substring(0, _maxLines * 50)}...';

    return Text(
      displayText,
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white70 : Colors.black54,
        fontFamily: 'monospace',
      ),
      maxLines: _isExpanded ? null : _maxLines,
      overflow: _isExpanded ? null : TextOverflow.ellipsis,
    );
  }
}
