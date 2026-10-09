import 'package:flutter/material.dart';
import '../models/intervention_models.dart';

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
    final status = _text('status');
    final eligible = _preview?['interventionEligible'] == true;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.onBack();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Category Review')),
        body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(domainLabel, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Category completed'),
            if (status != null) ...[
              const SizedBox(height: 16),
              Text(_statusLabel(status), style: Theme.of(context).textTheme.titleMedium),
            ],
            if (hasPreview) ...[
              _section('Summary', _text('summary')),
              _section('Focus', _text('focusInsight')),
              _section('Strength', _text('strengthInsight')),
              _section('Suggested next step', _text('suggestedAction')),
              _section('Reflection', _text('reflectionPrompt')),
              if (eligible) ...[
                const SizedBox(height: 16),
                Text('Suggested activity: ${widget.intervention?.name ?? 'wellness activity'}'),
                if (widget.onTryActivity != null) FilledButton.tonal(onPressed: widget.onTryActivity, child: const Text('Try Suggested Activity')),
              ],
            ] else ...[
              const SizedBox(height: 20),
              const Text('This category result could not be retrieved. Your answers are still saved in this assessment session.'),
              if (_error != null) const SizedBox(height: 8),
              if (_error != null) const Text('You can retry or continue without a category preview.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _retrying ? null : _retry,
                child: const Text('Retry Preview'),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: widget.onContinue, child: const Text('Continue Assessment')),
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

  Widget _section(String title, String? text) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(text),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'supported' => 'Generally supported',
    'mostlySupported' => 'Mostly supported',
    'someStrain' => 'Some strain',
    'supportMayHelp' => 'Support may be helpful',
    'insufficientResponses' => 'More responses are needed',
    _ => 'Category result available',
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
