import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/image_base64.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app.dart';
import '../../core/browser/browser_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/chat/domain/chat_message.dart';
import '../../features/map/data/map_action.dart' show mapActionBus, mapActionPending;
import '../utils/responsive.dart';
import '../utils/code_highlighter.dart';

/// Emoji font family name — loaded once via google_fonts, then cached on device
String? _emojiFamily;
String _getEmojiFamily() {
  if (_emojiFamily != null) return _emojiFamily!;
  try {
    _emojiFamily = GoogleFonts.notoColorEmoji().fontFamily;
  } catch (_) {
    _emojiFamily = 'NotoColorEmoji';
  }
  return _emojiFamily!;
}

/// 给 TextStyle 加上 emoji 字体 fallback
TextStyle _withEmojiFallback(TextStyle base) {
  final family = _getEmojiFamily();
  final fallback = base.fontFamilyFallback ?? <String>[];
  if (fallback.contains(family)) return base;
  return base.copyWith(fontFamilyFallback: [...fallback, family]);
}

class ChatBubble extends StatelessWidget {

  const ChatBubble({
    required this.message, super.key,
    this.isStreaming = false,
    this.onLongPress,
    this.onBacktrack,
    this.isBacktrackPending = false,
  });
  final ChatMessage message;
  final bool isStreaming;
  final VoidCallback? onLongPress;
  final VoidCallback? onBacktrack;
  final bool isBacktrackPending;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final contentColumn = Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.content.isNotEmpty || message.hasImage)
          _BubbleContent(
            message: message,
            isUser: isUser,
            isStreaming: isStreaming,
          ),
      ],
    );

    final bubble = RepaintBoundary(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: isUser ? 8 : 4),
        child: isUser
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (onBacktrack != null)
                    GestureDetector(
                      onTap: onBacktrack,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Icon(
                          Icons.undo_rounded,
                          size: 18,
                          color: isBacktrackPending
                              ? Colors.red
                              : PixelTheme.primary,
                        ),
                      ),
                    ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      child: contentColumn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _AvatarIcon(isAgent: false),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头像 + 思考同行
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _AvatarIcon(isAgent: true),
                      const SizedBox(width: 8),
                      if (message.hasThinking)
                        Expanded(
                          child: _ThinkingSection(
                            thinking: message.thinking!,
                            isStreaming: isStreaming,
                            isThinkingFinished: message.isAssistant && !isStreaming,
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                  if (message.hasThinking) const SizedBox(height: 8),
                  // 回复内容
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.97),
                    child: contentColumn,
                  ),
                ],
              ),
      ),
    );

    // Long press handler
    Widget? wrapped = bubble;
    if (onLongPress != null) {
      wrapped = GestureDetector(
        onLongPress: () {
          onLongPress!();
        },
        child: bubble,
      );
    }

    return wrapped;
  }
}

class _AvatarIcon extends ConsumerWidget {
  const _AvatarIcon({required this.isAgent});
  final bool isAgent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarSize = ResponsiveHelper.avatarSize(context);
    final iconSize = avatarSize * 0.55;
    final primaryColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;

    final path = ref.watch(isAgent ? agentAvatarProvider : userAvatarProvider);
    final hasCustom = path.isNotEmpty && File(path).existsSync();

    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        color: isAgent
            ? (isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariantFor(isDark).withValues(alpha: 0.8))
            : (isDark ? PixelTheme.darkHighElevated : PixelTheme.surfaceVariantFor(isDark)),
        borderRadius: BorderRadius.circular(PixelTheme.radiusSm),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasCustom
          ? Image.file(File(path), fit: BoxFit.cover)
          : Icon(
              isAgent ? Icons.smart_toy : Icons.person,
              size: iconSize,
              color: isAgent ? primaryColor : (isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText),
            ),
    );
  }
}

/// 思考内容区域（可折叠）
class _ThinkingSection extends StatefulWidget {

  const _ThinkingSection({
    required this.thinking,
    this.isStreaming = false,
    this.isThinkingFinished = false,
  });
  final String thinking;
  final bool isStreaming;
  final bool isThinkingFinished;

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayText = widget.isThinkingFinished ? '思考' : '思考中...';

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(PixelTheme.radiusLg),
      topRight: const Radius.circular(PixelTheme.radiusLg),
      bottomLeft: const Radius.circular(4),
      bottomRight: const Radius.circular(PixelTheme.radiusLg),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: isDark ? PixelTheme.darkBorder : PixelTheme.pixelBorder.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Material(
        color: isDark ? PixelTheme.darkHighElevated : PixelTheme.surfaceElevated,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 可点击的头部
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                children: [
                  Text(
                    displayText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.isStreaming && !widget.isThinkingFinished) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                  ),
                ],
              ),
            ),
          // 展开的思考内容，使用 SizeTransition 实现纯粹的上下收缩动画
          SizeTransition(
            sizeFactor: AlwaysStoppedAnimation(_isExpanded ? 1.0 : 0.0),
            axisAlignment: -1.0, // 从顶部开始
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                widget.thinking,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }
}

class _BubbleContent extends StatelessWidget {

  const _BubbleContent({
    required this.message,
    required this.isUser,
    required this.isStreaming,
  });
  final ChatMessage message;
  final bool isUser;
  final bool isStreaming;

@override
  Widget build(BuildContext context) {
    final maxWidthRatio = ResponsiveHelper.bubbleMaxWidthRatio(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTool = message.isTool;
    final toolColor = isDark ? const Color(0xFF6A9955) : const Color(0xFF517A3E); // 绿色系区分工具结果

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * maxWidthRatio,
      ),
      decoration: BoxDecoration(
        gradient: isUser
            ? (isDark
                ? const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],  // 蓝
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],  // 蓝-500 → 蓝-400
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ))
            : null,
        color: isUser
            ? null
            : isTool
                ? (isDark ? const Color(0xFF162316) : const Color(0xFFF0F7EC))
                : (isDark ? PixelTheme.darkHighElevated : PixelTheme.surfaceElevated),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(PixelTheme.radiusLg),
          topRight: const Radius.circular(PixelTheme.radiusLg),
          bottomLeft: Radius.circular(isUser ? PixelTheme.radiusLg : 4),
          bottomRight: Radius.circular(isUser ? 4 : PixelTheme.radiusLg),
        ),
        border: isUser
            ? null
            : isTool
                ? Border(left: BorderSide(color: toolColor, width: 4))
                : Border.all(
                    color: isDark ? PixelTheme.darkBorder : PixelTheme.pixelBorder.withValues(alpha: 0.5),
                    width: 1,
                  ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.hasImage) _buildImage(message.imageBase64!),
          if (message.hasFile) _buildFile(message.fileName!),
          if (message.hasToolImage) _buildToolImage(message.toolImageUrl!),
          _buildMessageContent(),
          if (message.isTool && _isMapTool(message.toolCall)) _buildMapActionChip(context),
        ],
      ),
    );
  }

  static const _mapToolNames = {
    'geocode', 'regeocode', 'search_places', 'search_nearby',
    'plan_driving_route', 'plan_walking_route', 'plan_cycling_route',
    'plan_transit_route', 'plan_electrobike_route',
    'get_traffic_status', 'get_traffic_events',
    'grasproad', 'future_route', 'map_agent',
  };

  bool _isMapTool(String? toolName) {
    return toolName != null && _mapToolNames.contains(toolName);
  }

  Widget _buildMapActionChip(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: GestureDetector(
        onTap: () {
          final pending = mapActionPending.value;
          if (pending != null) {
            mapActionBus.value = pending;
          }
          try {
            ProviderScope.containerOf(context).read(navigationIndexProvider.notifier).state = 1;
          } catch (_) {}
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: PixelTheme.brandBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: PixelTheme.brandBlue.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 14, color: PixelTheme.brandBlue),
              SizedBox(width: 4),
              Text('查看地图', style: TextStyle(fontSize: 12, color: PixelTheme.brandBlue)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String base64) {
    Uint8List bytes;
    try {
      bytes = ImageBase64.decodeAny(base64);
    } catch (_) {
      return const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.broken_image, size: 48),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Builder(
        builder: (ctx) => GestureDetector(
          onTap: () => _showImageDialog(ctx, bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : double.infinity,
                    maxHeight: 400,
                  ),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    cacheWidth: 512,
                    cacheHeight: 512,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showImageDialog(BuildContext ctx, Uint8List bytes) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48, color: Colors.white70),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFile(String fileName) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_file, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              fileName,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 渲染工具返回的网络图片
  Widget _buildToolImage(String url) {
    // 清理零宽空格
    final cleanUrl = url.replaceAll('​', '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Icon(Icons.broken_image, size: 24, color: Colors.grey),
            const SizedBox(width: 8),
            const Text('图片加载失败', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          cleanUrl,
          width: double.infinity,
          fit: BoxFit.contain,
          cacheWidth: 600,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: double.infinity,
              height: 200,
              alignment: Alignment.center,
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
                strokeWidth: 2,
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            width: double.infinity,
            height: 100,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, size: 32, color: Colors.grey),
                Text('图片加载失败', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent() {
    // 提取 base64 图片并渲染
    final extractedBase64 = _extractBase64Image();
    if (extractedBase64 != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildImage(extractedBase64),
          _buildTextContent(),
        ],
      );
    }

    // 标准渲染
    // 过滤掉 [SUMMARY]...[/SUMMARY] 部分
    var cleanContent = _filterSummary(message.content);
    // 预处理：修复加粗包裹公式的问题 **$...$** -> $...$
    cleanContent = _preprocessMathBold(cleanContent);
    // 自动分段：长文本无换行时智能插入段落分隔
    cleanContent = _autoParagraph(cleanContent);

    // 用户消息不可选择；AI 消息用 SelectionArea 包裹实现跨块连续选取
    final bodyWidget = isUser
        ? _buildUserText()
        : isStreaming
            ? _StreamingMarkdown(content: cleanContent)
            : SelectionArea(
                contextMenuBuilder: (context, selectableRegionState) {
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: selectableRegionState.contextMenuAnchors,
                    buttonItems: [
                      ContextMenuButtonItem(
                        onPressed: () {
                          selectableRegionState.copySelection(SelectionChangedCause.toolbar);
                        },
                        label: '复制',
                      ),
                      ContextMenuButtonItem(
                        onPressed: () {
                          selectableRegionState.selectAll(SelectionChangedCause.toolbar);
                        },
                        label: '全选',
                      ),
                    ],
                  );
                },
                child: _FreeSelectableMarkdown(content: cleanContent, selectable: false),
              );

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 12, isUser ? 12 : 48, 12),
          child: bodyWidget,
        ),
        if (!isUser)
          Positioned(
            top: 4,
            right: 4,
            child: _CopyButton(content: cleanContent),
          ),
      ],
    );
  }

  String _filterSummary(String content) {
    // 移除 [SUMMARY]...[/SUMMARY] 及各种变体
    var cleanContent = content;

    // 情况1: 标准格式 [SUMMARY]...[/SUMMARY]
    final standardPattern = RegExp(r'\[SUMMARY\][\s\S]*?\[/SUMMARY\]', caseSensitive: false);
    cleanContent = cleanContent.replaceAll(standardPattern, '');

    // 情况2: [SEARCH]关键词[/SUMMARY]：摘要内容
    final searchBlockPattern = RegExp(
      r'\[SEARCH\][^\[]*?\[/SUMMARY\][\s\S]*?(?=\[SEARCH\]|\[ASK\]|\[TOOL_CALL\]|$)',
      caseSensitive: false,
    );
    cleanContent = cleanContent.replaceAll(searchBlockPattern, '');

    // 情况3: 只有 [/SUMMARY] 在内容之后
    final endTagPattern = RegExp(r'\[/SUMMARY\][\s\S]*?$', caseSensitive: false);
    cleanContent = cleanContent.replaceAll(endTagPattern, '');

    return cleanContent.trim();
  }

  static String _preprocessMathBold(String content) {
    // 1. 修复 **$latex$** -> $latex$（去掉无意义的加粗包裹）
    content = content.replaceAllMapped(
      RegExp(r'\*\*\s*(\$[^$]+\$)\s*\*\*'),
      (m) => m.group(1)!,
    );

    // 2. 把 **o(x²)** 这种转成 $o(x^2)$（Unicode 上标转 LaTeX）
    content = content.replaceAllMapped(
      RegExp(r'\*\*o\(x([²³⁴⁵⁶⁷⁸⁹⁰])\)\*\*'),
      (m) {
        final sup = m.group(1)!;
        final latexSup = {'²': '^2', '³': '^3', '⁴': '^4', '⁵': '^5', '⁶': '^6', '⁷': '^7', '⁸': '^8', '⁹': '^9', '⁰': '^0'}[sup] ?? sup;
        return r'$o(x' + latexSup + r')$';
      },
    );

    // 3. 处理独立的 Unicode 上标公式（无 $ 包裹）如 o(x²) -> $o(x^2)$
    content = content.replaceAllMapped(
      RegExp(r'o\(x([²³⁴⁵⁶⁷⁸⁹⁰])\)(?!\$)'),
      (m) {
        final sup = m.group(1)!;
        final latexSup = {'²': '^2', '³': '^3', '⁴': '^4', '⁵': '^5', '⁶': '^6', '⁷': '^7', '⁸': '^8', '⁹': '^9', '⁰': '^0'}[sup] ?? sup;
        return r'$o(x' + latexSup + r')$';
      },
    );

    // 4. 其他 Unicode 上标转 LaTeX（通用）
    content = content.replaceAll('²', '^2');
    content = content.replaceAll('³', '^3');
    content = content.replaceAll('⁴', '^4');
    content = content.replaceAll('⁵', '^5');
    content = content.replaceAll('⁶', '^6');
    content = content.replaceAll('⁷', '^7');
    content = content.replaceAll('⁸', '^8');
    content = content.replaceAll('⁹', '^9');
    content = content.replaceAll('⁰', '^0');
    content = content.replaceAll('¹', '^1');

    // 5. 长 URL 插入零宽空格，实现软换行（不截断、可点击）
    content = _insertZeroWidthSpaces(content);

    return content;
  }

  /// 在超过40字符的URL中插入零宽空格，让 TextPainter 可以任意位置换行
  static String _insertZeroWidthSpaces(String text) {
    return text.replaceAllMapped(
      RegExp(r'https?://[^\s\)>\]]{40,}'),
      (m) {
        // 在每个字符间插入零宽空格
        return m.group(0)!.split('').join('​');
      },
    );
  }

  /// 渲染前智能分段：对无分段的长文本自动插入空行
  static String _autoParagraph(String text) {
    if (text.contains('\n\n') || text.length < 220) return text;
    if (text.contains('```') || text.contains('|') ||
        RegExp(r'^\s*[-*+]\s').hasMatch(text)) return text;
    return text.replaceAllMapped(
      RegExp(r'([。！？])'
            r'|(?<!\b(?:Mr|Mrs|Dr|Ms|Prof|Fig|Eq|vs|i\.e|e\.g|etc|al|No|no))\.'
            r'(?!\d)'
            r'(?=\s+[A-Z一-鿿])'),
      (m) => '${m[0]}\n\n',
    );
  }

  Widget _buildUserText() {
    var text = message.content;
    if (message.hasImage) {
      // 用户图片：直接移除 markdown 图片语法
      text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\(data:image/[^)]+\).*?(?=\n|$)'), '').trim();
      if (text.isEmpty) text = '[用户发送了一张图片]';
    }
    return Text(
      text,
      softWrap: true,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: PixelTheme.userBubbleText),
    );
  }

  /// 渲染纯文本内容（不含 base64 图片）
  Widget _buildTextContent() {
    var cleanContent = message.content;
    // 移除 base64 图片语法
    cleanContent = cleanContent.replaceAll(RegExp(r'!\[([^\]]*)\]\(data:image/[^)]+;base64,[^)]+\)'), '').trim();
    if (cleanContent.isEmpty) return const SizedBox.shrink();
    return Text(
      cleanContent,
      softWrap: true,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
      ),
    );
  }

  /// 从消息内容中提取 base64 图片并渲染
  String? _extractBase64Image() {
    final imgMatch = RegExp(r'!\[([^\]]*)\]\(data:image/([^;]+);base64,([^)]+)\)').firstMatch(message.content);
    if (imgMatch != null) {
      return imgMatch.group(3);
    }
    return null;
  }
}

/// 自由选择文本组件（选择后可复制）
class _FreeSelectableText extends StatefulWidget {

  const _FreeSelectableText({
    required this.text,
    required this.style,
  });
  final String text;
  final TextStyle style;

  @override
  State<_FreeSelectableText> createState() => _FreeSelectableTextState();
}

class _FreeSelectableTextState extends State<_FreeSelectableText> {
  String _selectedText = '';
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _showCopyButton() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Positioned(
        width: 80,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: Material(
            color: PixelTheme.surfaceFor(isDark),
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _copySelection,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: PixelTheme.borderFor(isDark)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy, size: 14, color: PixelTheme.primaryFor(isDark)),
                    const SizedBox(width: 4),
                    Text(
                      '复制',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: PixelTheme.primaryFor(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _copySelection() async {
    if (_selectedText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _selectedText));
    _removeOverlay();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已复制', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? PixelTheme.darkSurface : PixelTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(12),
        ),
      );
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SelectableText(
        widget.text,
        style: widget.style,
        onSelectionChanged: (selection, cause) {
          final text = selection.textInside(widget.text);
          if (text.isNotEmpty) {
            _selectedText = text;
            _showCopyButton();
          } else {
            _removeOverlay();
          }
        },
      ),
    );
  }
}

/// 复制按钮
class _CopyButton extends StatefulWidget {

  const _CopyButton({required this.content});
  final String content;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  void _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _copied ? Icons.check : Icons.copy,
        size: 16,
        color: _copied ? PixelTheme.primary : PixelTheme.textSecondary,
      ),
      onPressed: _copyToClipboard,
      tooltip: _copied ? '已复制' : '复制全部',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 32,
        minHeight: 32,
      ),
    );
  }
}

/// 可折叠的代码块组件
class _CollapsibleCodeBlock extends StatefulWidget {

  const _CollapsibleCodeBlock({
    required this.code,
    this.language,
    this.isStreaming = false,
  });
  final String code;
  final String? language;
  final bool isStreaming;

  @override
  State<_CollapsibleCodeBlock> createState() => _CollapsibleCodeBlockState();
}

class _CollapsibleCodeBlockState extends State<_CollapsibleCodeBlock>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = true;
  late AnimationController _pulseController;
  bool _wasStreaming = false;

  @override
  void initState() {
    super.initState();
    _wasStreaming = widget.isStreaming;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isStreaming) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _CollapsibleCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !_wasStreaming) {
      _isExpanded = true;
      _pulseController.repeat(reverse: true);
    } else if (!widget.isStreaming && _wasStreaming) {
      _pulseController.stop();
      _pulseController.reset();
    }
    _wasStreaming = widget.isStreaming;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _langColor(String? lang) {
    return CodeHighlighter.getLanguageColor(lang);
  }

  String _getLangDisplayName(String? lang) {
    return CodeHighlighter.getLanguageDisplayName(lang);
  }

  void _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('代码已复制', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? PixelTheme.darkSurface : PixelTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(12),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLongCode = widget.code.split('\n').length > 10;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkCodeBlockBg : PixelTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        border: Border.all(color: isDark ? PixelTheme.darkBorderSubtle : PixelTheme.pixelBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? PixelTheme.darkElevated.withValues(alpha: 0.8) : PixelTheme.surface.withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(PixelTheme.radiusMd - 1)),
            ),
            child: Row(
              children: [
                // 语言色点
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _langColor(widget.language),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getLangDisplayName(widget.language),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.isStreaming) ...[
                  const SizedBox(width: 10),
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) => Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: PixelTheme.accent.withValues(alpha: 0.4 + _pulseController.value * 0.6),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: PixelTheme.accent.withValues(alpha: 0.2 + _pulseController.value * 0.3),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('生成中', style: TextStyle(fontSize: 10, color: isDark ? PixelTheme.darkAccent : PixelTheme.accent)),
                ],
                const Spacer(),
                // 行数
                Text(
                  '${widget.code.split('\n').length} 行',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                // 复制按钮
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.copy_rounded, size: 16, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                  ),
                ),
                if (isLongCode) ...[
                  const SizedBox(width: 4),
                  // 展开/收起按钮
                  InkWell(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 16,
                            color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isExpanded ? '收起' : '展开',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 代码内容（可水平滚动）- SizeTransition 上下收缩
          // 展开时动态高度：按行数自适应，上限 60% 屏幕高度
          SizeTransition(
            sizeFactor: AlwaysStoppedAnimation(_isExpanded ? 1.0 : 0.0),
            axisAlignment: -1.0,
            child: Builder(
              builder: (ctx) {
                final screenH = MediaQuery.of(ctx).size.height;
                final lineCount = widget.code.split('\n').length;
                // ~18px per line, min 80px, max 60% screen
                final contentH = (lineCount * 18.0 + 28).clamp(80.0, screenH * 0.6);
                return SizedBox(
                  height: contentH,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: MediaQuery.of(ctx).size.width - 32,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        physics: const ClampingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: SelectableText.rich(
                            const CodeHighlighter().highlight(widget.code, widget.language, isDark: isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 行内公式组件 - 使用 WidgetSpan 确保与文字基线对齐
class _InlineMathWidget extends StatelessWidget {

  const _InlineMathWidget({required this.latex, required this.fontSize});
  final String latex;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? PixelTheme.darkPrimaryText
        : PixelTheme.primaryText;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mathWidget = Math.tex(
          latex,
          textStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            height: 1.2,
            color: textColor,
          ),
          mathStyle: MathStyle.text,
          onErrorFallback: (error) {
            return Text(
              r'$' + latex + r'$',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize,
                color: PixelTheme.error,
              ),
            );
          },
        );
        // WidgetSpan 环境中约束不可靠，取可用最大宽度
        final effectiveMaxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width * 0.6;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: mathWidget,
          ),
        );
      },
    );
  }
}

/// 处理不完整的 LaTeX 公式，防止流式输出时解析错误闪烁
String _sanitizeMath(String text) {
  // 1. 清理包裹公式的粗体：**$...$** -> $...$
  text = text.replaceAllMapped(
    RegExp(r'\*\*\s*(\$[^$]+\$)\s*\*\*'),
    (m) => m.group(1)!,
  );

  // 2. 处理行内公式 $...$：如果 $ 数量为奇数，说明有未闭合的公式
  final dollarMatches = RegExp(r'(?<!\\)\$').allMatches(text);
  if (dollarMatches.length.isOdd) {
    // 找到最后一个未转义的 $
    int lastIndex = -1;
    for (final match in dollarMatches) {
      lastIndex = match.start;
    }
    if (lastIndex != -1) {
      // 把最后一个 $ 临时转义
      text = text.substring(0, lastIndex) + r'\$' + text.substring(lastIndex + 1);
    }
  }

  // 3. 处理块级公式 $$...$$：如果 $$ 数量为奇数
  final blockMatches = RegExp(r'\$\$(?!\$)').allMatches(text);
  if (blockMatches.length.isOdd) {
    int lastIndex = -1;
    for (final match in blockMatches) {
      lastIndex = match.start;
    }
    if (lastIndex != -1) {
      // 把最后一个 $$ 临时转义
      text = text.substring(0, lastIndex) + r'\$\$' + text.substring(lastIndex + 2);
    }
  }

  return text;
}

/// 支持数学公式的 Markdown 渲染器
class _MathAwareMarkdown extends StatelessWidget {

  const _MathAwareMarkdown({required this.content, this.isStreaming = false, this.selectable = true});
  final String content;
  final bool isStreaming;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 先提取图片
    final imageWidgets = _extractImages();

    // 提取后剩余内容
    final textOnly = content.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
      (m) => '',
    ).trim();

    final widgets = _parseContent(textOnly.isEmpty ? ' ' : textOnly, isDark, isStreaming);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [...imageWidgets, ...widgets],
    );
  }

  /// 提取 Markdown 图片并渲染
  List<Widget> _extractImages() {
    final widgets = <Widget>[];
    final regex = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');

    for (final match in regex.allMatches(content)) {
      final alt = match.group(1) ?? '';
      final url = match.group(2)?.replaceAll('​', '') ?? '';
      if (url.isNotEmpty) {
        widgets.add(_MathAwareMarkdown._buildNetworkImage(url, alt: alt));
      }
    }
    return widgets;
  }

  List<Widget> _parseContent(String content, bool isDark, bool isStreaming) {
    // 预处理：合并 "标签 + 换行 + $$公式$$" -> "标签 $公式$"
    content = _preprocessMathBlocks(content);

    final widgets = <Widget>[];
    final blocks = <String>[];

    // 先处理完整代码块 ```...```
    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    int lastEnd = 0;

    for (final match in codeBlockRegex.allMatches(content)) {
      if (match.start > lastEnd) {
        blocks.add(content.substring(lastEnd, match.start));
      }
      blocks.add('__CODE_BLOCK_${match.group(0)}__CODE_BLOCK__');
      lastEnd = match.end;
    }

    // 流式生成时检测未闭合的代码块：```开头但没找到配对```
    final remaining = content.substring(lastEnd);
    final openCodeMatch = RegExp(r'```(\w*)\n([\s\S]*)').firstMatch(remaining);
    if (isStreaming && openCodeMatch != null) {
      // 有未闭合的代码块，整个剩余部分都是代码
      blocks.add('__STREAMING_CODE_${openCodeMatch.group(1) ?? ''}__${openCodeMatch.group(2) ?? remaining}__STREAMING_CODE__');
    } else if (remaining.isNotEmpty) {
      blocks.add(remaining);
    }

    // 处理每个块
    for (final block in blocks) {
      if (block.startsWith('__STREAMING_CODE_')) {
        // 流式生成中的代码块
        final inner = block.replaceAll('__STREAMING_CODE_', '').replaceAll('__STREAMING_CODE__', '');
        final langMatch = RegExp(r'^([^\n]*?)__').firstMatch(inner);
        final lang = langMatch?.group(1)?.isNotEmpty == true ? langMatch!.group(1) : null;
        final code = inner.substring(langMatch != null ? langMatch.end : 0);
        widgets.add(_CollapsibleCodeBlock(code: code, language: lang, isStreaming: true));
      } else if (block.startsWith('__CODE_BLOCK_')) {
        final codeContent = block.replaceAll('__CODE_BLOCK_', '').replaceAll('__CODE_BLOCK__', '');
        widgets.add(_buildCodeBlock(codeContent));
      } else {
        // 解析数学公式和 Markdown
        widgets.addAll(_parseMathAndMarkdown(block, isDark));
      }
    }

    return widgets;
  }

  List<Widget> _parseMathAndMarkdown(String text, bool isDark) {
    final widgets = <Widget>[];

    // 先检测表格（表格需要特殊处理：横向滚动）
    final tablePattern = RegExp(r'^\|.+\|[\s\S]*?^\|.+\|[\s\S]*?^:\|[-:]+\|', multiLine: true);
    final hasTable = tablePattern.hasMatch(text);

    if (hasTable) {
      // 有表格，提取并单独处理
      widgets.addAll(_parseContentWithTable(text, isDark));
    } else {
      // 拆分文本：先按行拆，每行检查是否是 Markdown 标题
      final lines = _splitByHeaders(text);
      for (final line in lines) {
        if (line.startsWith('#')) {
          // Markdown 标题，单独渲染
          widgets.add(_buildMarkdownWidget(line, isDark));
        } else if (line.trim().isEmpty) {
          // 空行，跳过
          continue;
        } else {
          // 普通文本或包含行内公式，按 $$...$$ 分割
          final blockParts = _splitByBlockMath(line);
          for (final part in blockParts) {
            if (part.isMathBlock) {
              widgets.add(_buildMathBlock(part.content));
            } else {
              widgets.add(_buildInlineContent(part.content, isDark));
            }
          }
        }
      }
    }

    return widgets;
  }

  /// 按 Markdown 标题拆分文本
  List<String> _splitByHeaders(String text) {
    final lines = <String>[];
    final headerRegex = RegExp(r'^(#{1,6}\s+.*)$', multiLine: true);
    int lastEnd = 0;

    for (final match in headerRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        final before = text.substring(lastEnd, match.start);
        if (before.isNotEmpty) lines.add(before);
      }
      lines.add(match.group(1)!);
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd);
      if (remaining.isNotEmpty) lines.add(remaining);
    }

    // 如果没有找到标题，整个文本作为一个块
    if (lines.isEmpty) lines.add(text);

    return lines;
  }

  /// 解析包含表格的内容
  List<Widget> _parseContentWithTable(String text, bool isDark) {
    final widgets = <Widget>[];
    final tableRegex = RegExp(r'(\|.+\|[\s\S]*?)(?=\n\n|\n[^|]|$)');
    int lastEnd = 0;

    for (final match in tableRegex.allMatches(text)) {
      final tableContent = match.group(0)!;
      final isTable = tableContent.contains(RegExp(r'^\|.+\|[\s\S]*?^:\|[-:]+\|', multiLine: true));

      if (match.start > lastEnd) {
        final beforeText = text.substring(lastEnd, match.start);
        // 处理非表格部分
        final blockParts = _splitByBlockMath(beforeText);
        for (final part in blockParts) {
          if (part.isMathBlock) {
            widgets.add(_buildMathBlock(part.content));
          } else {
            widgets.add(_buildInlineContent(part.content, isDark));
          }
        }
      }

      if (isTable) {
        widgets.add(_buildScrollableTable(tableContent, isDark));
      } else {
        widgets.add(_buildInlineContent(tableContent, isDark));
      }

      lastEnd = match.end;
    }

    // 处理剩余内容
    if (lastEnd < text.length) {
      final blockParts = _splitByBlockMath(text.substring(lastEnd));
      for (final part in blockParts) {
        if (part.isMathBlock) {
          widgets.add(_buildMathBlock(part.content));
        } else {
          widgets.add(_buildInlineContent(part.content, isDark));
        }
      }
    }

    return widgets;
  }

  /// 构建可横向滚动的表格
  Widget _buildScrollableTable(String tableContent, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: MarkdownBody(
        data: tableContent,
        selectable: selectable,
        shrinkWrap: true,
        fitContent: true,
        styleSheet: _buildStyleSheet(isDark),
        imageBuilder: (uri, title, alt) {
          return _MathAwareMarkdown._buildNetworkImage(uri, alt: alt);
        },
      ),
    );
  }

  /// 预处理 LaTeX 公式格式
  String _preprocessMathBlocks(String text) {
    // 1. 把 \( \) 替换成 $ $
    text = text.replaceAllMapped(
      RegExp(r'\\\((.*?)\\\)'),
      (m) => '\$${m[1]}\$',
    );

    // 2. 把 \[ \] 替换成 $$ $$
    text = text.replaceAllMapped(
      RegExp(r'\\\[(.*?)\\\]'),
      (m) => '\$\$${m[1]}\$\$',
    );

    // 3. 处理 ```math 代码块 -> $$...$$
    text = text.replaceAllMapped(
      RegExp(r'```math\s*\n([\s\S]*?)\n```'),
      (m) => '\$\$${m[1]}\$\$',
    );

    // 4. 匹配：标签（如 "分子："、"分母："、"代入得：" 等）+ 换行 + $$公式$$
    //    替换为：标签 $公式$（把独立公式转为行内公式）
    text = text.replaceAllMapped(
      RegExp(
        r'^([\-•]\s*[一-龥a-zA-Z]+[:：]\s*)\n+\$\$([\s\S]*?)\$\$',
        multiLine: true,
      ),
      (m) => '${m.group(1)}\$${m.group(2)}\$',
    );

    // 5. 把行间公式单独成行（确保 markdown 解析正确）
    text = text.replaceAllMapped(
      RegExp(r'([^\n])\$\$'),
      (m) => '${m[1]}\n\$\$',
    );

    return text;
  }

  List<_TextPart> _splitByBlockMath(String text) {
    final parts = <_TextPart>[];
    final blockRegex = RegExp(r'\$\$([\s\S]*?)\$\$');
    int lastEnd = 0;

    for (final match in blockRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        parts.add(_TextPart(text.substring(lastEnd, match.start), isMathBlock: false));
      }
      parts.add(_TextPart(match.group(1)!, isMathBlock: true));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      parts.add(_TextPart(text.substring(lastEnd), isMathBlock: false));
    }

    return parts;
  }

  /// 构建行内内容（文字 + 行内公式）
  Widget _buildInlineContent(String text, bool isDark) {
    // 检查是否有需要强制并排的公式（||| 分隔）
    if (text.contains('|||')) {
      return _buildForcedInline(text, isDark);
    }

    // 没有 $ 符号，直接返回 Markdown
    if (!text.contains(r'$')) {
      return _buildMarkdownWidget(text, isDark);
    }

    final spans = _parseInlineSpans(text);

    if (spans.isEmpty) return _buildMarkdownWidget(text, isDark);
    if (spans.length == 1 && spans.first.isText) {
      return _buildMarkdownWidget(spans.first.content, isDark);
    }

    // 检查文本部分是否包含 Markdown 格式
    final hasMarkdown = _containsMarkdown(text);
    if (hasMarkdown) {
      return _buildMixedContent(text, spans, isDark);
    }

    // 使用 Row + Baseline 强制并排（更精确的基线对齐）
    return _buildRowWithBaseline(spans, isDark);
  }

  /// 使用 RichText + WidgetSpan 强制基线对齐（关键：PlaceholderAlignment.baseline）
  Widget _buildRowWithBaseline(List<_InlineSpan> spans, bool isDark) {
    const fontSize = 13.0;
    final inlineSpans = <InlineSpan>[];

    for (final span in spans) {
      if (span.isText) {
        inlineSpans.add(TextSpan(
          text: span.content,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            height: 1.5,
            color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
          ),
        ));
      } else {
        inlineSpans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _InlineMathWidget(
            latex: span.content,
            fontSize: fontSize,
          ),
        ));
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: RichText(
            softWrap: true,
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize,
                color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
                height: 1.5,
              ),
              children: inlineSpans,
            ),
          ),
        );
      },
    );
  }

  /// 处理强制并排的公式（||| 分隔符）- 使用 RichText 基线对齐
  Widget _buildForcedInline(String text, bool isDark) {
    final parts = text.split('|||');
    const fontSize = 13.0;
    final inlineSpans = <InlineSpan>[];

    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        if (parts[i].isNotEmpty) {
          inlineSpans.add(TextSpan(
            text: parts[i],
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: fontSize,
              height: 1.5,
              color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
            ),
          ));
        }
      } else {
        if (parts[i].trim().isNotEmpty) {
          inlineSpans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _InlineMathWidget(
              latex: parts[i].trim(),
              fontSize: fontSize,
            ),
          ));
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: RichText(
            softWrap: true,
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize,
                color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
                height: 1.5,
              ),
              children: inlineSpans,
            ),
          ),
        );
      },
    );
  }

  /// 检测文本是否包含行内 Markdown 格式
  /// 注意：不包括 ## 等标题标记，因为标题已在前面单独处理
  bool _containsMarkdown(String text) {
    // 只检测行内格式：**bold**, __bold__, *italic*, _italic_, `code`, ~~strike~~
    return RegExp(r'\*\*|__|\*|_|`|~~').hasMatch(text);
  }

  /// 处理混合了 Markdown 和数学公式的内容
  /// 关键：必须用 RichText + TextSpan/WidgetSpan，不能用 Wrap
  Widget _buildMixedContent(String text, List<_InlineSpan> spans, bool isDark) {
    const fontSize = 13.0;
    final inlineSpans = <InlineSpan>[];

    for (final span in spans) {
      if (span.isText) {
        // 文本部分：尝试解析 Markdown 格式
        final markdownSpans = _parseMarkdownSpans(span.content, fontSize, isDark);
        inlineSpans.addAll(markdownSpans);
      } else {
        // 公式部分：WidgetSpan + baseline 对齐
        inlineSpans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _InlineMathWidget(
            latex: span.content,
            fontSize: fontSize,
          ),
        ));
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: RichText(
            softWrap: true,
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize,
                color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
                height: 1.5,
              ),
              children: inlineSpans,
            ),
          ),
        );
      },
    );
  }

  /// 解析 Markdown 格式为 TextSpan（粗体、斜体等）
  List<InlineSpan> _parseMarkdownSpans(String text, double fontSize, bool isDark) {
    final spans = <InlineSpan>[];
    if (text.isEmpty) return spans;

    // 匹配 Markdown 格式，支持跨行：**bold**, __bold__, *italic*, _italic_, `code`
    // 使用 [\s\S] 替代 . 来匹配包括换行符在内的任意字符
    final markdownRegex = RegExp(r'(\*\*|__)([\s\S]*?)\1|\*([^\*]+)\*|_([^_]+)_|`([^`]+)`');
    int lastEnd = 0;

    for (final match in markdownRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            height: 1.5,
          ),
        ));
      }

      final fullMatch = match.group(0)!;
      if (fullMatch.startsWith('**') || fullMatch.startsWith('__')) {
        // 粗体
        spans.add(TextSpan(
          text: match.group(2),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.5,
          ),
        ));
      } else if (fullMatch.startsWith('*') || fullMatch.startsWith('_')) {
        // 斜体
        final italicContent = match.group(3) ?? match.group(4);
        spans.add(TextSpan(
          text: italicContent,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            fontStyle: FontStyle.italic,
            height: 1.5,
          ),
        ));
      } else if (fullMatch.startsWith('`')) {
        // 行内代码
        spans.add(TextSpan(
          text: match.group(5),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize * 0.9,
            backgroundColor: PixelTheme.surfaceVariantFor(isDark),
            color: PixelTheme.primaryFor(isDark),
            height: 1.5,
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          height: 1.5,
        ),
      ));
    }

    return spans;
  }

  List<_InlineSpan> _parseInlineSpans(String text) {
    final spans = <_InlineSpan>[];

    // 匹配行内公式 $...$
    // 使用 [\s\S] 匹配任意字符（包括换行），处理复杂的 LaTeX 内容
    final inlineMathRegex = RegExp(r'\$([\s\S]*?)\$');
    int lastEnd = 0;

    for (final match in inlineMathRegex.allMatches(text)) {
      final formulaContent = match.group(1) ?? '';
      // 过滤掉空白内容
      if (formulaContent.trim().isEmpty) {
        lastEnd = match.end;
        continue;
      }

      if (match.start > lastEnd) {
        spans.add(_InlineSpan(text.substring(lastEnd, match.start)));
      }
      spans.add(_InlineSpan(formulaContent, isMath: true));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(_InlineSpan(text.substring(lastEnd)));
    }

    return spans;
  }

  Widget _buildMarkdownWidget(String text, bool isDark) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    // 处理单行 Markdown（没有段落分隔符）
    return MarkdownBody(
      data: text,
      selectable: selectable,
      shrinkWrap: true,
      fitContent: true,
      styleSheet: _buildStyleSheet(isDark),
      imageBuilder: (uri, title, alt) {
        return _MathAwareMarkdown._buildNetworkImage(uri, alt: alt);
      },
      onTapLink: (text, href, title) {
        if (href != null) _openUrl(href);
      },
    );
  }

  Future<void> _openUrl(String url) async {
    // 过滤零宽空格后再跳转
    final cleanUrl = url.replaceAll('​', '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildMathBlock(String latex) {
    return Builder(
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? PixelTheme.darkCodeBlockBg : PixelTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: (isDark ? PixelTheme.darkPrimary : PixelTheme.primary).withValues(alpha: 0.4),
                width: 3,
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              latex,
              mathStyle: MathStyle.display,
              textStyle: TextStyle(
                fontSize: 18,
                color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText,
              ),
              onErrorFallback: (error) => Text(
                r'$$' + latex + r'$$',
                style: TextStyle(color: isDark ? PixelTheme.error : PixelTheme.error, fontSize: 13),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCodeBlock(String codeBlock, {bool isStreaming = false}) {
    final match = RegExp(r'```(\w*)\n?([\s\S]*?)```').firstMatch(codeBlock);
    final language = match?.group(1) ?? '';
    final code = match?.group(2)?.trim() ?? codeBlock.trim();

    final block = _CollapsibleCodeBlock(code: code, language: language.isEmpty ? null : language, isStreaming: isStreaming);

    if (language.toLowerCase() == 'html' && code.isNotEmpty && !isStreaming) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block,
          const SizedBox(height: 6),
          _HtmlPreviewButton(htmlContent: code),
        ],
      );
    }
    return block;
  }

  MarkdownStyleSheet _buildStyleSheet(bool isDark) {
    // 使用 PixelTheme 规范颜色（符合最佳实践指南）
    final bodyColor = PixelTheme.textPrimaryFor(isDark);
    final h2Color = PixelTheme.mdH2ColorFor(isDark);
    final h3Color = PixelTheme.mdH3ColorFor(isDark);
    final quoteBg = PixelTheme.mdQuoteBgFor(isDark);
    final quoteBorder = PixelTheme.mdQuoteBorderFor(isDark);
    final codeBlockBg = PixelTheme.mdCodeBgFor(isDark);
    final codeBlockBorder = PixelTheme.mdCodeBorderFor(isDark);
    final hrColor = PixelTheme.mdHrFor(isDark);
    final tableBorder = PixelTheme.mdTableBorderFor(isDark);
    final tableHeadBg = PixelTheme.mdTableHeadBgFor(isDark);
    final listBullet = PixelTheme.mdListBulletFor(isDark);

    return MarkdownStyleSheet(
      // ========== 正文 ==========
      // 14sp, height 1.7（中文排版标准），字间距提升易读性
      p: _withEmojiFallback(TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: PixelTheme.mdBodyFontSize,
        height: PixelTheme.mdLineHeight,
        color: bodyColor,
        letterSpacing: PixelTheme.mdLetterSpacing,
      )),
      blockSpacing: 12,

      // ========== 代码 ==========
      code: _withEmojiFallback(TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: PixelTheme.mdCodeFontSize,
        height: PixelTheme.mdCodeLineHeight,
        backgroundColor: codeBlockBg,
        color: bodyColor,
      )),
      codeblockDecoration: BoxDecoration(
        color: codeBlockBg,
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        border: Border.all(color: codeBlockBorder, width: 1),
      ),
      codeblockPadding: const EdgeInsets.all(14),

      // ========== 表格 ==========
      // 表头：加粗 + 背景色区分
      tableHead: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: bodyColor,
      ),
      tableBody: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: 13,
        color: bodyColor,
      ),
      // 边框加粗至 1.5，表头加背景色
      tableBorder: TableBorder.all(
        color: tableBorder,
        width: PixelTheme.mdTableBorderWidth,
      ),
      tableHeadAlign: TextAlign.center,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tableColumnWidth: const IntrinsicColumnWidth(),

      // ========== 标题 ==========
      // H1 22sp, H2 18sp, H3 16sp，字重 w700，层级差距明显
      h1: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: PixelTheme.mdH1FontSize,
        fontWeight: FontWeight.w700,
        height: PixelTheme.mdHeadingLineHeight,
        color: PixelTheme.mdH1ColorFor(isDark),
        letterSpacing: 0.3,
      ),
      h2: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: PixelTheme.mdH2FontSize,
        fontWeight: FontWeight.w600,
        height: PixelTheme.mdHeadingLineHeight,
        color: h2Color,
        letterSpacing: 0.2,
      ),
      h3: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: PixelTheme.mdH3FontSize,
        fontWeight: FontWeight.w600,
        height: PixelTheme.mdHeadingLineHeight,
        color: h3Color,
        letterSpacing: 0.1,
      ),
      h4: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: PixelTheme.mdH4FontSize,
        fontWeight: FontWeight.w600,
        color: bodyColor,
      ),
      h5: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: bodyColor,
      ),
      h6: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: h3Color,
      ),

      // ========== 链接 ==========
      a: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: PixelTheme.mdBodyFontSize,
        color: h2Color,
        decoration: TextDecoration.underline,
        decorationColor: h2Color.withValues(alpha: 0.4),
      ),

      // ========== 列表 ==========
      // 统一用 •，缩进递进，项间有空隙
      listBullet: TextStyle(
        fontSize: PixelTheme.mdBodyFontSize,
        color: listBullet,
        height: PixelTheme.mdLineHeight,
      ),
      listIndent: 28,

      // ========== 分隔线 ==========
      // 章节间视觉分隔
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hrColor, width: 1, strokeAlign: BorderSide.strokeAlignCenter),
        ),
      ),

      // ========== 引用块 ==========
      blockquote: TextStyle(
        fontFamily: PixelTheme.mdFontFamily,
        fontSize: PixelTheme.mdBodyFontSize,
        color: h3Color,
        height: PixelTheme.mdLineHeight,
      ),
      blockquoteDecoration: BoxDecoration(
        color: quoteBg,
        border: Border(left: BorderSide(color: quoteBorder, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),

      // ========== 任务列表 ==========
      checkbox: TextStyle(
        color: listBullet,
      ),
    );
  }

  TextStyle _buildHeadingStyle(double size, Color color, bool isDark) {
    return TextStyle(
      fontFamily: 'monospace', fontSize: size, fontWeight: FontWeight.w700, color: color,
      height: 1.3, letterSpacing: 0.3,
    );
  }

  /// 构建网络图片（供 _buildMarkdownWidget 和 _buildScrollableTable 调用）
  static Widget _buildNetworkImage(dynamic uri, {String? alt}) {
    // 清理零宽空格（长链接可能被插入过）
    final uriStr = uri.toString().replaceAll('​', '');
    final uriObj = Uri.tryParse(uriStr);
    if (uriObj == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.broken_image, size: 24, color: Colors.grey),
            if (alt != null) ...[
              const SizedBox(width: 8),
              Flexible(child: Text(alt, style: const TextStyle(fontSize: 12, color: Colors.grey))),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(uriStr.replaceAll('​', ''));
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            uriStr,
            width: double.infinity,
            fit: BoxFit.contain,
            cacheWidth: 600,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: double.infinity,
                height: 200,
                alignment: Alignment.center,
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              width: double.infinity,
              height: 100,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image, size: 32, color: Colors.grey),
                  if (alt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(alt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 用于分割文本的部分（公式块或普通文本）
class _TextPart {

  _TextPart(this.content, {required this.isMathBlock});
  final String content;
  final bool isMathBlock;
}

/// 行内元素（文字或公式）
class _InlineSpan {

  _InlineSpan(this.content, {this.isMath = false});
  final String content;
  final bool isMath;

  bool get isText => !isMath;
}

/// 可自由选择的 Markdown（选择文字后显示复制按钮）
class _FreeSelectableMarkdown extends StatelessWidget {

  const _FreeSelectableMarkdown({required this.content, this.selectable = true});
  final String content;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    // 先提取图片（支持 ![描述](url) 和纯 url）
    final result = _extractAllImages();
    final imageWidgets = result.widgets;
    final usedUrls = result.urls;

    // 检测是否包含代码块或数学公式
    final hasCodeBlock = content.contains('```');
    final hasMath = content.contains(r'$') || content.contains('数学');

    // 提取后剩余的纯文本内容
    var textOnly = content;
    // 移除 ![描述](url) 格式
    textOnly = textOnly.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
      (m) => '',
    );
    // 移除已渲染的图片 URL
    for (final url in usedUrls) {
      textOnly = textOnly.replaceAll(url, '');
    }
    textOnly = textOnly.trim();

    if (hasCodeBlock || hasMath) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...imageWidgets,
          if (textOnly.isNotEmpty) _MathAwareMarkdown(content: textOnly, selectable: selectable),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...imageWidgets,
        if (textOnly.isNotEmpty) _buildMarkdownWithLinks(textOnly),
      ],
    );
  }

  /// 提取 Markdown 图片和纯 URL 并渲染
  ({List<Widget> widgets, Set<String> urls}) _extractAllImages() {
    final widgets = <Widget>[];
    final usedUrls = <String>{};

    // 提取 ![描述](url) 格式
    final regex1 = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');
    for (final match in regex1.allMatches(content)) {
      final alt = match.group(1) ?? '';
      final url = match.group(2)?.replaceAll('​', '') ?? '';
      if (url.isNotEmpty && !usedUrls.contains(url)) {
        usedUrls.add(url);
        widgets.add(_FreeSelectableMarkdown._buildNetworkImage(url, alt: alt));
      }
    }

    // 提取独立图片 URL
    final regex2 = RegExp(r'https?://[^\s\)>\]]+');
    for (final match in regex2.allMatches(content)) {
      final url = match.group(0)?.replaceAll('​', '') ?? '';
      if (url.isNotEmpty && !usedUrls.contains(url)) {
        final isImageUrl = url.contains('staticmap') || url.contains('image')
            || url.endsWith('.png') || url.endsWith('.jpg') || url.endsWith('.jpeg');
        if (isImageUrl) {
          usedUrls.add(url);
          widgets.add(_FreeSelectableMarkdown._buildNetworkImage(Uri.parse(url), alt: '图片'));
        }
      }
    }

    return (widgets: widgets, urls: usedUrls);
  }

  Widget _buildMarkdownWithLinks(String content) {
    final hasTable = content.contains('|') && content.contains('---');
    return Builder(
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final md = MarkdownBody(
          data: content,
          selectable: selectable,
          shrinkWrap: true,
          fitContent: true,
          styleSheet: _buildStyleSheet(isDark),
          imageBuilder: (uri, title, alt) {
            return _FreeSelectableMarkdown._buildNetworkImage(uri, alt: alt);
          },
          onTapLink: (text, href, title) async {
            if (href != null) {
              final uri = Uri.tryParse(href.replaceAll('​', ''));
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          },
        );
        if (hasTable) {
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: md);
        }
        return md;
      },
    );
  }

  MarkdownStyleSheet _buildStyleSheet(bool isDark) {
    // 颜色规范（明确 Hex 值）
    const lightBody = Color(0xFF1A1A1A);
    const lightH2 = Color(0xFF2563EB);
    const lightH3 = Color(0xFF374151);
    const lightQuoteBg = Color(0xFFF3F4F6);
    const lightQuoteBorder = Color(0xFFD1D5DB);
    const lightCodeBlockBg = Color(0xFFF8F9FA);
    const lightHr = Color(0xFFE5E7EB);

    const darkBody = Color(0xFFE5E7EB);
    const darkH2 = Color(0xFF60A5FA);
    const darkH3 = Color(0xFF9CA3AF);
    const darkQuoteBg = Color(0xFF1F2937);
    const darkQuoteBorder = Color(0xFF4B5563);
    const darkCodeBlockBg = Color(0xFF111827);
    const darkHr = Color(0xFF374151);

    final bodyColor = isDark ? darkBody : lightBody;
    final h2Color = isDark ? darkH2 : lightH2;
    final h3Color = isDark ? darkH3 : lightH3;
    final quoteBg = isDark ? darkQuoteBg : lightQuoteBg;
    final quoteBorder = isDark ? darkQuoteBorder : lightQuoteBorder;
    final codeBlockBg = isDark ? darkCodeBlockBg : lightCodeBlockBg;
    final hrColor = isDark ? darkHr : lightHr;

    return MarkdownStyleSheet(
      // 正文：14sp, height 1.7（中文行高，>= 1.5）
      p: _withEmojiFallback(TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.7, color: bodyColor, letterSpacing: 0.2)),
      blockSpacing: 12,
      // 代码
      code: _withEmojiFallback(TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        backgroundColor: codeBlockBg,
        color: bodyColor,
      )),
      codeblockDecoration: BoxDecoration(
        color: codeBlockBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      // 表格：边框加粗至 1.5，表头加背景色区分
      tableHead: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13, color: bodyColor),
      tableBody: TextStyle(fontFamily: 'monospace', fontSize: 13, color: bodyColor),
      tableBorder: TableBorder.all(
        color: isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB),
        width: 1.5,
      ),
      tableHeadAlign: TextAlign.center,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tableColumnWidth: const IntrinsicColumnWidth(),
      // 标题：H1 22sp, H2 18sp, H3 16sp，字重 w700/w600，标题与正文差距拉开
      h1: TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w700, height: 1.3, color: bodyColor, letterSpacing: 0.3),
      h2: TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w600, height: 1.35, color: h2Color, letterSpacing: 0.2),
      h3: TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: h3Color, letterSpacing: 0.1),
      h4: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600, color: bodyColor),
      h5: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600, color: bodyColor),
      h6: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600, color: h3Color),
      // 链接：长链接软换行，不溢出撑开布局
      a: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: h2Color,
        decoration: TextDecoration.underline,
        decorationColor: h2Color.withValues(alpha: 0.4),
        overflow: TextOverflow.visible,
      ),
      // 列表：bullet 颜色跟随 h2 蓝，列表项间距用 blockSpacing 控制
      listBullet: TextStyle(fontSize: 14, color: h2Color, height: 1.7),
      listIndent: 28,
      // 分隔线：章节间视觉分隔
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: hrColor, width: 1, strokeAlign: BorderSide.strokeAlignCenter)),
      ),
      // 引用块
      blockquote: TextStyle(fontFamily: 'monospace', fontSize: 14, color: isDark ? darkH3 : lightH3, height: 1.7),
      blockquoteDecoration: BoxDecoration(
        color: quoteBg,
        border: Border(left: BorderSide(color: quoteBorder, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
    );
  }

  TextStyle _buildHeadingStyle(double size, Color color, bool isDark) {
    return TextStyle(
      fontFamily: 'monospace', fontSize: size, fontWeight: FontWeight.w700, color: color,
      height: 1.3, letterSpacing: 0.3,
    );
  }

  /// 构建网络图片（供 _buildMarkdownWidget 和 _buildScrollableTable 调用）
  static Widget _buildNetworkImage(dynamic uri, {String? alt}) {
    // 清理零宽空格（长链接可能被插入过）
    final uriStr = uri.toString().replaceAll('​', '');
    final uriObj = Uri.tryParse(uriStr);
    if (uriObj == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.broken_image, size: 24, color: Colors.grey),
            if (alt != null) ...[
              const SizedBox(width: 8),
              Flexible(child: Text(alt, style: const TextStyle(fontSize: 12, color: Colors.grey))),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(uriStr.replaceAll('​', ''));
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            uriStr,
            width: double.infinity,
            fit: BoxFit.contain,
            cacheWidth: 600,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: double.infinity,
                height: 200,
                alignment: Alignment.center,
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              width: double.infinity,
              height: 100,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image, size: 32, color: Colors.grey),
                  if (alt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(alt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.replaceAll('​', ''));
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 处理后的 Markdown（包含代码块折叠和表格滚动）
class _ProcessedMarkdown extends StatefulWidget {

  const _ProcessedMarkdown({required this.content});
  final String content;

  @override
  State<_ProcessedMarkdown> createState() => _ProcessedMarkdownState();
}

class _ProcessedMarkdownState extends State<_ProcessedMarkdown> {
  List<Widget>? _widgets;
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _processContent();
  }

  @override
  void didUpdateWidget(_ProcessedMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _processContent();
    }
  }

  void _processContent() {
    final content = widget.content;
    final widgets = <Widget>[];

    // 分割代码块和普通内容
    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    int lastEnd = 0;

    for (final match in codeBlockRegex.allMatches(content)) {
      // 添加匹配之前的普通内容
      if (match.start > lastEnd) {
        final textBefore = content.substring(lastEnd, match.start);
        if (textBefore.trim().isNotEmpty) {
          final hasTable = textBefore.contains('|') && textBefore.contains('---');
          final md = MarkdownBody(
            data: textBefore,
            selectable: true,
            shrinkWrap: true,
            fitContent: true,
            styleSheet: _buildStyleSheet(),
            imageBuilder: (uri, title, alt) {
              return _FreeSelectableMarkdown._buildNetworkImage(uri, alt: alt);
            },
            onTapLink: (text, href, title) async {
              if (href != null) {
                final uri = Uri.tryParse(href.replaceAll('​', ''));
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
          );
          widgets.add(hasTable
              ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: md)
              : md);
        }
      }

      // 添加代码块
      final language = match.group(1) ?? '';
      final code = match.group(2) ?? '';
      widgets.add(_CollapsibleCodeBlock(
        code: code.trim(),
        language: language.isEmpty ? null : language,
      ));

      lastEnd = match.end;
    }

    // 添加剩余的普通内容
    if (lastEnd < content.length) {
      final remaining = content.substring(lastEnd);
      if (remaining.trim().isNotEmpty) {
        final hasTable = remaining.contains('|') && remaining.contains('---');
        final md = MarkdownBody(
          data: remaining,
          selectable: true,
          shrinkWrap: true,
          fitContent: true,
          styleSheet: _buildStyleSheet(),
          imageBuilder: (uri, title, alt) {
            return _FreeSelectableMarkdown._buildNetworkImage(uri, alt: alt);
          },
        );
        widgets.add(hasTable
            ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: md)
            : md);
      }
    }

    _widgets = widgets;
  }

  MarkdownStyleSheet _buildStyleSheet() {
    // 颜色规范（明确 Hex 值）
    const lightBody = Color(0xFF1A1A1A);
    const lightH2 = Color(0xFF2563EB);
    const lightH3 = Color(0xFF374151);
    const lightCodeBlockBg = Color(0xFFF8F9FA);
    const lightHr = Color(0xFFE5E7EB);

    const darkBody = Color(0xFFE5E7EB);
    const darkH2 = Color(0xFF60A5FA);
    const darkH3 = Color(0xFF9CA3AF);
    const darkCodeBlockBg = Color(0xFF111827);
    const darkHr = Color(0xFF374151);

    final bodyColor = _isDark ? darkBody : lightBody;
    final h2Color = _isDark ? darkH2 : lightH2;
    final h3Color = _isDark ? darkH3 : lightH3;
    final codeBlockBg = _isDark ? darkCodeBlockBg : lightCodeBlockBg;
    final hrColor = _isDark ? darkHr : lightHr;

    return MarkdownStyleSheet(
      p: _withEmojiFallback(TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.7, color: bodyColor, letterSpacing: 0.2)),
      blockSpacing: 12,
      code: _withEmojiFallback(TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        backgroundColor: codeBlockBg,
        color: bodyColor,
      )),
      codeblockDecoration: BoxDecoration(
        color: codeBlockBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hrColor),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      tableHead: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13, color: bodyColor),
      tableBody: TextStyle(fontFamily: 'monospace', fontSize: 13, color: bodyColor),
      tableBorder: TableBorder.all(
        color: _isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB),
        width: 1.5,
      ),
      tableHeadAlign: TextAlign.center,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      tableColumnWidth: const IntrinsicColumnWidth(),
      h1: TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w700, height: 1.3, color: bodyColor),
      h2: TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w600, height: 1.35, color: h2Color),
      h3: TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: h3Color),
      h4: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600, color: bodyColor),
      h5: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600, color: bodyColor),
      h6: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600, color: h3Color),
      listBullet: TextStyle(fontSize: 14, color: h2Color, height: 1.7),
      listIndent: 28,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: hrColor, width: 1, strokeAlign: BorderSide.strokeAlignCenter)),
      ),
      blockquote: TextStyle(fontFamily: 'monospace', fontSize: 14, color: h3Color, height: 1.7),
      blockquoteDecoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
        border: Border(left: BorderSide(color: _isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB), width: 4)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;
    _processContent();
    if (_widgets == null || _widgets!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _widgets!,
    );
  }
}

/// 流式输出的 Markdown 组件
class _StreamingMarkdown extends StatefulWidget {

  const _StreamingMarkdown({required this.content});
  final String content;

  @override
  State<_StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<_StreamingMarkdown>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(_StreamingMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _controller.reset();
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 清理不完整的 LaTeX 公式，防止解析错误闪烁
    final safeContent = _sanitizeMath(widget.content);

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: _MathAwareMarkdown(content: safeContent, isStreaming: true),
        );
      },
    );
  }
}

class _HtmlPreviewButton extends StatelessWidget {
  const _HtmlPreviewButton({required this.htmlContent});
  final String htmlContent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final container = ProviderScope.containerOf(context);
    return GestureDetector(
      onTap: () {
        _previewHtml(container, htmlContent);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: PixelTheme.brandBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PixelTheme.brandBlue.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_browser, size: 14, color: PixelTheme.brandBlue),
            SizedBox(width: 4),
            Text('预览 HTML', style: TextStyle(fontSize: 12, color: PixelTheme.brandBlue, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _previewHtml(ProviderContainer container, String html) {
    container.read(browserEngineActiveProvider.notifier).state = true;
    container.read(browserPanelVisibleProvider.notifier).state = true;
    Future.delayed(const Duration(milliseconds: 200), () {
      final handler = container.read(browserToolHandlerProvider);
      if (handler == null) {
        container.read(browserTabsProvider.notifier).addTab();
        Future.delayed(const Duration(milliseconds: 200), () {
          final h = container.read(browserToolHandlerProvider);
          final idx = container.read(browserActiveTabIndexProvider);
          final c = h?.controllers[idx];
          c?.loadData(data: html, mimeType: 'text/html');
        });
        return;
      }
      final idx = container.read(browserActiveTabIndexProvider);
      final c = handler.controllers[idx];
      c?.loadData(data: html, mimeType: 'text/html');
    });
  }
}
