import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../database/firestore_collections.dart';
import '../features/mood/config/mood_v2_feature_flag.dart';
import '../features/mood/domain/mood_v2_analytics.dart';
import '../services/firebase/firebase_callable_router.dart';

/// Disabled adapter for the later Mood V2 rollout. Existing Mood screens and
/// legacy daily writes do not instantiate or call this repository yet.
class MoodV2Repository {
  MoodV2Repository({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  }) : _providedFunctions = functions,
       _providedFirestore = firestore;

  final FirebaseFunctions? _providedFunctions;
  final FirebaseFirestore? _providedFirestore;

  FirebaseFunctions get _functions =>
      _providedFunctions ?? FirebaseFunctions.instance;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  Future<MoodV2Event> create({
    required int level,
    required String clientRequestId,
    String? label,
    String? note,
    String entryMethod = 'manual',
    bool expressionAssistUsed = false,
    bool expressionSuggestionAccepted = false,
    String? expressionModelVersion,
  }) async {
    if (!MoodV2FeatureFlag.enabled) {
      throw StateError('Mood V2 persistence is not enabled.');
    }
    final result = await _functions.routedCallable('createMoodEntry').call({
      'level': level,
      'label': label ?? '',
      'note': note ?? '',
      'entryMethod': entryMethod,
      'expressionAssistUsed': expressionAssistUsed,
      'expressionSuggestionAccepted': expressionSuggestionAccepted,
      'expressionModelVersion': ?expressionModelVersion,
      'clientRequestId': clientRequestId,
    });
    return _fromCallable(Map<String, dynamic>.from(result.data as Map));
  }

  Future<List<NormalizedMoodEvent>> fetchHistory(String userId, {int limit = 50}) async {
    if (!MoodV2FeatureFlag.enabled) return const [];
    final query = await _firestore
        .collection(FirestoreCollections.moodEntries)
        .where('userId', isEqualTo: userId)
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .get();
    return query.docs.map((doc) => _fromDocument(doc)).toList(growable: false);
  }

  MoodV2Event _fromCallable(Map<String, dynamic> data) => MoodV2Event(
    id: data['entryId']?.toString() ?? '',
    userId: data['userId']?.toString() ?? '',
    level: data['level'] as int,
    dateKey: data['dateKey']?.toString() ?? '',
    occurredAt: DateTime.parse(data['occurredAt']?.toString() ?? ''),
    clientRequestId: data['clientRequestId']?.toString() ?? '',
    label: data['label']?.toString(),
    note: data['note']?.toString(),
    entryMethod: data['entryMethod']?.toString(),
  );

  NormalizedMoodEvent _fromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return MoodV2Event(
      id: doc.id,
      userId: data['userId']?.toString() ?? '',
      level: data['level'] as int,
      dateKey: data['dateKey']?.toString() ?? '',
      occurredAt: (data['occurredAt'] as Timestamp).toDate(),
      clientRequestId: data['clientRequestId']?.toString() ?? '',
      label: data['label']?.toString(),
      note: data['note']?.toString(),
      entryMethod: data['entryMethod']?.toString(),
    ).toNormalized();
  }
}
