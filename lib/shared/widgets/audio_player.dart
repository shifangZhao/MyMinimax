import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../app/theme.dart';

class AudioPlayerWidget extends StatefulWidget {

  const AudioPlayerWidget({
    super.key,
    this.audioUrl,
    this.audioBase64,
    this.localPath,
    this.title,
    this.lyrics,
  });
  final String? audioUrl;
  final String? audioBase64;
  final String? localPath;
  final String? title;
  final String? lyrics;

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget>
    with TickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = false;
  bool _isDownloaded = false;
  String? _downloadedPath;
  String? _error;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  late AnimationController _rotationController;

  bool get _hasLocalFile =>
      widget.localPath != null && File(widget.localPath!).existsSync();
  String? get _effectiveLocalPath => widget.localPath ?? _downloadedPath;

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 12000),
    );

    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) {
        setState(() => _playerState = s);
        _syncRotation();
      }
    });
  }

  void _syncRotation() {
    if (_playerState == PlayerState.playing) {
      _rotationController.repeat();
    } else {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _rotationController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    final path = _effectiveLocalPath;
    if (path == null) return;

    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(path));
    }
  }

  Future<void> _seek(double value) async {
    if (_duration.inMilliseconds > 0) {
      await _player.seek(
        Duration(milliseconds: (_duration.inMilliseconds * value).round()),
      );
    }
  }

  Future<void> _openInBrowser() async {
    if (widget.audioUrl == null) return;
    final uri = Uri.parse(widget.audioUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadAudio() async {
    if (widget.audioUrl == null) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final dio = Dio();
      final response = await dio.get(
        widget.audioUrl!,
        options: Options(responseType: ResponseType.bytes),
      );
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'music_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(response.data);
      _downloadedPath = file.path;
      if (mounted) {
        setState(() { _isLoading = false; _isDownloaded = true; });
      }
    } catch (e) {
      print('[audio] error: \$e');
      if (mounted) {
        setState(() { _error = '下载失败: $e'; _isLoading = false; });
      }
    }
  }

  Future<void> _openFile() async {
    final path = _effectiveLocalPath;
    if (path != null) await OpenFilex.open(path);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.audioUrl == null &&
        widget.audioBase64 == null &&
        widget.localPath == null) {
      return const SizedBox.shrink();
    }

    if (_hasLocalFile || _isDownloaded) {
      return _buildInAppPlayer();
    }

    return _buildExternalPlayer();
  }

  // ─── In-App Player ───────────────────────────────────────────

  Widget _buildInAppPlayer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPlaying = _playerState == PlayerState.playing;
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;
    final accent = isDark ? PixelTheme.darkAccent : PixelTheme.accent;
    final hasLyrics = widget.lyrics != null && widget.lyrics!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkSurface : const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
        border: Border.all(
          color: isDark ? PixelTheme.darkBorderSubtle : const Color(0xFFE5E7EB),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Cover + Lyrics row ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRotatingCover(isDark, accent, isPlaying),
              const SizedBox(width: 12),
              Expanded(child: hasLyrics ? _buildLyricsPanel(isDark) : _buildInfoPanel(isDark)),
            ],
          ),

          const SizedBox(height: 10),

          // ── Progress ──
          _buildProgressBar(isDark, accent, progress),

          const SizedBox(height: 6),

          // ── Time + Controls row ──
          Row(children: [
            Text(_formatDuration(_position),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
            const Spacer(),
            _buildPlayPauseBtn(isDark, accent, isPlaying),
            const Spacer(),
            Text(_formatDuration(_duration),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
          ]),
        ],
      ),
    );
  }

  // ─── Rotating Cover ──────────────────────────────────────────

  Widget _buildRotatingCover(bool isDark, Color accent, bool isPlaying) {
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationController.value * 2 * 3.1415926535,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: isPlaying ? 0.25 : 0.08),
                  blurRadius: isPlaying ? 14 : 6,
                  spreadRadius: isPlaying ? 1 : 0,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF0B0B14) : const Color(0xFFF2F3F5),
                  ),
                ),
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Lyrics Panel ────────────────────────────────────────────

  Widget _buildLyricsPanel(bool isDark) {
    final lyrics = widget.lyrics ?? '';
    return SizedBox(
      height: 72,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            lyrics,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Info Panel (when no lyrics) ─────────────────────────────

  Widget _buildInfoPanel(bool isDark) {
    return SizedBox(
      height: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.title ?? '音乐',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (isDark ? PixelTheme.darkAccent : PixelTheme.accent).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              _duration.inMilliseconds > 0 ? '${_formatDuration(_duration)} · MP3' : 'MP3 音频',
              style: TextStyle(fontSize: 11, color: isDark ? PixelTheme.darkAccent : PixelTheme.accent),
            ),
          ),
          const Spacer(),
          if (widget.audioUrl != null)
            GestureDetector(
              onTap: _openInBrowser,
              child: Text('浏览器打开 →', style: TextStyle(fontSize: 10, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
            ),
        ],
      ),
    );
  }

  // ─── Progress Bar ────────────────────────────────────────────

  Widget _buildProgressBar(bool isDark, Color accent, double progress) {
    return GestureDetector(
      onTapDown: (d) => _seekByTap(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _seekByTap(d.localPosition.dx),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: isDark ? PixelTheme.darkElevated : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: 3,
                width: barWidth * progress.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              Positioned(
                left: (barWidth * progress.clamp(0.0, 1.0)) - 5,
                top: -4,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: progress > 0.01
                      ? Container(
                          key: const ValueKey('thumb'),
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 4)],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _seekByTap(double dx) {
    final ctx = context;
    if (ctx.size == null) return;
    final barWidth = ctx.size!.width - 32;
    final ratio = (dx / barWidth).clamp(0.0, 1.0);
    _seek(ratio);
  }

  // ─── Play/Pause Button ───────────────────────────────────────

  Widget _buildPlayPauseBtn(bool isDark, Color accent, bool isPlaying) {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: isPlaying
                ? [accent, accent.withValues(alpha: 0.75)]
                : [isDark ? Colors.white : PixelTheme.primary, (isDark ? Colors.white : PixelTheme.primary).withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: isPlaying ? Colors.white : (isDark ? PixelTheme.darkBase : Colors.white),
          size: 20,
        ),
      ),
    );
  }

  // ─── External Player ─────────────────────────────────────────

  Widget _buildExternalPlayer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkSurface : const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
        border: Border.all(color: isDark ? PixelTheme.darkBorderSubtle : const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            gradient: PixelTheme.accentGradient,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.music_note_rounded, size: 20, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(widget.title ?? '音乐', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
        const SizedBox(height: 2),
        Text('MP3 音频 · 暂无本地文件', style: TextStyle(fontSize: 11, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: PixelTheme.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [const Icon(Icons.error_outline, size: 14, color: PixelTheme.error), const SizedBox(width: 6), Expanded(child: Text(_error!, style: const TextStyle(color: PixelTheme.error, fontSize: 11)))]),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _buildChipButton(icon: Icons.play_arrow_rounded, label: '浏览器播放', onTap: _isLoading ? null : _openInBrowser, isDark: isDark)),
          const SizedBox(width: 8),
          Expanded(child: _buildChipButton(icon: _isDownloaded ? Icons.folder_open : Icons.download_rounded, label: _isDownloaded ? '已下载' : '下载', onTap: _isLoading ? null : (_isDownloaded ? _openFile : _downloadAudio), isLoading: _isLoading, isDark: isDark)),
        ]),
        if (_downloadedPath != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_downloadedPath!, style: TextStyle(fontSize: 10, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _buildChipButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required bool isDark, bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: onTap != null
              ? (isDark ? PixelTheme.darkPrimaryGradient : PixelTheme.primaryGradient)
              : null,
          color: onTap != null ? null : (isDark ? PixelTheme.darkElevated : const Color(0xFFE5E7EB)),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: onTap != null ? Colors.white : (isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onTap != null ? Colors.white : (isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary))),
                ]),
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    if (d.inMilliseconds <= 0) return '0:00';
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

class AudioCard extends StatelessWidget {

  const AudioCard({super.key, this.audioUrl, this.title, this.onTap});
  final String? audioUrl;
  final String? title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ModernCard(
      onTap: onTap ?? () async {
        if (audioUrl != null) {
          final uri = Uri.parse(audioUrl!);
          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: PixelTheme.accentGradient, borderRadius: BorderRadius.circular(PixelTheme.radiusSm)), child: const Icon(Icons.music_note_rounded, size: 20, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title ?? '音乐', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
          if (audioUrl != null) Text(audioUrl!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
        ])),
        Icon(Icons.play_arrow, size: 20, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
      ]),
    );
  }
}
