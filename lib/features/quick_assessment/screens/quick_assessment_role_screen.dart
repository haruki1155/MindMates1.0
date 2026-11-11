import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/assessment_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';
import '../models/quick_assessment_models.dart';
import '../widgets/quick_assessment_widgets.dart';

class QuickAssessmentRoleScreen extends StatelessWidget {
  const QuickAssessmentRoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      final user = context.watch<UserProvider>().user;
      if (user?.quickAssessmentCompleted == true) {
        return const _CompletedAssessmentRedirect();
      }
      final storedRole = user?.assessmentRole;
      if (storedRole != null) return _StoredRoleRedirect(role: storedRole);
    } on ProviderNotFoundException {
      // Standalone previews can render without authentication state.
    }

    return QuickAssessmentScaffold(
      showBottomBubble: false,
      topClusters: const [
        BubbleCluster(top: -6, left: -22),
        BubbleCluster(top: -12, right: -28, mirrored: true),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              108,
              24,
              26 + MediaQuery.paddingOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 134,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: const _RoleContent(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StoredRoleRedirect extends StatefulWidget {
  const _StoredRoleRedirect({required this.role});

  final AssessmentRole role;

  @override
  State<_StoredRoleRedirect> createState() => _StoredRoleRedirectState();
}

class _StoredRoleRedirectState extends State<_StoredRoleRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AssessmentProvider>().beginQuickAssessment(
        role: widget.role,
        name: _profileName(context),
      );
      Navigator.of(
        context,
      ).pushReplacementNamed(RouteNames.quickAssessmentQuestions);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _CompletedAssessmentRedirect extends StatefulWidget {
  const _CompletedAssessmentRedirect();

  @override
  State<_CompletedAssessmentRedirect> createState() =>
      _CompletedAssessmentRedirectState();
}

class _CompletedAssessmentRedirectState
    extends State<_CompletedAssessmentRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(RouteNames.home, (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _RoleContent extends StatelessWidget {
  const _RoleContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Adaptive Mental Health\nAssessment',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: QuickAssessmentPalette.text,
            fontSize: 27,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'First, please select your role within the institution to\nget personalized questions',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: QuickAssessmentPalette.text,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 28),
        _RoleCard(
          role: AssessmentRole.student,
          onTap: () => _selectRole(context, AssessmentRole.student),
        ),
        const SizedBox(height: 16),
        _RoleCard(
          role: AssessmentRole.faculty,
          onTap: () => _selectRole(context, AssessmentRole.faculty),
        ),
        const SizedBox(height: 16),
        _RoleCard(
          role: AssessmentRole.staff,
          onTap: () => _selectRole(context, AssessmentRole.staff),
        ),
        const SizedBox(height: 48),
        const _LikertLegend(),
        const SizedBox(height: 28),
        const Text(
          '🔒 Your responses are completely confidential and will only be used\nto provide personalized mental health insights',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: QuickAssessmentPalette.mutedText,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  void _selectRole(BuildContext context, AssessmentRole role) {
    context.read<AssessmentProvider>().beginQuickAssessment(
      role: role,
      name: _profileName(context),
    );
    Navigator.of(context).pushNamed(RouteNames.quickAssessmentQuestions);
  }
}

/// The signed-in user's name from their profile; empty in standalone
/// previews without a [UserProvider].
String _profileName(BuildContext context) {
  try {
    return context.read<UserProvider>().user?.displayName ?? '';
  } on ProviderNotFoundException {
    return '';
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.onTap});

  final AssessmentRole role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFBEC),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 98),
          padding: const EdgeInsets.fromLTRB(15, 16, 8, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: QuickAssessmentPalette.primary),
          ),
          child: Row(
            children: [
              QuickRoleIcon(role: role),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.label,
                      style: const TextStyle(
                        color: QuickAssessmentPalette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      role.description,
                      style: const TextStyle(
                        color: QuickAssessmentPalette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: QuickAssessmentPalette.text,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikertLegend extends StatelessWidget {
  const _LikertLegend();

  static const _items = [
    (1, 'Strongly Disagree', Color(0xFFFF1010)),
    (2, 'Disagree', Color(0xFFFF7A00)),
    (3, 'Neutral', Color(0xFFFFC400)),
    (4, 'Agree', Color(0xFFA6FF00)),
    (5, 'Strongly Agree', Color(0xFF00D326)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2C24A), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '5-Point Likert Scale',
            style: TextStyle(
              color: QuickAssessmentPalette.text,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final item in _items)
                _LegendItem(number: item.$1, label: item.$2, color: item.$3),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.number,
    required this.label,
    required this.color,
  });

  final int number;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: const TextStyle(
                color: QuickAssessmentPalette.text,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: QuickAssessmentPalette.text,
                fontSize: 7.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
