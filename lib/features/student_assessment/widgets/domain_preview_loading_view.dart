import 'package:flutter/material.dart';

import 'assessment_presentation.dart';

/// Read-only presentation for an in-flight, server-authoritative V4 preview.
class DomainPreviewLoadingView extends StatelessWidget {
  const DomainPreviewLoadingView({
    required this.domainLabel,
    required this.domainNumber,
    required this.domainCount,
    super.key,
  });

  final String domainLabel;
  final int domainNumber;
  final int domainCount;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            label:
                'Reviewing $domainLabel, domain $domainNumber of $domainCount',
            child: AssessmentSurfaceCard(
              color: AssessmentPresentation.softAccent(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    'Reviewing $domainLabel',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AssessmentStatusPill(
                    label: 'Domain $domainNumber of $domainCount',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We are reviewing your answers before showing the next step.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AssessmentPresentation.muted(context),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
