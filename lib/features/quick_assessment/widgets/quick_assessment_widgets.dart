import 'package:flutter/material.dart';

import '../models/quick_assessment_models.dart';

class QuickAssessmentPalette {
  const QuickAssessmentPalette._();

  static const background = Color(0xFFFFFCF7);
  static const primary = Color(0xFFFFB900);
  static const primaryPressed = Color(0xFFE3A100);
  static const selectedFill = Color(0xFFFFE6A3);
  static const cream = Color(0xFFFFF5DA);
  static const optionFill = Color(0xFFFFFBF1);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE1A900);
  static const softBorder = Color(0xFFF0CF74);
  static const text = Color(0xFF17130A);
  static const secondaryText = Color(0xFF3E3520);
  static const mutedText = Color(0xFF665D49);
  static const subtleText = Color(0xFF7A705C);
  static const grayBubble = Color(0xFFE5E1D7);
  static const softBubble = Color(0xFFFFF0C7);
  static const shadow = Color(0x26000000);
}

class QuickAssessmentScaffold extends StatelessWidget {
  const QuickAssessmentScaffold({
    super.key,
    required this.child,
    this.topClusters = const [
      BubbleCluster(top: 70, left: -15),
      BubbleCluster(top: 88, right: -22, mirrored: true),
    ],
    this.showBottomBubble = true,
  });

  final Widget child;
  final List<BubbleCluster> topClusters;
  final bool showBottomBubble;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: QuickAssessmentPalette.background,
      body: SafeArea(
        child: Stack(
          children: [
            for (final cluster in topClusters) cluster,
            if (showBottomBubble)
              const Positioned(
                right: 68,
                bottom: 92,
                child: _SoftBubble(
                  size: 37,
                  color: QuickAssessmentPalette.softBubble,
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class BubbleCluster extends StatelessWidget {
  const BubbleCluster({
    super.key,
    this.top,
    this.left,
    this.right,
    this.mirrored = false,
  });

  final double? top;
  final double? left;
  final double? right;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final bubbles = [
      _BubbleSpec(0, 0, 28, QuickAssessmentPalette.primary, 0.42),
      _BubbleSpec(23, 11, 22, QuickAssessmentPalette.primary, 0.38),
      _BubbleSpec(35, -20, 30, QuickAssessmentPalette.grayBubble, 0.54),
      _BubbleSpec(52, 21, 30, QuickAssessmentPalette.primary, 0.34),
      _BubbleSpec(78, -10, 16, QuickAssessmentPalette.primary, 0.36),
      _BubbleSpec(88, 24, 20, QuickAssessmentPalette.primary, 0.42),
      _BubbleSpec(62, -34, 18, QuickAssessmentPalette.primary, 0.34),
    ];

    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(mirrored ? -1.0 : 1.0, 1.0, 1.0),
            child: SizedBox(
              width: 112,
              height: 130,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final bubble in bubbles)
                    Positioned(
                      top: bubble.top,
                      left: bubble.left + 34,
                      child: _SoftBubble(
                        size: bubble.size,
                        color: bubble.color.withValues(alpha: bubble.opacity),
                        hasShadow:
                            bubble.color == QuickAssessmentPalette.grayBubble,
                      ),
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

class QuickProgressHeader extends StatelessWidget {
  const QuickProgressHeader({
    super.key,
    required this.step,
    required this.label,
    required this.total,
  });

  final int step;
  final String label;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fill = step.clamp(1, total) / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: QuickAssessmentPalette.softBorder,
                  width: 0.8,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    widthFactor: fill,
                    heightFactor: 1,
                    child: Container(color: QuickAssessmentPalette.primary),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: QuickAssessmentPalette.text,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class QuickNextButton extends StatelessWidget {
  const QuickNextButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 216,
      height: 38,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: QuickAssessmentPalette.primary,
          foregroundColor: QuickAssessmentPalette.text,
          elevation: 5,
          shadowColor: QuickAssessmentPalette.shadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Next'),
                  SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, size: 19),
                ],
              ),
      ),
    );
  }
}

IconData quickAssessmentRoleIcon(AssessmentRole role) => switch (role) {
  AssessmentRole.student => Icons.school_rounded,
  AssessmentRole.faculty => Icons.co_present_rounded,
  AssessmentRole.staff => Icons.badge_rounded,
};

class QuickRoleIcon extends StatelessWidget {
  const QuickRoleIcon({super.key, required this.role, this.size = 28});

  final AssessmentRole role;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFFFD246),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        quickAssessmentRoleIcon(role),
        size: size,
        color: QuickAssessmentPalette.text,
        semanticLabel: role.label,
      ),
    );
  }
}

class _SoftBubble extends StatelessWidget {
  const _SoftBubble({
    required this.size,
    required this.color,
    this.hasShadow = false,
  });

  final double size;
  final Color color;
  final bool hasShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: QuickAssessmentPalette.shadow,
                  blurRadius: 7,
                  offset: const Offset(4, 4),
                ),
              ]
            : null,
      ),
    );
  }
}

class _BubbleSpec {
  const _BubbleSpec(this.top, this.left, this.size, this.color, this.opacity);

  final double top;
  final double left;
  final double size;
  final Color color;
  final double opacity;
}
