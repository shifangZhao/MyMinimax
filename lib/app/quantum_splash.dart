import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// 量子觉醒启动动画 — 4 阶段
/// 0. 粒子汇聚  1. 神经连接  2. 坍缩为 Logo  3. 破壳展开
class QuantumSplash extends StatefulWidget {
  const QuantumSplash({super.key, required this.ready, required this.onReady, this.onComplete});
  final bool ready;
  final Future<void> onReady;
  final VoidCallback? onComplete;

  @override
  State<QuantumSplash> createState() => _QuantumSplashState();
}

class _QuantumSplashState extends State<QuantumSplash>
    with TickerProviderStateMixin {
  late AnimationController _particleCtrl;
  late AnimationController _networkCtrl;
  late AnimationController _collapseCtrl;
  late AnimationController _expandCtrl;
  int _phase = 0;
  int _loopCount = 0;

  static const _totalDuration = 4200; // ms

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000));
    _networkCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
    _collapseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));
    _expandCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));

    _runSequence();
    widget.onReady.then((_) {
      if (mounted && _phase < 3) {
        // Init done early — jump to shell break
        _particleCtrl.stop();
        _networkCtrl.stop();
        _collapseCtrl.stop();
        setState(() => _phase = 3);
        _expandCtrl.forward().then((_) => widget.onComplete?.call());
      }
    });
  }

  Future<void> _runSequence() async {
    while (!widget.ready && mounted) {
      _loopCount++;
      // Phase 0: particles
      setState(() => _phase = 0);
      _particleCtrl.reset();
      await _particleCtrl.forward();
      if (widget.ready) break;

      // Phase 1: network
      setState(() => _phase = 1);
      _networkCtrl.reset();
      await _networkCtrl.forward();
      if (widget.ready) break;

      // Phase 2: collapse
      setState(() => _phase = 2);
      _collapseCtrl.reset();
      await _collapseCtrl.forward();
      if (widget.ready) break;

      // Brief hold at logo
      await Future.delayed(const Duration(milliseconds: 400));
      if (widget.ready) break;
    }

    // Phase 3: shell break
    setState(() => _phase = 3);
    _expandCtrl.reset();
    await _expandCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    _networkCtrl.dispose();
    _collapseCtrl.dispose();
    _expandCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _NebulaBg(),
          if (_phase >= 0)
            _ParticleField(
              ctrl: _particleCtrl,
              size: size,
              visible: _phase == 0,
            ),
          if (_phase >= 1)
            _NeuralMesh(
              ctrl: _networkCtrl,
              size: size,
              visible: _phase == 1,
            ),
          if (_phase >= 2)
            _LogoCollapse(
              ctrl: _collapseCtrl,
              size: size,
              visible: _phase == 2,
            ),
          if (_phase >= 3)
            _ShellBreak(
              ctrl: _expandCtrl,
              size: size,
              phase: _phase,
            ),
          if (_phase < 3)
            Positioned(
              bottom: 80,
              left: 0, right: 0,
              child: Opacity(
                opacity: 0.3,
                child: Text(
                  _loopCount == 0 ? 'INITIALIZING' : 'LOADING MODULES',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10, letterSpacing: 4,
                    color: Color(0x66FFFFFF), fontFamily: 'monospace'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Nebula background ───
class _NebulaBg extends StatefulWidget {
  const _NebulaBg();
  @override
  State<_NebulaBg> createState() => _NebulaBgState();
}

class _NebulaBgState extends State<_NebulaBg>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 20))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _NebulaPainter(_ctrl.value),
        size: Size.infinite,
      ),
    );
  }
}

class _NebulaPainter extends CustomPainter {
  final double t;
  _NebulaPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A0A0F));
    final spots = [
      (Offset(size.width * 0.3, size.height * 0.4), const Color(0xFF1a1a3e)),
      (Offset(size.width * 0.7, size.height * 0.6), const Color(0xFF16213e)),
      (Offset(size.width * 0.5, size.height * 0.3), const Color(0xFF0f3460)),
    ];
    for (int i = 0; i < spots.length; i++) {
      final off = i * 2.094;
      final dx = spots[i].$1.dx + sin(t * 2 * pi + off) * 30;
      final dy = spots[i].$1.dy + cos(t * 1.5 * pi + off) * 20;
      final rect = Rect.fromCenter(center: Offset(dx, dy), width: size.width * 0.8, height: size.height * 0.8);
      canvas.drawRect(rect, Paint()
        ..shader = RadialGradient(colors: [spots[i].$2, const Color(0x000f3460)]).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
    }
  }

  @override
  bool shouldRepaint(covariant _NebulaPainter o) => true;
}

// ─── Phase 0: Particle field ───
class _ParticleField extends StatelessWidget {
  final AnimationController ctrl;
  final Size size;
  final bool visible;
  const _ParticleField({required this.ctrl, required this.size, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible && ctrl.isCompleted) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _ParticlePainter(ctrl.value, Offset(size.width / 2, size.height * 0.42)),
        size: size,
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double p;
  final Offset center;
  final Random rng = Random(42);
  _ParticlePainter(this.p, this.center);

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 80; i++) {
      final seed = rng.nextDouble();
      final angle = seed * 2 * pi;
      final startDist = 150 + rng.nextDouble() * 200;
      final ep = Curves.easeInOutCubic.transform(p.clamp(0.0, 1.0));
      final d = startDist * (1 - ep);
      final x = center.dx + cos(angle) * d;
      final y = center.dy + sin(angle) * d;
      final sz = 3 * (1 - ep * 0.7);
      final color = Color.lerp(const Color(0xFF00D4FF), const Color(0xFFB829DD), ep)!;
      double opacity = 1.0;
      if (p > 0.8) opacity = 1 - (p - 0.8) / 0.2;
      canvas.drawCircle(Offset(x, y), sz, Paint()
        ..color = color.withOpacity(opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
    if (p > 0.5) {
      final gp = (p - 0.5) / 0.5;
      canvas.drawCircle(center, 20, Paint()
        ..color = const Color(0xFFB829DD).withOpacity(gp * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter o) => true;
}

// ─── Phase 1: Neural mesh ───
class _NeuralMesh extends StatelessWidget {
  final AnimationController ctrl;
  final Size size;
  final bool visible;
  const _NeuralMesh({required this.ctrl, required this.size, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible && ctrl.isCompleted) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _NeuralPainter(ctrl.value, Offset(size.width / 2, size.height * 0.42)),
        size: size,
      ),
    );
  }
}

class _NeuralPainter extends CustomPainter {
  final double p;
  final Offset center;
  _NeuralPainter(this.p, this.center);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 6;
    final nodes = <Offset>[];
    for (int i = 0; i < n; i++) {
      final a = (i / n) * 2 * pi - pi / 2;
      nodes.add(Offset(center.dx + cos(a) * 60, center.dy + sin(a) * 60));
    }
    final lp = Curves.easeOutCubic.transform(p < 0.3 ? p / 0.3 : 1.0);
    final linePaint = Paint()..strokeWidth = 1.5..style = PaintingStyle.stroke;
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final idx = i * n + j;
        final total = (n * (n - 1)) ~/ 2;
        final th = idx / total;
        if (lp > th) {
          final lo = ((lp - th) * total).clamp(0.0, 1.0);
          final rect = Rect.fromPoints(nodes[i], nodes[j]);
          linePaint.shader = LinearGradient(colors: [
            const Color(0xFF00D4FF).withOpacity(lo * 0.6),
            const Color(0xFFB829DD).withOpacity(lo * 0.6),
          ]).createShader(rect);
          canvas.drawLine(nodes[i], nodes[j], linePaint);
        }
      }
    }
    final np = Curves.elasticOut.transform(p < 0.5 ? p / 0.5 : 1.0);
    for (int i = 0; i < n; i++) {
      final nd = i * 0.1;
      final nap = ((p - nd) / (1 - nd)).clamp(0.0, 1.0);
      if (nap <= 0) continue;
      final s = Curves.elasticOut.transform(nap);
      final r = 6 * s;
      canvas.drawCircle(nodes[i], r * 2, Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(0.2 * nap)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(nodes[i], r, Paint()..color = const Color(0xFF00D4FF).withOpacity(nap));
      canvas.drawCircle(nodes[i], r * 0.4, Paint()..color = Colors.white.withOpacity(nap));
    }
    if (p > 0.4) {
      final cp = (p - 0.4) / 0.6;
      final cs = Curves.easeOutBack.transform(cp);
      canvas.drawCircle(center, 25 * cs, Paint()
        ..color = const Color(0xFFB829DD).withOpacity(0.4 * cp)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20));
      final cr = Rect.fromCenter(center: center, width: 30, height: 30);
      canvas.drawCircle(center, 15 * cs, Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFFFFFFF), Color(0xFFB829DD)]).createShader(cr));
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralPainter o) => true;
}

// ─── Phase 2: Logo collapse ───
class _LogoCollapse extends StatelessWidget {
  final AnimationController ctrl;
  final Size size;
  final bool visible;
  const _LogoCollapse({required this.ctrl, required this.size, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible && ctrl.isCompleted) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _CollapsePainter(ctrl.value, Offset(size.width / 2, size.height * 0.42)),
        size: size,
      ),
    );
  }
}

class _CollapsePainter extends CustomPainter {
  final double p;
  final Offset center;
  _CollapsePainter(this.p, this.center);

  @override
  void paint(Canvas canvas, Size size) {
    final ep = Curves.easeInOutExpo.transform(p);
    final cs = 1 - ep * 0.5;
    final op = 1 - ep;
    final rect = Rect.fromCenter(center: center, width: 120 * cs, height: 120 * cs);
    canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF00D4FF).withOpacity(op * 0.3),
        const Color(0xFFB829DD).withOpacity(0),
      ]).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20));

    final lp = Curves.easeOutBack.transform(p);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(lp);
    _drawLogo(canvas);
    canvas.restore();

    if (p > 0.3) {
      final rp = (p - 0.3) / 0.7;
      canvas.drawCircle(center, 40 + Curves.easeOutCubic.transform(rp) * 60, Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(0.3 * (1 - rp))
        ..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  void _drawLogo(Canvas canvas) {
    // M 字形 — My minimax
    final path = Path();
    path.moveTo(-20, 14);
    path.lineTo(-20, -14);
    path.lineTo(-4, 4);
    path.lineTo(4, -4);
    path.lineTo(8, 4);
    path.lineTo(8, -14);
    path.lineTo(8, 14);
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(Offset.zero, 3.5, Paint()..color = const Color(0xFFB829DD));
  }

  @override
  bool shouldRepaint(covariant _CollapsePainter o) => true;
}

// ─── Phase 3: Shell break ───
class _ShellBreak extends StatelessWidget {
  final AnimationController ctrl;
  final Size size;
  final int phase;
  const _ShellBreak({required this.ctrl, required this.size, required this.phase});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _ShellPainter(ctrl.value, Offset(size.width / 2, size.height * 0.42), size),
        size: size,
      ),
    );
  }
}

class _ShellPainter extends CustomPainter {
  final double p;
  final Offset center;
  final Size screen;
  _ShellPainter(this.p, this.center, this.screen);

  @override
  void paint(Canvas canvas, Size size) {
    final ep = Curves.easeInOutExpo.transform(p);
    final ls = 1 + ep * 0.4;
    final ly = center.dy - ep * (center.dy - screen.height * 0.18);

    canvas.save();
    canvas.translate(center.dx, ly);
    canvas.scale(ls);
    _drawLogo(canvas);
    canvas.restore();

    if (p > 0.2) {
      final cp = (p - 0.2) / 0.8;
      final crackPaint = Paint()
        ..color = Colors.white.withOpacity(0.08 * (1 - cp))
        ..strokeWidth = 1..style = PaintingStyle.stroke;
      final rng = Random(123);
      for (int i = 0; i < 10; i++) {
        final a = (i / 10) * 2 * pi;
        final sl = 40.0;
        final el = sl + cp * 200;
        final s = Offset(center.dx + cos(a) * sl, center.dy + sin(a) * sl);
        final e = Offset(center.dx + cos(a) * el, center.dy + sin(a) * el);
        final m = Offset.lerp(s, e, 0.5)!;
        final off = Offset((rng.nextDouble() - 0.5) * 20 * cp, (rng.nextDouble() - 0.5) * 20 * cp);
        final path = Path()..moveTo(s.dx, s.dy)..quadraticBezierTo(m.dx + off.dx, m.dy + off.dy, e.dx, e.dy);
        canvas.drawPath(path, crackPaint);
      }
    }

    if (p > 0.4) {
      final up = (p - 0.4) / 0.6;
      final ue = Curves.easeOutCubic.transform(up);
      final tp = TextPainter(text: TextSpan(text: 'My minimax', style: TextStyle(
        fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: 4,
        color: Colors.white.withOpacity(ue),
      )), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout();
      tp.paint(canvas, Offset(center.dx - tp.width / 2, screen.height * 0.28 + (1 - ue) * 40));

      final sp = TextPainter(text: TextSpan(text: 'AI AGENT', style: TextStyle(
        fontSize: 11, letterSpacing: 6,
        color: const Color(0xFF00D4FF).withOpacity(ue * 0.7),
      )), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout();
      sp.paint(canvas, Offset(center.dx - sp.width / 2, screen.height * 0.28 + 36 + (1 - ue) * 40));
    }

    if (p > 0.8) {
      final fp = (p - 0.8) / 0.2;
      canvas.drawRect(Offset.zero & screen, Paint()
        ..color = Colors.white.withOpacity(sin(fp * pi) * 0.3));
    }
  }

  void _drawLogo(Canvas canvas) {
    final path = Path();
    path.moveTo(-20, 14); path.lineTo(-20, -14);
    path.lineTo(-4, 4); path.lineTo(4, -4);
    path.lineTo(8, 4); path.lineTo(8, -14);
    path.lineTo(8, 14);
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(Offset.zero, 3.5, Paint()..color = const Color(0xFFB829DD));
  }

  @override
  bool shouldRepaint(covariant _ShellPainter o) => true;
}
