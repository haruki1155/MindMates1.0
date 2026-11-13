import 'package:flutter/material.dart';

import 'home_dashboard_widgets.dart';

const _unlitFlame = Color(0x99B8B2A6); // #B8B2A6 at 60% opacity.

/// Flame colour stops by streak day: deep red → magenta → violet → royal blue.
const List<(int, Color)> _flameStops = [
  (1, Color(0xFFC62828)),
  (7, Color(0xFFA0237A)),
  (14, Color(0xFF7B2FA8)),
  (21, Color(0xFF5B3FC4)),
  (30, Color(0xFF4169E1)),
];

/// The streak flame colour for [days]; unlit grey at 0, royal blue from 30.
Color streakFlameColor(int days) {
  if (days <= 0) return const Color(0xFFB8B2A6).withValues(alpha: .6);
  if (days >= _flameStops.last.$1) return _flameStops.last.$2;
  for (var index = 0; index < _flameStops.length - 1; index++) {
    final (fromDay, fromColor) = _flameStops[index];
    final (toDay, toColor) = _flameStops[index + 1];
    if (days == fromDay) return fromColor;
    if (days < toDay) {
      return Color.lerp(
        fromColor,
        toColor,
        (days - fromDay) / (toDay - fromDay),
      )!;
    }
  }
  return _flameStops.last.$2;
}

/// The Home/Journey streak fire, tinted by streak length with a soft glow and
/// a gentle flicker. Static when animations are disabled or the streak is 0.
class StreakFlame extends StatefulWidget {
  const StreakFlame({super.key, required this.days, this.size = 84});

  final int days;
  final double size;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame>
    with TickerProviderStateMixin {
  static const _flickerPeriod = Duration(milliseconds: 2400);

  /// Flicker loops each time the flame appears or the streak changes; the
  /// flame then rests (scale 1, steady glow) so screens can settle.
  static const _flickerLoops = 3;
  static const _colorDuration = Duration(milliseconds: 600);

  static final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.04), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.04, end: .98), weight: 1),
    TweenSequenceItem(tween: Tween(begin: .98, end: 1), weight: 1),
  ]).chain(CurveTween(curve: Curves.easeInOut));
  static final _glow = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: .30, end: .45), weight: 1),
    TweenSequenceItem(tween: Tween(begin: .45, end: .30), weight: 1),
  ]).chain(CurveTween(curve: Curves.easeInOut));

  AnimationController? _controller;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  bool get _shouldAnimate => widget.days > 0 && !_reduceMotion;

  void _syncController({bool restart = false}) {
    if (!_shouldAnimate) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    final controller = _controller;
    if (controller == null) {
      _controller = AnimationController(vsync: this, duration: _flickerPeriod)
        ..repeat(count: _flickerLoops);
    } else if (restart) {
      controller
        ..reset()
        ..repeat(count: _flickerLoops);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant StreakFlame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(restart: oldWidget.days != widget.days);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lit = widget.days > 0;
    return ExcludeSemantics(
      child: SizedBox.square(
        key: const Key('streak-flame'),
        dimension: widget.size,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: streakFlameColor(widget.days)),
          duration: _reduceMotion ? Duration.zero : _colorDuration,
          curve: Curves.easeInOut,
          builder: (context, color, _) {
            final flame = color ?? _unlitFlame;
            final controller = _controller;
            if (controller == null) {
              return _frame(flame, scale: 1, lift: 0, glow: lit ? .35 : 0);
            }
            return AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final t = controller.value;
                final scale = _scale.transform(t);
                return _frame(
                  flame,
                  scale: scale,
                  lift: scale > 1 ? 1 : 0,
                  glow: _glow.transform(t),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _frame(
    Color flame, {
    required double scale,
    required double lift,
    required double glow,
  }) {
    final size = widget.size;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        if (glow > 0)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    flame.withValues(alpha: glow),
                    flame.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        Transform.translate(
          offset: Offset(0, -lift),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(flame, Colors.white, .15)!, flame],
              ).createShader(bounds),
              child: HomeDashboardAssetImage(
                assetName: 'fire_icon.png',
                width: size * .82,
                height: size * .82,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
