import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../app/theme.dart';

class VideoResultPlayer extends StatefulWidget {
  const VideoResultPlayer({required this.videoUrl, super.key});
  final String videoUrl;

  @override
  State<VideoResultPlayer> createState() => _VideoResultPlayerState();
}

class _VideoResultPlayerState extends State<VideoResultPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initController(widget.videoUrl);
  }

  @override
  void didUpdateWidget(VideoResultPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl) {
      _disposeController();
      _initController(widget.videoUrl);
    }
  }

  void _disposeController() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
    _isPlaying = false;
    _error = null;
  }

  Future<void> _initController(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.hasScheme && !url.startsWith('/'))) {
      setState(() => _error = '无效的视频链接');
      return;
    }

    // 支持相对路径自动补全 MiniMax CDN URL
    final effectiveUrl = (!uri.hasScheme && url.startsWith('/'))
        ? 'https://api.minimax.chat$url'
        : url;

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(effectiveUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      _controller = controller;
      _controller!.addListener(_onControllerUpdate);
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _error = null;
        });
        _controller!.play();
        _isPlaying = true;
      }
    } catch (e) {
      print('[video] error: \$e');
      if (mounted) {
        setState(() => _error = '视频加载失败: ${e.toString()}');
      }
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    final playing = _controller!.value.isPlaying;
    if (playing != _isPlaying) {
      setState(() => _isPlaying = playing);
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: PixelTheme.error, size: 32),
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: PixelTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: PixelTheme.primary)),
      );
    }

    return GestureDetector(
      onTap: () {
        if (_isPlaying) {
          _controller!.pause();
        } else {
          _controller!.play();
        }
        setState(() => _isPlaying = !_isPlaying);
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: RepaintBoundary(child: VideoPlayer(_controller!)),
            ),
          ),
          if (!_isPlaying)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, size: 36, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}
