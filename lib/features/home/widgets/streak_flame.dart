import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../domain/home_streak_source.dart';

/// Multi-layer volumetric colour palette for [StreakFlame].
@immutable
class StreakFlamePalette {
  const StreakFlamePalette({
    required this.outer,
    required this.mid,
    required this.core,
  });

  final Color outer;
  final Color mid;
  final Color core;

  static StreakFlamePalette lerp(
    StreakFlamePalette a,
    StreakFlamePalette b,
    double t,
  ) => StreakFlamePalette(
    outer: Color.lerp(a.outer, b.outer, t)!,
    mid: Color.lerp(a.mid, b.mid, t)!,
    core: Color.lerp(a.core, b.core, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is StreakFlamePalette &&
      other.outer == outer &&
      other.mid == mid &&
      other.core == core;

  @override
  int get hashCode => Object.hash(outer, mid, core);
}

const _unlitPalette = StreakFlamePalette(
  outer: Color(0x99B8B2A6), // #B8B2A6 at 60% opacity.
  mid: Color(0xAABDB8AE),
  core: Color(0xCCD6D1C9),
);

/// Volumetric flame stops by streak day:
/// crimson ember -> rose magenta -> amethyst -> cosmic indigo -> royal sapphire.
const List<(int, StreakFlamePalette)> _paletteStops = [
  (
    1,
    StreakFlamePalette(
      outer: Color(0xFFC62828),
      mid: Color(0xFFFA6B1F),
      core: Color(0xFFFFF0B8),
    ),
  ),
  (
    7,
    StreakFlamePalette(
      outer: Color(0xFFA0237A),
      mid: Color(0xFFF2478F),
      core: Color(0xFFFFE0F0),
    ),
  ),
  (
    14,
    StreakFlamePalette(
      outer: Color(0xFF7B2FA8),
      mid: Color(0xFFBD57F5),
      core: Color(0xFFF2E0FF),
    ),
  ),
  (
    21,
    StreakFlamePalette(
      outer: Color(0xFF5B3FC4),
      mid: Color(0xFF757AFA),
      core: Color(0xFFE6F0FF),
    ),
  ),
  (
    30,
    StreakFlamePalette(
      outer: Color(0xFF4169E1),
      mid: Color(0xFF3DB8FA),
      core: Color(0xFFE0FAFF),
    ),
  ),
];

/// Returns the 3-layer flame palette for [days]; unlit ash at 0, royal sapphire
/// from day 30 onward.
StreakFlamePalette streakFlamePalette(int days) {
  if (days <= 0) return _unlitPalette;
  if (days >= _paletteStops.last.$1) return _paletteStops.last.$2;
  for (var index = 0; index < _paletteStops.length - 1; index++) {
    final (fromDay, fromPalette) = _paletteStops[index];
    final (toDay, toPalette) = _paletteStops[index + 1];
    if (days == fromDay) return fromPalette;
    if (days < toDay) {
      return StreakFlamePalette.lerp(
        fromPalette,
        toPalette,
        (days - fromDay) / (toDay - fromDay),
      );
    }
  }
  return _paletteStops.last.$2;
}

/// Primary outer flame colour for [days]; unlit grey at 0, royal blue from 30.
Color streakFlameColor(int days) => streakFlamePalette(days).outer;

/// Smooth fluid-fire streak animation powered by a native GLSL fragment shader
/// (`shaders/streak_flame.frag`) with a matched multi-layer vector fallback.
///
/// Static when [days] is 0 or when animations are disabled via [MediaQuery].
class StreakFlame extends StatefulWidget {
  const StreakFlame({
    super.key,
    required this.days,
    this.size = 84,
    this.state,
  });

  final int days;
  final double size;
  final HomeStreakState? state;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame>
    with TickerProviderStateMixin {
  static const _shaderAsset = 'shaders/streak_flame.frag';
  static const _transitionDuration = Duration(milliseconds: 600);
  static Future<ui.FragmentProgram?>? _programFuture;

  static Future<ui.FragmentProgram?> _loadProgram() {
    return _programFuture ??= ui.FragmentProgram.fromAsset(_shaderAsset)
        .then<ui.FragmentProgram?>((program) => program)
        .catchError((Object _, StackTrace _) => null);
  }

  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: _transitionDuration,
    value: 1,
  );
  late final Listenable _repaint = Listenable.merge([_time, _transition]);

  Ticker? _ticker;
  Duration? _lastTick;
  ui.FragmentShader? _shader;

  late StreakFlamePalette _fromPalette = streakFlamePalette(widget.days);
  late StreakFlamePalette _toPalette = _fromPalette;
  late double _fromIntensity = _targetIntensity;
  late double _toIntensity = _targetIntensity;

  HomeStreakState get _effectiveState {
    if (widget.days <= 0) return HomeStreakState.notStarted;
    return widget.state ?? HomeStreakState.doneToday;
  }

  double get _targetIntensity => switch (_effectiveState) {
    HomeStreakState.notStarted => 0.0,
    HomeStreakState.activeNotToday => 0.68,
    HomeStreakState.doneToday => 1.0,
    HomeStreakState.milestone => 1.25,
  };

  double get _timeSpeed => switch (_effectiveState) {
    HomeStreakState.notStarted => 0.0,
    HomeStreakState.activeNotToday => 0.72,
    HomeStreakState.doneToday => 1.0,
    HomeStreakState.milestone => 1.15,
  };

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  bool get _shouldAnimate => widget.days > 0 && !_reduceMotion;

  StreakFlamePalette get _currentPalette => StreakFlamePalette.lerp(
    _fromPalette,
    _toPalette,
    Curves.easeInOut.transform(_transition.value),
  );

  double get _currentIntensity => ui.lerpDouble(
    _fromIntensity,
    _toIntensity,
    Curves.easeInOut.transform(_transition.value),
  )!;

  @override
  void initState() {
    super.initState();
    _initShader();
  }

  Future<void> _initShader() async {
    final program = await _loadProgram();
    if (!mounted || program == null) return;
    setState(() {
      _shader?.dispose();
      _shader = program.fragmentShader();
    });
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) return;
    final dt = (elapsed - previous).inMicroseconds / 1000000.0;
    if (dt <= 0) return;
    // Clamp dt so resuming from background does not jump the fluid simulation.
    _time.value += math.min(dt, 0.05) * _timeSpeed;
  }

  void _syncTicker() {
    if (!_shouldAnimate) {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
      _lastTick = null;
      return;
    }
    if (_ticker == null) {
      _lastTick = null;
      _ticker = createTicker(_onTick)..start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
    if (_reduceMotion && _transition.isAnimating) {
      _transition.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant StreakFlame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPalette = streakFlamePalette(widget.days);
    final nextIntensity = _targetIntensity;
    if (nextPalette != _toPalette || nextIntensity != _toIntensity) {
      _fromPalette = _currentPalette;
      _toPalette = nextPalette;
      _fromIntensity = _currentIntensity;
      _toIntensity = nextIntensity;
      if (_reduceMotion) {
        _transition.value = 1;
      } else {
        _transition
          ..value = 0
          ..forward();
      }
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _transition.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lit = widget.days > 0;
    final shader = _shader;
    return ExcludeSemantics(
      child: SizedBox.square(
        key: const Key('streak-flame'),
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: shader != null
                ? _ShaderFlamePainter(
                    shader: shader,
                    repaint: _repaint,
                    readTime: () => _reduceMotion ? 0.0 : _time.value,
                    readPalette: () => _currentPalette,
                    readIntensity: () => _currentIntensity,
                    lit: lit,
                  )
                : _VectorFlamePainter(
                    repaint: _repaint,
                    readTime: () => _reduceMotion ? 0.0 : _time.value,
                    readPalette: () => _currentPalette,
                    readIntensity: () => _currentIntensity,
                    lit: lit,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ShaderFlamePainter extends CustomPainter {
  _ShaderFlamePainter({
    required this.shader,
    required Listenable repaint,
    required this.readTime,
    required this.readPalette,
    required this.readIntensity,
    required this.lit,
  }) : super(repaint: repaint);

  final ui.FragmentShader shader;
  final ValueGetter<double> readTime;
  final ValueGetter<StreakFlamePalette> readPalette;
  final ValueGetter<double> readIntensity;
  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = readPalette();
    final intensity = readIntensity();

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, readTime())
      ..setFloat(3, lit ? 1.0 : 0.0)
      ..setFloat(4, intensity)
      ..setFloat(5, palette.outer.r)
      ..setFloat(6, palette.outer.g)
      ..setFloat(7, palette.outer.b)
      ..setFloat(8, palette.mid.r)
      ..setFloat(9, palette.mid.g)
      ..setFloat(10, palette.mid.b)
      ..setFloat(11, palette.core.r)
      ..setFloat(12, palette.core.g)
      ..setFloat(13, palette.core.b);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _ShaderFlamePainter oldDelegate) =>
      oldDelegate.shader != shader || oldDelegate.lit != lit;
}

/// Matched 3-layer organic vector fallback painted while the GLSL shader loads
/// or in environments without runtime fragment shaders.
class _VectorFlamePainter extends CustomPainter {
  _VectorFlamePainter({
    required Listenable repaint,
    required this.readTime,
    required this.readPalette,
    required this.readIntensity,
    required this.lit,
  }) : super(repaint: repaint);

  final ValueGetter<double> readTime;
  final ValueGetter<StreakFlamePalette> readPalette;
  final ValueGetter<double> readIntensity;
  final bool lit;

  Path _flamePath(
    double cx,
    double baseY,
    double w,
    double h,
    double swayTop,
    double swayMidL,
    double swayMidR,
    double tipCurl,
  ) => Path()
    ..moveTo(cx, baseY)
    ..cubicTo(
      cx + w * (0.68 + swayMidR),
      baseY - h * 0.04,
      cx + w * (0.58 + swayMidR * 0.7),
      baseY - h * 0.56,
      cx + swayTop + tipCurl,
      baseY - h,
    )
    ..cubicTo(
      cx - w * (0.48 - swayMidL * 0.8),
      baseY - h * 0.58,
      cx - w * (0.68 - swayMidL),
      baseY - h * 0.04,
      cx,
      baseY,
    )
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final palette = readPalette();
    final cx = size.width * 0.5;
    final baseY = size.height * 0.88;
    final unit = size.shortestSide / 192.0;

    if (!lit) {
      final outerPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, baseY - 122 * unit),
          Offset(cx, baseY),
          [palette.outer, palette.mid],
        );
      canvas.drawPath(
        _flamePath(cx, baseY, 72 * unit, 122 * unit, 0, 0, 0, 0),
        outerPaint,
      );
      canvas.drawPath(
        _flamePath(cx, baseY - 8 * unit, 36 * unit, 62 * unit, 0, 0, 0, 0),
        Paint()..color = palette.core,
      );
      return;
    }

    final t = readTime();
    final energy = readIntensity().clamp(0.5, 1.4);

    // Ambient radial glow.
    final glowRadius = 82 * unit;
    final glowCenter = Offset(cx, baseY - 54 * unit);
    final glowAlpha = ((0.28 + 0.06 * math.sin(t * 4.4)) * energy).clamp(
      0.0,
      0.55,
    );
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          glowCenter,
          glowRadius,
          [
            palette.mid.withValues(alpha: glowAlpha),
            palette.outer.withValues(alpha: 0),
          ],
        ),
    );

    // Side tongues.
    final leftH = (66 + 12 * math.sin(t * 4.7 + 0.8)) * unit;
    final leftSway = (-12 + 7 * math.sin(t * 5.3)) * unit;
    canvas.drawPath(
      _flamePath(
        cx - 22 * unit,
        baseY - 12 * unit,
        30 * unit,
        leftH,
        leftSway,
        0.1,
        -0.05,
        -4 * unit,
      ),
      Paint()..color = palette.outer.withValues(alpha: 0.92),
    );

    final rightH = (60 + 11 * math.cos(t * 4.2 + 1.5)) * unit;
    final rightSway = (11 + 6 * math.cos(t * 5.0)) * unit;
    canvas.drawPath(
      _flamePath(
        cx + 22 * unit,
        baseY - 14 * unit,
        28 * unit,
        rightH,
        rightSway,
        -0.05,
        0.1,
        4 * unit,
      ),
      Paint()..color = palette.outer.withValues(alpha: 0.92),
    );

    // Outer flame.
    final h1 = (132 + 10 * math.sin(t * 3.8) + 4 * math.sin(t * 7.1)) * unit;
    final sway1 = (10 * math.sin(t * 2.9) + 4 * math.cos(t * 5.7)) * unit;
    final curl1 = 7 * math.sin(t * 4.3 + 1.1) * unit;
    canvas.drawPath(
      _flamePath(
        cx,
        baseY,
        76 * unit,
        h1,
        sway1,
        0.08 * math.sin(t * 3.5),
        0.08 * math.cos(t * 3.9),
        curl1,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, baseY - h1),
          Offset(cx, baseY),
          [palette.mid, palette.outer, palette.outer],
          const [0.0, 0.55, 1.0],
        ),
    );

    // Mid flame.
    final h2 = (96 + 8 * math.sin(t * 4.5 + 1.4)) * unit;
    final sway2 = 7 * math.sin(t * 3.4 + 0.9) * unit;
    canvas.drawPath(
      _flamePath(
        cx,
        baseY - 4 * unit,
        52 * unit,
        h2,
        sway2,
        0.06 * math.cos(t * 4.1),
        0.06 * math.sin(t * 4.6),
        -3 * math.sin(t * 5.2) * unit,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, baseY - h2),
          Offset(cx, baseY - 6 * unit),
          [palette.core, palette.mid, palette.outer],
          const [0.0, 0.55, 1.0],
        ),
    );

    // Inner incandescent core.
    final h3 = (56 + 6 * math.cos(t * 5.1 + 0.5)) * unit;
    final sway3 = 4 * math.sin(t * 4.2 + 2.1) * unit;
    canvas.drawPath(
      _flamePath(cx, baseY - 8 * unit, 29 * unit, h3, sway3, 0.04, 0.04, 0),
      Paint()..color = palette.core.withValues(alpha: 0.96),
    );

    // Rising ember droplets.
    final sparkCount = energy > 1.1 ? 4 : 3;
    for (var i = 0; i < sparkCount; i++) {
      final prog = (t * (0.45 + i * 0.14) + i * 0.29) % 1.0;
      final sx = cx + math.sin(prog * 7 + i * 2.2 + t) * (18 + i * 6) * unit;
      final sy = baseY - (58 + prog * 96) * unit;
      final r = ((1 - prog) * 4.5 + 1.4) * unit;
      final alpha = math.sin(prog * math.pi).clamp(0.0, 1.0);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(sx, sy), width: r * 1.4, height: r * 2.4),
        Paint()..color = (i == 1 ? palette.core : palette.mid).withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VectorFlamePainter oldDelegate) =>
      oldDelegate.lit != lit;
}
