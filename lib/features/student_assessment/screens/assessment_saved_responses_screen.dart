import 'package:flutter/material.dart';

import '../widgets/v4_assessment_response_review.dart';

class AssessmentSavedResponsesScreen extends StatelessWidget {
  const AssessmentSavedResponsesScreen({
    required this.itemSnapshot,
    required this.responses,
    required this.domainSummaries,
    super.key,
  });

  final List<Map<String, dynamic>> itemSnapshot;
  final List<Map<String, dynamic>> responses;
  final List<Map<String, dynamic>> domainSummaries;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your responses')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          V4AssessmentResponseReview(
            itemSnapshot: itemSnapshot,
            responses: responses,
            domainSummaries: domainSummaries,
          ),
        ],
      ),
    ),
  );
}
