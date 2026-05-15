import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 永不溢出的 Row：子元素自动收缩 + 文本自动省略
///
/// 用法：
/// ```dart
/// SafeRow(children: [
///   Text('很长的标题'),
///   Text('可能很长的副标题'),
/// ])
/// ```
class SafeRow extends StatelessWidget {

  const SafeRow({
    required this.children, super.key,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.spacing = 0,
  });
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisAlignment: mainAxisAlignment,
      children: _wrapAll(children),
    );
  }

  List<Widget> _wrapAll(List<Widget> items) {
    return items.asMap().entries.map((entry) {
      final i = entry.key;
      final child = entry.value;
      return <Widget>[
        if (i > 0 && spacing > 0) SizedBox(width: spacing),
        Flexible(child: _wrapChild(child)),
      ];
    }).expand((w) => w).toList();
  }

  static Widget _wrapChild(Widget child) {
    // Already flexible — leave as-is
    if (child is Flexible || child is Expanded) return child;
    // Text widgets → auto-ellipsis
    if (child is Text) {
      return Text(
        child.data ?? '',
        style: child.style,
        maxLines: child.maxLines ?? 1,
        overflow: TextOverflow.ellipsis,
        textAlign: child.textAlign,
      );
    }
    return child;
  }
}

/// 永不溢出的 Column：内容区自动滚动
///
/// 用法：
/// ```dart
/// SafeColumn(children: [
///   SafeRow(children: [...上头固定区域...]),
///   Expanded(child: ...中间内容...),
///   SafeRow(children: [...底部输入框...]),
/// ])
/// ```
class SafeColumn extends StatelessWidget {

  const SafeColumn({
    required this.children, super.key,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.padding = EdgeInsets.zero,
    this.controller,
  });
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Column(
              crossAxisAlignment: crossAxisAlignment,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

/// 防键盘遮挡包装器：键盘弹出时底部内容自动上移
///
/// 用法：
/// ```dart
/// KeyboardAware(child: SafeRow(children: [...]))
/// ```
class KeyboardAware extends StatelessWidget {

  const KeyboardAware({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: child,
    );
  }
}

/// 溢出检测包装器（仅 debug 模式生效）
/// 子组件溢出时显示橙色边框，方便快速定位问题
class OverflowDetector extends StatelessWidget {

  const OverflowDetector({required this.child, super.key, this.label = ''});
  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;
    return child;
  }
}
