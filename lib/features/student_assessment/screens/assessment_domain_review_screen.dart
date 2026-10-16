import 'package:flutter/material.dart';

import '../models/intervention_models.dart';
import '../widgets/assessment_presentation.dart';

/// Renders one server-authoritative V4 category preview. It intentionally does
/// not interpret answers or calculate a local category status.
class AssessmentDomainReviewScreen extends StatefulWidget {
  const AssessmentDomainReviewScreen({
    required this.preview,
    required this.onContinue,
    required this.onRetry,
    required this.onBack,
    this.intervention,
    this.onTryActivity,
    this.previewAfterRetry,
    this.errorAfterRetry,
    this.error,
    super.key,
  });

  final Map<String, Object>? preview;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final InterventionType? intervention;
  final VoidCallback? onTryActivity;
  final Future<void> Function() onRetry;
  final Map<String, Object>? Function()? previewAfterRetry;
  final Object? Function()? errorAfterRetry;
  final Object? error;

  @override
  State<AssessmentDomainReviewScreen> createState() =>
      _AssessmentDomainReviewScreenState();
}

class _AssessmentDomainReviewScreenState
    extends State<AssessmentDomainReviewScreen> {
  late Map<String, Object>? _preview;
  Object? _error;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
    _error = widget.error;
  }

  @override
  Widget build(BuildContext context) {
    final hasPreview = _preview != null;
    final domainLabel = _text('domainLabel') ?? 'Category review';
    final eligible = _preview?['interventionEligible'] == true;
    final status = _text('status');
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.onBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('Suggested activity'),
          backgroundColor: AssessmentPresentation.softAccent(context),
          foregroundColor: AssessmentPresentation.onSoftAccent(context),
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AssessmentSurfaceCard(
                color: AssessmentPresentation.softAccent(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status != null) ...[
                      AssessmentStatusPill(label: _statusLabel(status)),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      domainLabel,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You have completed this part of your assessment.',
                    ),
                    if (hasPreview && eligible) ...[
                      const SizedBox(height: 18),
                      Text(
                        'A short ${widget.intervention?.name ?? 'wellness'} activity is available if you would like a pause before continuing.',
                        style: const TextStyle(height: 1.45),
                      ),
                      if (widget.onTryActivity != null) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          style: AssessmentPresentation.filledButtonStyle(
                            context,
                          ),
                          onPressed: widget.onTryActivity,
                          child: const Text('Try Activity'),
                        ),
                      ],
                    ],
                    if (!hasPreview) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'This category result could not be retrieved. Your answers are still saved in this assessment session.',
                        style: TextStyle(height: 1.45),
                      ),
                      if (_error != null) const SizedBox(height: 8),
                      if (_error != null)
                        const Text(
                          'You can retry or continue without a category preview.',
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        style: AssessmentPresentation.outlinedButtonStyle(
                          context,
                        ),
                        onPressed: _retrying ? null : _retry,
                        child: const Text('Retry Preview'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: AssessmentPresentation.filledButtonStyle(context),
                onPressed: widget.onContinue,
                child: const Text('Not now, continue assessment'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _text(String key) {
    final value = _preview?[key];
    if (value is! String || value.trim().isEmpty) return null;
    return value;
  }

  String _statusLabel(String status) => switch (status) {
    'supportMayHelp' => 'Support may be helpful',
    'someStrain' => 'Some strain indicated',
    'mostlySupported' => 'Mostly supported',
    'supported' => 'Supported at present',
    _ => 'Preview ready',
  };

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await widget.onRetry();
    if (!mounted) return;
    setState(() {
      _preview = widget.previewAfterRetry?.call() ?? widget.preview;
      _error = widget.errorAfterRetry?.call() ?? widget.error;
      _retrying = false;
    });
  }
}
