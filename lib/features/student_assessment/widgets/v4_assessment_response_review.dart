import 'package:flutter/material.dart';

/// Displays a saved V4 response record without consulting a live question set.
class V4AssessmentResponseReview extends StatelessWidget {
  const V4AssessmentResponseReview({
    super.key,
    required this.itemSnapshot,
    required this.responses,
    required this.domainSummaries,
  });

  final List<Map<String, dynamic>> itemSnapshot;
  final List<Map<String, dynamic>> responses;
  final List<Map<String, dynamic>> domainSummaries;

  @override
  Widget build(BuildContext context) {
    final responseByItemId = <String, Map<String, dynamic>>{};
    for (final response in responses) {
      final itemId = response['itemId'];
      if (itemId is String && itemId.isNotEmpty) {
        responseByItemId.putIfAbsent(itemId, () => response);
      }
    }

    final groups = domainSummaries
        .map(
          (domain) =>
              _SavedDomain.fromMap(domain, itemSnapshot, responseByItemId),
        )
        .whereType<_SavedDomain>()
        .toList(growable: false);

    if (groups.isEmpty) {
      return const _ReviewEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              label: 'Assessment responses for ${group.label}',
              child: ExpansionTile(
                key: ValueKey('v4-response-group-${group.id}'),
                title: Text(
                  group.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                children: [
                  if (group.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        'No saved responses are available for this area.',
                      ),
                    )
                  else
                    for (final item in group.items)
                      _SavedResponseItem(item: item),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ReviewEmptyState extends StatelessWidget {
  const _ReviewEmptyState();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Saved assessment responses are unavailable for this result.',
      ),
    ),
  );
}

class _SavedResponseItem extends StatelessWidget {
  const _SavedResponseItem({required this.item});

  final _SavedResponse item;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('v4-response-${item.itemId}'),
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${item.displayOrder}. ${item.questionText}',
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 4),
        Text(
          item.answerLabel,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _SavedDomain {
  const _SavedDomain({
    required this.id,
    required this.label,
    required this.items,
  });

  final String id;
  final String label;
  final List<_SavedResponse> items;

  static _SavedDomain? fromMap(
    Map<String, dynamic> domain,
    List<Map<String, dynamic>> itemSnapshot,
    Map<String, Map<String, dynamic>> responseByItemId,
  ) {
    final id = domain['domainId'];
    if (id is! String || id.isEmpty) return null;
    final label = domain['domainLabel'];
    final items =
        itemSnapshot
            .where((item) => item['domainId'] == id)
            .map((item) => _SavedResponse.fromSnapshot(item, responseByItemId))
            .whereType<_SavedResponse>()
            .toList()
          ..sort(
            (left, right) => left.displayOrder.compareTo(right.displayOrder),
          );
    return _SavedDomain(
      id: id,
      label: label is String && label.trim().isNotEmpty
          ? label
          : 'Well-being area',
      items: items,
    );
  }
}

class _SavedResponse {
  const _SavedResponse({
    required this.itemId,
    required this.displayOrder,
    required this.questionText,
    required this.answerLabel,
  });

  final String itemId;
  final int displayOrder;
  final String questionText;
  final String answerLabel;

  static _SavedResponse? fromSnapshot(
    Map<String, dynamic> snapshot,
    Map<String, Map<String, dynamic>> responseByItemId,
  ) {
    final itemId = snapshot['itemId'];
    if (itemId is! String || itemId.isEmpty) return null;
    final text = snapshot['text'];
    final displayOrder = _displayOrder(snapshot['displayOrder']);
    return _SavedResponse(
      itemId: itemId,
      displayOrder: displayOrder,
      questionText: text is String && text.trim().isNotEmpty
          ? text
          : 'Question unavailable',
      answerLabel: _answerLabel(responseByItemId[itemId]),
    );
  }
}

int _displayOrder(Object? value) => switch (value) {
  int order => order,
  num order => order.toInt(),
  String order => int.tryParse(order) ?? 999999,
  _ => 999999,
};

String _answerLabel(Map<String, dynamic>? response) {
  if (response == null || response['skipped'] == true) return 'Not answered';
  return switch (response['responseCode']) {
    'stronglyDisagree' => 'Strongly disagree',
    'disagree' => 'Disagree',
    'agree' => 'Agree',
    'stronglyAgree' => 'Strongly agree',
    _ => 'Response unavailable',
  };
}
