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
    final eligible = _preview?['interventionEligible'] == true;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.onBack();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Suggested activity')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                domainLabel,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('You have completed this part of your assessment.'),
              if (hasPreview) ...[
                if (eligible) ...[
                  const SizedBox(height: 16),
                  Text(
                    'A short ${widget.intervention?.name ?? 'wellness'} activity is available if you would like a pause before continuing.',
                  ),
                  const SizedBox(height: 12),
                  if (widget.onTryActivity != null)
                    FilledButton.tonal(
                      onPressed: widget.onTryActivity,
                      child: const Text('Try Activity'),
                    ),
                ],
              ] else ...[
                const SizedBox(height: 20),
                const Text(
                  'This category result could not be retrieved. Your answers are still saved in this assessment session.',
                ),
                if (_error != null) const SizedBox(height: 8),
                if (_error != null)
                  const Text(
                    'You can retry or continue without a category preview.',
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _retrying ? null : _retry,
                  child: const Text('Retry Preview'),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
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
