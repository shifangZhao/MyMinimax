import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../image_gen/presentation/image_gen_page.dart';
import '../../video_gen/presentation/video_gen_page.dart';
import '../../music/presentation/music_gen_page.dart';
import '../../speech/presentation/speech_page.dart';

class _DesensitizedTabPhysics extends ScrollPhysics {
  const _DesensitizedTabPhysics({super.parent});
  @override
  _DesensitizedTabPhysics applyTo(ScrollPhysics? ancestor) =>
      _DesensitizedTabPhysics(parent: buildParent(ancestor));
  @override
  double get dragStartDistanceMotionThreshold => 40.0;
}

class CreationPage extends StatelessWidget {
  const CreationPage({super.key});

  static const _tabs = [
    (Icons.image_outlined, '图像'),
    (Icons.videocam_outlined, '视频'),
    (Icons.music_note_outlined, '音乐'),
    (Icons.mic_outlined, '语音'),
  ];

  static const _pages = [
    ImageGenPage(),
    VideoGenPage(),
    MusicGenPage(),
    SpeechPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = PixelTheme.dividerFor(isDark);
    return DefaultTabController(
      length: 4,
      child: SafeArea(
        child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            color: isDark ? PixelTheme.darkSurface : PixelTheme.cardBackground,
            child: TabBar(
              indicator: const BoxDecoration(),
              indicatorColor: Colors.transparent,
              dividerColor: Colors.transparent,
              indicatorWeight: 0,
              indicatorPadding: EdgeInsets.zero,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelColor: isDark ? PixelTheme.darkPrimary : PixelTheme.primary,
              unselectedLabelColor: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary,
              labelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, height: 1),
              unselectedLabelStyle: const TextStyle(fontSize: 9, height: 1),
              tabs: _tabs.map((t) => Tab(
                icon: Icon(t.$1, size: 20),
                text: t.$2,
                height: 40,
              )).toList(),
            ),
          ),
          Container(height: 0.5, color: dividerColor),
          Expanded(
            child: TabBarView(
              physics: const _DesensitizedTabPhysics(),
              children: _pages,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
