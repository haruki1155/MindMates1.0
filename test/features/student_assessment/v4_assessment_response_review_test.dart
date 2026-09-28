import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/widgets/v4_assessment_response_review.dart';

void main() {
  testWidgets('renders five saved domain groups in saved domain order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: V4AssessmentResponseReview(
              itemSnapshot: _reversedSnapshot(),
              responses: _responses(),
              domainSummaries: _domainSummaries(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ExpansionTile), findsNWidgets(5));
    expect(find.text('Area 1'), findsOneWidget);
    expect(find.text('Area 5'), findsOneWidget);
    expect(find.text('Historical saved question 1.'), findsNothing);

    await tester.tap(find.text('Area 1'));
    await tester.pumpAndSettle();

    expect(find.text('1. Historical saved question 1.'), findsOneWidget);
    expect(find.text('10. Historical saved question 10.'), findsOneWidget);
    expect(find.text('Agree'), findsNWidgets(7));
  });

  testWidgets('uses saved fallbacks and wraps long historical text safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 320, child: _ReviewFixture()),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Area 1'));
    await tester.pumpAndSettle();

    expect(find.text('Not answered', skipOffstage: false), findsNWidgets(2));
    expect(
      find.text('Response unavailable', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Question unavailable', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'This is a very long saved historical question intended to verify that the response review wraps naturally on a narrow phone without overflowing the screen.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _ReviewFixture extends StatelessWidget {
  const _ReviewFixture();

  @override
  Widget build(BuildContext context) => V4AssessmentResponseReview(
    itemSnapshot: _reversedSnapshot(),
    responses: _responses(),
    domainSummaries: _domainSummaries(),
  );
}

List<Map<String, dynamic>> _domainSummaries() => [
  for (var domainIndex = 1; domainIndex <= 5; domainIndex += 1)
    {'domainId': 'domain_$domainIndex', 'domainLabel': 'Area $domainIndex'},
];

List<Map<String, dynamic>> _reversedSnapshot() {
  final items = [
    for (var index = 1; index <= 50; index += 1)
      {
        'itemId': 'item_$index',
        'domainId': 'domain_${((index - 1) ~/ 10) + 1}',
        'displayOrder': index,
        'text': _textFor(index),
      },
  ];
  return items.reversed.toList();
}

String _textFor(int index) {
  if (index == 5) return '';
  if (index == 6) {
    return 'This is a very long saved historical question intended to verify that the response review wraps naturally on a narrow phone without overflowing the screen.';
  }
  return 'Historical saved question $index.';
}

List<Map<String, dynamic>> _responses() => [
  for (var index = 1; index <= 50; index += 1)
    if (index != 3)
      {
        'itemId': 'item_$index',
        'responseCode': index == 2
            ? 'stronglyDisagree'
            : index == 4
            ? 'unexpected'
            : 'agree',
        'skipped': index == 2,
      },
];
