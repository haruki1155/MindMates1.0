import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/providers/reminder_preferences_provider.dart';
import 'package:mind_mates/repositories/reminder_preferences_repository.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';
import 'package:mind_mates/features/settings/models/reminder_preferences.dart';

void main() {
  group('ReminderPreferences', () {
    test('defaults keep appointment reminders on and self-care reminders off', () {
      const preferences = ReminderPreferences();

      expect(preferences.appointment24HourEnabled, isTrue);
      expect(preferences.appointment1HourEnabled, isTrue);
      expect(preferences.moodDailyEnabled, isFalse);
      expect(preferences.breathingDailyEnabled, isFalse);
    });

    test('parses and serializes the saved time and independent timestamps', () {
      final moodUpdatedAt = DateTime(2026, 11, 28, 10);
      final breathingUpdatedAt = DateTime(2026, 11, 27, 20);
      final updatedAt = DateTime(2026, 11, 28, 11);
      final preferences = ReminderPreferences.fromJson({
        'appointment24HourEnabled': false,
        'appointment1HourEnabled': true,
        'moodDailyEnabled': true,
        'moodDailyTime': '20:15',
        'moodDailyUpdatedAt': Timestamp.fromDate(moodUpdatedAt),
        'breathingDailyEnabled': false,
        'breathingDailyTime': '21:00',
        'breathingDailyUpdatedAt': Timestamp.fromDate(breathingUpdatedAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      });

      expect(preferences.appointment24HourEnabled, isFalse);
      expect(preferences.appointment1HourEnabled, isTrue);
      expect(preferences.moodDailyEnabled, isTrue);
      expect(preferences.moodDailyTime, '20:15');
      expect(preferences.moodDailyUpdatedAt, moodUpdatedAt);
      expect(preferences.breathingDailyEnabled, isFalse);
      expect(preferences.breathingDailyTime, '21:00');
      expect(preferences.breathingDailyUpdatedAt, breathingUpdatedAt);
      expect(preferences.updatedAt, updatedAt);
      expect(preferences.toJson()['moodDailyTime'], '20:15');
      expect(preferences.toJson()['breathingDailyTime'], '21:00');
    });

    test('accepts only 24-hour HH:mm reminder times', () {
      expect(ReminderPreferences.isValidTime('00:00'), isTrue);
      expect(ReminderPreferences.isValidTime('23:59'), isTrue);
      expect(ReminderPreferences.isValidTime('24:00'), isFalse);
      expect(ReminderPreferences.isValidTime('8:30'), isFalse);
      expect(ReminderPreferences.isValidTime('08:60'), isFalse);
    });
  });

  group('ReminderPreferencesRepository', () {
    test('loads defaults when the account has no preference document', () async {
      final service = _MemoryFirestoreService();
      final repository = ReminderPreferencesRepository(firestoreService: service);

      final preferences = await repository.load('user_1');

      expect(preferences.appointment24HourEnabled, isTrue);
      expect(preferences.appointment1HourEnabled, isTrue);
      expect(preferences.moodDailyEnabled, isFalse);
      expect(preferences.breathingDailyEnabled, isFalse);
    });

    test('first save creates the complete document with server timestamps', () async {
      final service = _MemoryFirestoreService();
      final repository = ReminderPreferencesRepository(firestoreService: service);

      await repository.save('user_1', const ReminderPreferences());

      expect(service.lastSetCollection, 'reminder_preferences');
      expect(service.lastSetDocumentId, 'user_1');
      expect(
        service.lastSetData!.keys.toSet(),
        containsAll({
          'appointment24HourEnabled',
          'appointment1HourEnabled',
          'moodDailyEnabled',
          'moodDailyTime',
          'moodDailyUpdatedAt',
          'breathingDailyEnabled',
          'breathingDailyTime',
          'breathingDailyUpdatedAt',
          'updatedAt',
        }),
      );
      expect(service.lastSetData!['moodDailyUpdatedAt'], isA<FieldValue>());
      expect(service.lastSetData!['breathingDailyUpdatedAt'], isA<FieldValue>());
      expect(service.lastSetData!['updatedAt'], isA<FieldValue>());
    });

    test('appointment changes do not rewrite self-care schedule timestamps', () async {
      final service = _MemoryFirestoreService()
        ..documents['user_1'] = _savedDocument();
      final repository = ReminderPreferencesRepository(firestoreService: service);

      await repository.save(
        'user_1',
        const ReminderPreferences(appointment24HourEnabled: false),
      );

      expect(
        service.lastUpdateData!.keys.toSet(),
        {'appointment24HourEnabled', 'updatedAt'},
      );
    });

    test('changing Mood updates only the Mood schedule timestamp', () async {
      final service = _MemoryFirestoreService()
        ..documents['user_1'] = _savedDocument();
      final repository = ReminderPreferencesRepository(firestoreService: service);

      await repository.save(
        'user_1',
        const ReminderPreferences(moodDailyEnabled: true),
      );

      expect(
        service.lastUpdateData!.keys.toSet(),
        {'moodDailyEnabled', 'moodDailyUpdatedAt', 'updatedAt'},
      );
      expect(service.lastUpdateData!['moodDailyUpdatedAt'], isA<FieldValue>());
    });
  });

  test('provider clears the previous account value before loading another user', () async {
    final repository = _MemoryReminderPreferencesRepository({
      'user_1': const ReminderPreferences(moodDailyEnabled: true),
      'user_2': const ReminderPreferences(breathingDailyEnabled: true),
    });
    final provider = ReminderPreferencesProvider(repository);

    await provider.load('user_1');
    expect(provider.preferences?.moodDailyEnabled, isTrue);
    await provider.load('user_2');

    expect(provider.userId, 'user_2');
    expect(provider.preferences?.moodDailyEnabled, isFalse);
    expect(provider.preferences?.breathingDailyEnabled, isTrue);
  });

  test('provider saves the new account preferences', () async {
    final repository = _MemoryReminderPreferencesRepository({
      'user_1': const ReminderPreferences(),
    });
    final provider = ReminderPreferencesProvider(repository);
    await provider.load('user_1');

    await provider.save(
      'user_1',
      const ReminderPreferences(moodDailyEnabled: true),
    );

    expect(repository.savedUserId, 'user_1');
    expect(provider.preferences?.moodDailyEnabled, isTrue);
    expect(provider.isSaving, isFalse);
  });

  test('provider clears old preferences and reports a load error on user switch', () async {
    final repository = _MemoryReminderPreferencesRepository({
      'user_1': const ReminderPreferences(moodDailyEnabled: true),
    })..failureUserId = 'user_2';
    final provider = ReminderPreferencesProvider(repository);
    await provider.load('user_1');

    await provider.load('user_2');

    expect(provider.preferences, isNull);
    expect(provider.error, isNotNull);
  });
}

Map<String, dynamic> _savedDocument() => {
  'appointment24HourEnabled': true,
  'appointment1HourEnabled': true,
  'moodDailyEnabled': false,
  'moodDailyTime': '20:00',
  'moodDailyUpdatedAt': Timestamp.fromDate(DateTime(2026, 11, 25)),
  'breathingDailyEnabled': false,
  'breathingDailyTime': '21:00',
  'breathingDailyUpdatedAt': Timestamp.fromDate(DateTime(2026, 11, 26)),
  'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 27)),
};

class _MemoryFirestoreService extends FirestoreService {
  final Map<String, Map<String, dynamic>> documents = {};
  String? lastSetCollection;
  String? lastSetDocumentId;
  Map<String, dynamic>? lastSetData;
  Map<String, dynamic>? lastUpdateData;

  @override
  Future<Map<String, dynamic>?> getDocument(String collection, String documentId) async =>
      documents[documentId];

  @override
  Future<void> setDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    lastSetCollection = collection;
    lastSetDocumentId = documentId;
    lastSetData = Map<String, dynamic>.of(data);
    documents[documentId] = Map<String, dynamic>.of(data);
  }

  @override
  Future<void> updateDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    lastUpdateData = Map<String, dynamic>.of(data);
    documents[documentId] = {...documents[documentId]!, ...data};
  }
}

class _MemoryReminderPreferencesRepository extends ReminderPreferencesRepository {
  _MemoryReminderPreferencesRepository(this.values)
    : super(firestoreService: _MemoryFirestoreService());

  final Map<String, ReminderPreferences> values;
  String? failureUserId;
  String? savedUserId;

  @override
  Future<ReminderPreferences> load(String userId) async {
    if (userId == failureUserId) throw StateError('load failed');
    return values[userId] ?? const ReminderPreferences();
  }

  @override
  Future<void> save(String userId, ReminderPreferences preferences) async {
    savedUserId = userId;
    values[userId] = preferences;
  }
}
