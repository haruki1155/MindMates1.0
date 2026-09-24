import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/assessment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';
import '../../quick_assessment/widgets/quick_assessment_widgets.dart';
import '../../counseling/screens/pacc_counseling_screen.dart';
import '../models/student_assessment_models.dart';
import '../models/assessment_interpretation_models.dart';

class StudentAssessmentCompleteScreen extends StatefulWidget {
  const StudentAssessmentCompleteScreen({super.key});

  @override
  State<StudentAssessmentCompleteScreen> createState() =>
      _StudentAssessmentCompleteScreenState();
}

class _StudentAssessmentCompleteScreenState
    extends State<StudentAssessmentCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _backgroundController;
  bool _requestedSave = false;
  bool _appointmentPromptRequested = false;
  bool _resultUnlocked = false;
  Future<Map<String, Object>?>? _v4SaveFuture;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AssessmentProvider>(
      builder: (context, provider, _) {
        if (provider.isStudentAssessmentV4) {
          return _buildV4Completion(provider);
        }
        final result = provider.studentResult;
        if (result == null) {
          return Scaffold(
            backgroundColor: QuickAssessmentPalette.background,
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(
                  context,
                ).pushReplacementNamed(RouteNames.studentAssessment),
                child: const Text('Start Assessment'),
              ),
            ),
          );
        }

        _saveResultIfNeeded(provider);
        _requestAppointmentDecision(result);

        if (!_resultUnlocked) {
          return const Scaffold(
            backgroundColor: QuickAssessmentPalette.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: QuickAssessmentPalette.background,
          body: SafeArea(
            child: Stack(
              children: [
                _ResultBackground(animation: _backgroundController),
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _Hero(result: result)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 22),
                      sliver: SliverList.list(
                        children: [
                          _AnimatedResultSection(
                            delay: 0,
                            child: _SummaryCards(result: result),
                          ),
                          const SizedBox(height: 12),
                          _AnimatedResultSection(
                            delay: 50,
                            child: _CategoryBars(result: result),
                          ),
                          const SizedBox(height: 12),
                          _AnimatedResultSection(
                            delay: 110,
                            child: _PilotFeedbackCard(
                              onSelected:
                                  provider.saveAssessmentClarityFeedback,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _AnimatedResultSection(
                            delay: 130,
                            child: _PaccCard(),
                          ),
                          const SizedBox(height: 12),
                          const _AnimatedResultSection(
                            delay: 170,
                            child: _ReferencesCard(),
                          ),
                          const SizedBox(height: 12),
                          _AnimatedResultSection(
                            delay: 210,
                            child: _ImportantCard(
                              disclaimer: result.disclaimer,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _AnimatedResultSection(
                            delay: 250,
                            child: _ResultActions(
                              onTalkPressed: () {
                                Navigator.of(
                                  context,
                                ).pushNamed(RouteNames.mindAid);
                              },
                              onContinuePressed: () {
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  RouteNames.home,
                                  (route) => false,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildV4Completion(AssessmentProvider provider) {
    final saveFuture = _v4SaveFuture ??= _saveV4Result(provider);
    return FutureBuilder<Map<String, Object>?>(
      future: saveFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: QuickAssessmentPalette.background,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparing your well-being profile…'),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            backgroundColor: QuickAssessmentPalette.background,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Your profile could not be saved yet. Your answers were not treated as a result.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => setState(() => _v4SaveFuture = null),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return _StudentV4ProfileView(payload: snapshot.data!);
      },
    );
  }

  Future<Map<String, Object>?> _saveV4Result(
    AssessmentProvider provider,
  ) async {
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) {
      throw StateError('A signed-in user is required to save this profile.');
    }
    final payload = await provider.saveStudentAssessmentForUser(userId);
    if (payload == null) return null;
    if (!mounted) return payload;
    await context.read<UserProvider>().markFullAssessment(userId);
    if (mounted) await _reportProviderOrNull()?.refreshWeeklyReport(userId);
    return payload;
  }

  void _saveResultIfNeeded(AssessmentProvider provider) {
    if (_requestedSave || provider.studentResult == null) return;
    _requestedSave = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final userId = _currentUserId();
      if (userId == null || userId.isEmpty) return;

      try {
        final payload = await provider.saveStudentAssessmentForUser(userId);
        if (payload == null) return;
        if (!mounted) return;
        await context.read<UserProvider>().markFullAssessment(userId);
        if (!mounted) return;
        await _reportProviderOrNull()?.refreshWeeklyReport(userId);
      } catch (error) {
        debugPrint('Student assessment sync failed: $error');
      }
    });
  }

  void _requestAppointmentDecision(StudentAssessmentResult result) {
    if (_appointmentPromptRequested) return;
    _appointmentPromptRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final wantsAppointment = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.calendar_month_outlined, size: 34),
          title: const Text('Set an appointment?'),
          content: const Text(
            'Do you want to set an appointment with PACC to discuss your well-being result?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _resultUnlocked = true);
      if (wantsAppointment == true) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PaccCounselingScreen(
              startBooking: true,
              initialConcern: result.interpretation.userSummary,
            ),
          ),
        );
      }
    });
  }

  ReportProvider? _reportProviderOrNull() {
    try {
      return context.read<ReportProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  String? _currentUserId() {
    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.userId ?? authProvider.hydrateCurrentUser();
      if (userId != null && userId.isNotEmpty) return userId;
    } on ProviderNotFoundException {
      // Tests and preview surfaces may provide only UserProvider.
    }

    try {
      return context.read<UserProvider>().user?.id;
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _StudentV4ProfileView extends StatelessWidget {
  const _StudentV4ProfileView({required this.payload});

  final Map<String, Object> payload;

  @override
  Widget build(BuildContext context) {
    final result = _map(payload['result']);
    final interpretation = _map(payload['interpretation']);
    final quality = _map(result['responseQuality']);
    final domains = _maps(result['domainResults']);
    final focus = _strings(interpretation['focusInsights']);
    final strengths = _strings(interpretation['strengthInsights']);
    final actions = _strings(interpretation['suggestedActions']);
    final profileStatus = _v4ProfileLabel(result['profileStatus']?.toString());
    return Scaffold(
      backgroundColor: QuickAssessmentPalette.background,
      appBar: AppBar(title: const Text('Your well-being profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              profileStatus,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              interpretation['studentSummary']?.toString() ??
                  'This is a snapshot of the past 7 days based on the areas you answered.',
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 16),
            _V4InfoCard(
              title: 'Response confidence',
              child: Text(
                '${quality['answered'] ?? 0} of ${quality['presented'] ?? 50} answered · ${_v4ConfidenceLabel(quality['confidence']?.toString())}. Skipped questions are excluded.',
              ),
            ),
            if (strengths.isNotEmpty) ...[
              const SizedBox(height: 12),
              _V4InfoCard(
                title: 'Your strengths',
                child: _V4Bullets(values: strengths),
              ),
            ],
            if (focus.isNotEmpty) ...[
              const SizedBox(height: 12),
              _V4InfoCard(
                title: 'Areas to explore',
                child: _V4Bullets(values: focus),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Well-being areas',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...domains.map(
              (domain) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _V4InfoCard(
                  title:
                      domain['domainId']?.toString().replaceAllMapped(
                        RegExp(r'([a-z])([A-Z])'),
                        (match) => '${match.group(1)} ${match.group(2)}',
                      ) ??
                      'Well-being area',
                  trailing: _v4DomainLabel(domain['status']?.toString()),
                  child: Text(
                    '${domain['answeredCount'] ?? 0}/${domain['presentedCount'] ?? 10} answered. ${domain['isScorable'] == true ? 'This area is available for reflection.' : 'More responses are needed for this area.'}',
                  ),
                ),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              _V4InfoCard(
                title: 'Practical next steps',
                child: _V4Bullets(values: actions),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              interpretation['disclaimer']?.toString() ??
                  'This is a 7-day reflection profile, not a diagnosis.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: _ResultPalette.secondaryText,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const PaccCounselingScreen(startBooking: true),
                ),
              ),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Book a PACC appointment'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(RouteNames.home, (route) => false),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _V4InfoCard extends StatelessWidget {
  const _V4InfoCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (trailing != null) _V4StatusChip(label: trailing!),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _V4StatusChip extends StatelessWidget {
  const _V4StatusChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: QuickAssessmentPalette.selectedFill,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _V4Bullets extends StatelessWidget {
  const _V4Bullets({required this.values});
  final List<String> values;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: values
        .map(
          (value) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• $value', style: const TextStyle(height: 1.4)),
          ),
        )
        .toList(),
  );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const <Map<String, dynamic>>[];
List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : const <String>[];
String _v4ProfileLabel(String? value) => switch (value) {
  'generallySupported' => 'Well-being appears generally supported.',
  'mostlySupported' => 'Mostly supported, with an area to explore.',
  'someAreasNeedAttention' => 'Some areas may benefit from attention.',
  'supportMayHelp' => 'Support may be helpful right now.',
  _ => 'More responses are needed for a complete profile.',
};
String _v4DomainLabel(String? value) => switch (value) {
  'supported' => 'Supported at present',
  'mostlySupported' => 'Mostly supported',
  'someStrain' => 'Some strain indicated',
  'supportMayHelp' => 'Support may be helpful',
  _ => 'More responses needed',
};
String _v4ConfidenceLabel(String? value) => switch (value) {
  'high' => 'High confidence',
  'usableWithCaution' => 'Usable with caution',
  _ => 'Limited responses',
};

class _Hero extends StatelessWidget {
  const _Hero({required this.result});

  final StudentAssessmentResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 470,
      decoration: const BoxDecoration(color: QuickAssessmentPalette.primary),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 350,
            left: -80,
            right: -80,
            child: Container(
              height: 190,
              decoration: const BoxDecoration(
                color: QuickAssessmentPalette.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(160)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeroBadge(),
                const SizedBox(height: 14),
                const Text(
                  'Assessment Complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ResultPalette.text,
                    fontSize: 26,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Here are your personalized insights',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ResultPalette.secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                _ScoreGauge(status: result.responsePatternLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: QuickAssessmentPalette.shadow,
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.favorite_rounded,
        color: Color(0xFFFF5B69),
        size: 28,
      ),
    );
  }
}

class _ScoreGauge extends StatelessWidget {
  const _ScoreGauge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 286,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: QuickAssessmentPalette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: QuickAssessmentPalette.softBorder),
        boxShadow: [
          BoxShadow(
            color: QuickAssessmentPalette.shadow,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFFE0A500),
            size: 32,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your Well-being Profile',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ResultPalette.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ResultPalette.text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'A reflection on current strengths and areas you may want to explore. This is not a diagnosis.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ResultPalette.mutedText,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBackground extends StatelessWidget {
  const _ResultBackground({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    const bubbles = [
      _ResultBubble(-18, 128, 23, QuickAssessmentPalette.grayBubble),
      _ResultBubble(138, 408, 34, QuickAssessmentPalette.softBubble),
      _ResultBubble(316, 708, 24, QuickAssessmentPalette.primary),
      _ResultBubble(16, 930, 34, QuickAssessmentPalette.softBubble),
      _ResultBubble(304, 1138, 42, QuickAssessmentPalette.primary),
      _ResultBubble(54, 1440, 28, QuickAssessmentPalette.grayBubble),
      _ResultBubble(318, 1660, 34, QuickAssessmentPalette.softBubble),
    ];

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            return Stack(
              children: [
                const BubbleCluster(top: -34, left: -30),
                for (var index = 0; index < bubbles.length; index += 1)
                  Positioned(
                    left:
                        bubbles[index].left +
                        (index.isEven ? 1 : -1) * animation.value * 6,
                    top:
                        bubbles[index].top +
                        (index.isEven ? -1 : 1) * animation.value * 8,
                    child: Container(
                      width: bubbles[index].size,
                      height: bubbles[index].size,
                      decoration: BoxDecoration(
                        color: bubbles[index].color.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResultBubble {
  const _ResultBubble(this.left, this.top, this.size, this.color);

  final double left;
  final double top;
  final double size;
  final Color color;
}

class _AnimatedResultSection extends StatelessWidget {
  const _AnimatedResultSection({required this.child, required this.delay});

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + delay),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        final progress = ((value * (280 + delay) - delay) / 280).clamp(
          0.0,
          1.0,
        );

        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - progress)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.result});

  final StudentAssessmentResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfoCard(
          title: 'Your well-being at a glance',
          body: result.interpretation.userSummary,
        ),
        const SizedBox(height: 10),
        _InfoCard(
          title: 'Response confidence',
          body:
              '${result.interpretation.responseQuality.confidence.label} '
              '(${result.interpretation.responseQuality.completionPercent.round()}% answered). '
              'This summary uses only the questions you answered.',
        ),
        const SizedBox(height: 10),
        _InfoCard(
          title: 'Support options',
          body:
              '${result.interpretation.supportPriority.label}. Everyone experiences challenges differently. Counseling is available as an optional, confidential conversation if you would like additional guidance.',
        ),
        const SizedBox(height: 10),
        _InsightsCard(result: result),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _ResultText.title),
          const SizedBox(height: 11),
          Text(body, style: _ResultText.body),
        ],
      ),
    );
  }
}

class _PilotFeedbackCard extends StatefulWidget {
  const _PilotFeedbackCard({required this.onSelected});

  final Future<void> Function(String clarity) onSelected;

  @override
  State<_PilotFeedbackCard> createState() => _PilotFeedbackCardState();
}

class _PilotFeedbackCardState extends State<_PilotFeedbackCard> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Help improve this university pilot', style: _ResultText.title),
          const SizedBox(height: 8),
          Text(
            _submitted
                ? 'Thank you. Your anonymous clarity rating was recorded.'
                : 'Were your category results easy to understand? No written response or user ID is stored.',
            style: _ResultText.body,
          ),
          if (!_submitted) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                _feedbackButton('Clear', 'clear'),
                _feedbackButton('Partly clear', 'partlyClear'),
                _feedbackButton('Unclear', 'unclear'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _feedbackButton(String label, String value) {
    return OutlinedButton(
      onPressed: () async {
        try {
          await widget.onSelected(value);
          if (mounted) setState(() => _submitted = true);
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to save feedback right now.')),
          );
        }
      },
      child: Text(label),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.result});

  final StudentAssessmentResult result;

  @override
  Widget build(BuildContext context) {
    final interpretation = result.interpretation;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your personal insights', style: _ResultText.title),
          const SizedBox(height: 12),
          _InsightGroup(
            icon: Icons.star_rounded,
            title: 'Your strengths',
            emptyText:
                'Your completed responses still provide a useful starting point for reflection.',
            items: interpretation.strengthInsights,
          ),
          const SizedBox(height: 14),
          _InsightGroup(
            icon: Icons.explore_outlined,
            title: 'Areas to explore',
            emptyText:
                'No specific area stood out as needing additional attention right now.',
            items: interpretation.focusInsights,
          ),
          if (interpretation.suggestedActions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _InsightGroup(
              icon: Icons.lightbulb_outline_rounded,
              title: 'Options you can try',
              emptyText: '',
              items: interpretation.suggestedActions,
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightGroup extends StatelessWidget {
  const _InsightGroup({
    required this.icon,
    required this.title,
    required this.emptyText,
    required this.items,
  });

  final IconData icon;
  final String title;
  final String emptyText;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF9A6B00)),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ],
      ),
      const SizedBox(height: 7),
      if (items.isEmpty && emptyText.isNotEmpty)
        Text(emptyText, style: _ResultText.body),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: _ResultText.body),
              Expanded(child: Text(item, style: _ResultText.body)),
            ],
          ),
        ),
    ],
  );
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.result});

  final StudentAssessmentResult result;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      backgroundColor: const Color(0xFFFFFAEC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your well-being areas', style: _ResultText.title),
          const SizedBox(height: 5),
          const Text(
            'Each area summarizes ten answers. Statuses describe response patterns, not personal labels.',
            style: _ResultText.body,
          ),
          const SizedBox(height: 16),
          for (final entry in result.interpretation.domainResults.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: _ScoreBar(domain: entry.$2, staggerIndex: entry.$1),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.domain, required this.staggerIndex});

  final AssessmentDomainResult domain;
  final int staggerIndex;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: 430 + (staggerIndex * 45));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutQuart,
      builder: (context, value, _) {
        return Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: QuickAssessmentPalette.softBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      domain.domain,
                      style: const TextStyle(
                        color: _ResultPalette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    domain.isScorable
                        ? domain.responsePatternLabel
                        : 'Insufficient responses',
                    style: const TextStyle(
                      color: _ResultPalette.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                domain.interpretation,
                style: const TextStyle(
                  color: _ResultPalette.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Option to try: ${domain.suggestedAction}',
                style: const TextStyle(
                  color: _ResultPalette.secondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${domain.answeredCount} of ${domain.presentedCount} questions answered',
                style: const TextStyle(
                  color: _ResultPalette.mutedText,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PaccCard extends StatelessWidget {
  const _PaccCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QuickAssessmentPalette.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: QuickAssessmentPalette.shadow,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.support_agent_rounded, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAACC Counseling Office',
                  style: TextStyle(
                    color: _ResultPalette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Urdaneta City University - 1st Floor, Lai Building\n+63 912 345 6789\npacc@ucu.edu.ph',
                  style: TextStyle(
                    color: _ResultPalette.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferencesCard extends StatelessWidget {
  const _ReferencesCard();

  static const sections = {
    'Academic Stress and Student Well-Being': [
      'World Health Organization. Mental health and COVID-19: Early evidence of the pandemic impact.',
      'American Psychological Association. Psychological assessment and evaluation.',
      'Tan, J., Cruz, M., & Reyes, P. Needs assessment of mental health challenges among university students in the Philippines.',
      'American School Counselor Association. ASCA National Model.',
    ],
    'Financial Stress': [
      'American Psychological Association. Stress in America Report.',
      'World Health Organization. Mental health and well-being.',
      'Department of Health Philippines. Philippine Mental Health Program.',
    ],
    'Sleep and Rest': [
      'World Health Organization. Mental health: Strengthening our response.',
      'National Sleep Foundation. Sleep Health Recommendations.',
      'American Psychological Association. Sleep and mental health.',
    ],
    'Emotional Well-Being': [
      'World Health Organization. Mental health: Strengthening our response.',
      'Philippine Mental Health Association. Mental Health Promotion and Wellness.',
      'Psychological Association of the Philippines. Mental health promotion and ethical psychological practice.',
    ],
    'Social Support and Help-Seeking': [
      'Philippine Mental Health Association. Mental health promotion and wellness.',
      'World Health Organization. Mental health and community support.',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: QuickAssessmentPalette.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: QuickAssessmentPalette.softBorder),
        boxShadow: [
          BoxShadow(
            color: QuickAssessmentPalette.shadow.withValues(alpha: 0.11),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: QuickAssessmentPalette.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Text(
              'References',
              style: TextStyle(
                color: _ResultPalette.text,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          for (final section in sections.entries)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: QuickAssessmentPalette.primary.withValues(
                  alpha: 0.08,
                ),
              ),
              child: Material(
                color: QuickAssessmentPalette.card,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 13),
                  childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
                  iconColor: _ResultPalette.text,
                  collapsedIconColor: _ResultPalette.secondaryText,
                  title: Text(section.key, style: _ResultText.title),
                  children: [
                    for (final item in section.value) ...[
                      _ReferenceItem(text: item),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReferenceItem extends StatelessWidget {
  const _ReferenceItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: QuickAssessmentPalette.softBorder),
      ),
      child: Text(text, style: _ResultText.body),
    );
  }
}

class _ImportantCard extends StatelessWidget {
  const _ImportantCard({required this.disclaimer});

  final String disclaimer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: QuickAssessmentPalette.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Important:', style: _ResultText.title),
          const SizedBox(height: 8),
          Text(disclaimer, style: _ResultText.body),
        ],
      ),
    );
  }
}

class _ResultActions extends StatelessWidget {
  const _ResultActions({
    required this.onTalkPressed,
    required this.onContinuePressed,
  });

  final VoidCallback onTalkPressed;
  final VoidCallback onContinuePressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: onTalkPressed,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
            label: const Text('Talk with MindAid about this'),
            style: ElevatedButton.styleFrom(
              backgroundColor: QuickAssessmentPalette.text,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 5,
              shadowColor: QuickAssessmentPalette.shadow,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: OutlinedButton(
            onPressed: onContinuePressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: QuickAssessmentPalette.primary,
              foregroundColor: QuickAssessmentPalette.text,
              side: BorderSide(
                color: QuickAssessmentPalette.text.withValues(alpha: 0.18),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: const Text('Continue to MindMate'),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.backgroundColor = QuickAssessmentPalette.card,
  });

  final Widget child;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: QuickAssessmentPalette.softBorder),
        boxShadow: [
          BoxShadow(
            color: QuickAssessmentPalette.shadow.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ResultText {
  const _ResultText._();

  static const title = TextStyle(
    color: _ResultPalette.text,
    fontSize: 14,
    fontWeight: FontWeight.w900,
    height: 1.2,
  );
  static const body = TextStyle(
    color: _ResultPalette.secondaryText,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.42,
  );
}

class _ResultPalette {
  const _ResultPalette._();

  static const text = QuickAssessmentPalette.text;
  static const secondaryText = QuickAssessmentPalette.secondaryText;
  static const mutedText = QuickAssessmentPalette.mutedText;
}
