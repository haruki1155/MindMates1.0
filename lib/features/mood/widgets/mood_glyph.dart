import 'dart:math' as math;
import 'package:flutter/material.dart';

class MoodGlyphPainter extends CustomPainter {
  const MoodGlyphPainter({required this.glyph, required this.accentColor});

  final MoodGlyph glyph;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (glyph == MoodGlyph.excited) {
      _drawParty(canvas, size);
      return;
    }

    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .42;
    final faceRect = Rect.fromCircle(center: center, radius: radius);
    final facePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.35, -.35),
        radius: .9,
        colors: [
          const Color(0xFFFFF3AC),
          accentColor.withValues(alpha: .7),
          const Color(0xFFFFBC3F),
        ],
        stops: const [0, .62, 1],
      ).createShader(faceRect);

    canvas.drawCircle(center, radius, facePaint);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, size.width * .018)
        ..color = const Color(0xFFFFB42E),
    );

    switch (glyph) {
      case MoodGlyph.great:
        _drawGreat(canvas, size, center, radius);
      case MoodGlyph.okay:
        _drawOkay(canvas, size, center, radius);
      case MoodGlyph.stressed:
        _drawStressed(canvas, size, center, radius);
      case MoodGlyph.sad:
        _drawSad(canvas, size, center, radius);
      case MoodGlyph.angry:
        _drawAngry(canvas, size, center, radius);
      case MoodGlyph.tired:
        _drawTired(canvas, size, center, radius);
      case MoodGlyph.excited:
        break;
    }
  }

  Paint get _ink => Paint()
    ..color = const Color(0xFF17120A)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _drawGreat(Canvas canvas, Size size, Offset center, double radius) {
    final ink = _ink..strokeWidth = size.width * .055;
    _drawHappyEyes(canvas, center, radius, ink);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .2),
        width: radius * 1.18,
        height: radius * .82,
      ),
      .08,
      math.pi - .16,
      false,
      ink,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .28),
        width: radius * .92,
        height: radius * .42,
      ),
      .08,
      math.pi - .16,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .04
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawOkay(Canvas canvas, Size size, Offset center, double radius) {
    final fill = Paint()..color = const Color(0xFF17120A);
    canvas.drawCircle(
      Offset(center.dx - radius * .34, center.dy - radius * .12),
      radius * .085,
      fill,
    );
    canvas.drawCircle(
      Offset(center.dx + radius * .34, center.dy - radius * .12),
      radius * .085,
      fill,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .17),
        width: radius * .82,
        height: radius * .52,
      ),
      .12,
      math.pi - .24,
      false,
      _ink..strokeWidth = size.width * .04,
    );
  }

  void _drawStressed(Canvas canvas, Size size, Offset center, double radius) {
    final ink = _ink..strokeWidth = size.width * .048;
    canvas.drawLine(
      Offset(center.dx - radius * .54, center.dy - radius * .48),
      Offset(center.dx - radius * .18, center.dy - radius * .34),
      ink,
    );
    canvas.drawLine(
      Offset(center.dx + radius * .54, center.dy - radius * .48),
      Offset(center.dx + radius * .18, center.dy - radius * .34),
      ink,
    );
    _drawDotEyes(canvas, center, radius, radius * .085);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .5),
        width: radius * .86,
        height: radius * .7,
      ),
      math.pi + .2,
      math.pi - .4,
      false,
      ink,
    );
  }

  void _drawSad(Canvas canvas, Size size, Offset center, double radius) {
    _drawDotEyes(canvas, center, radius, radius * .09);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .52),
        width: radius * .86,
        height: radius * .72,
      ),
      math.pi + .2,
      math.pi - .4,
      false,
      _ink..strokeWidth = size.width * .045,
    );
  }

  void _drawAngry(Canvas canvas, Size size, Offset center, double radius) {
    final ink = _ink..strokeWidth = size.width * .052;
    canvas.drawLine(
      Offset(center.dx - radius * .54, center.dy - radius * .42),
      Offset(center.dx - radius * .16, center.dy - radius * .25),
      ink,
    );
    canvas.drawLine(
      Offset(center.dx + radius * .54, center.dy - radius * .42),
      Offset(center.dx + radius * .16, center.dy - radius * .25),
      ink,
    );
    _drawDotEyes(canvas, center, radius, radius * .08);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .52),
        width: radius * .72,
        height: radius * .62,
      ),
      math.pi + .14,
      math.pi - .28,
      false,
      ink,
    );
  }

  void _drawTired(Canvas canvas, Size size, Offset center, double radius) {
    final ink = _ink..strokeWidth = size.width * .042;
    _drawClosedEyes(canvas, center, radius, ink);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .46),
        width: radius * .56,
        height: radius * .42,
      ),
      math.pi + .2,
      math.pi - .4,
      false,
      ink,
    );
    _drawZ(
      canvas,
      Offset(center.dx + radius * .68, center.dy - radius * .62),
      size.width * .18,
    );
    _drawZ(
      canvas,
      Offset(center.dx + radius * .9, center.dy - radius * .88),
      size.width * .23,
    );
  }

  void _drawParty(Canvas canvas, Size size) {
    final body = Path()
      ..moveTo(size.width * .28, size.height * .76)
      ..lineTo(size.width * .52, size.height * .18)
      ..lineTo(size.width * .72, size.height * .62)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF6FA7E8), Color(0xFFFFC24E), Color(0xFFF0808F)],
        ).createShader(Offset.zero & size),
    );
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: .72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * .39, size.height * .51),
      Offset(size.width * .58, size.height * .6),
      stripe,
    );
    canvas.drawLine(
      Offset(size.width * .45, size.height * .36),
      Offset(size.width * .62, size.height * .45),
      stripe,
    );
    for (final star in [
      Offset(size.width * .74, size.height * .22),
      Offset(size.width * .82, size.height * .42),
      Offset(size.width * .55, size.height * .1),
    ]) {
      _drawStar(canvas, star, size.width * .07, const Color(0xFFF4B844));
    }
    final confettiPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .025
      ..strokeCap = StrokeCap.round;
    for (final item in [
      (Offset(size.width * .34, size.height * .2), const Color(0xFF78B7AE)),
      (Offset(size.width * .7, size.height * .12), const Color(0xFFE88EA0)),
      (Offset(size.width * .26, size.height * .35), const Color(0xFFF6C24B)),
    ]) {
      confettiPaint.color = item.$2;
      canvas.drawLine(
        item.$1,
        item.$1 + Offset(size.width * .03, -size.height * .08),
        confettiPaint,
      );
    }
  }

  void _drawHappyEyes(Canvas canvas, Offset center, double radius, Paint ink) {
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx - radius * .34, center.dy - radius * .18),
        width: radius * .3,
        height: radius * .22,
      ),
      math.pi,
      math.pi,
      false,
      ink,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx + radius * .34, center.dy - radius * .18),
        width: radius * .3,
        height: radius * .22,
      ),
      math.pi,
      math.pi,
      false,
      ink,
    );
  }

  void _drawClosedEyes(Canvas canvas, Offset center, double radius, Paint ink) {
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx - radius * .32, center.dy - radius * .18),
        width: radius * .34,
        height: radius * .18,
      ),
      0,
      math.pi,
      false,
      ink,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx + radius * .32, center.dy - radius * .18),
        width: radius * .34,
        height: radius * .18,
      ),
      0,
      math.pi,
      false,
      ink,
    );
  }

  void _drawDotEyes(
    Canvas canvas,
    Offset center,
    double radius,
    double dotSize,
  ) {
    final fill = Paint()..color = const Color(0xFF17120A);
    canvas.drawCircle(
      Offset(center.dx - radius * .3, center.dy - radius * .08),
      dotSize,
      fill,
    );
    canvas.drawCircle(
      Offset(center.dx + radius * .3, center.dy - radius * .08),
      dotSize,
      fill,
    );
  }

  void _drawZ(Canvas canvas, Offset topLeft, double size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Z',
        style: TextStyle(
          color: const Color(0xFF9D8CC7),
          fontSize: size,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, topLeft);
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + radius * .18,
        center.dy - radius * .18,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + radius * .18,
        center.dy + radius * .18,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - radius * .18,
        center.dy + radius * .18,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - radius * .18,
        center.dy - radius * .18,
        center.dx,
        center.dy - radius,
      );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant MoodGlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.accentColor != accentColor;
  }
}

enum MoodGlyph { great, okay, stressed, sad, angry, tired, excited }

/// The same native mood artwork used by the picker and personal timeline.
class MoodGlyphIcon extends StatelessWidget {
  const MoodGlyphIcon({super.key, required this.label, this.size = 36});
  final String? label;
  final double size;
  @override
  Widget build(BuildContext context) {
    final glyph = MoodGlyph.values
        .where((g) => g.name == label?.toLowerCase())
        .firstOrNull;
    final color = switch (glyph) {
      MoodGlyph.great => const Color(0xFF78A94E),
      MoodGlyph.okay => const Color(0xFF5E95BC),
      MoodGlyph.stressed => const Color(0xFF8F76C2),
      MoodGlyph.sad => const Color(0xFFC89F3A),
      MoodGlyph.angry => const Color(0xFFE3704D),
      MoodGlyph.tired => const Color(0xFF8072A8),
      _ => const Color(0xFFD99B20),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .18),
        ),
        child: glyph == null
            ? Icon(Icons.mood, size: size * .7)
            : CustomPaint(
                painter: MoodGlyphPainter(glyph: glyph, accentColor: color),
              ),
      ),
    );
  }
}
