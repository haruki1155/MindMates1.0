import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/user_repository.dart';

void main() {
  group('UserProvider', () {
    test('loads user profile by uid', () async {
      final repository = _FakeUserRepository(
        user: const UserModel(
          id: 'user_1',
          email: 'leo@example.com',
          firstName: 'Leo',
          lastName: 'Molar',
        ),
      );
      final provider = UserProvider(repository);

      await provider.loadProfile('user_1');

      expect(provider.user?.displayName, 'Leo Molar');
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('updates profile and keeps local state on success', () async {
      final repository = _FakeUserRepository(
        user: const UserModel(id: 'user_1', email: 'leo@example.com'),
      );
      final provider = UserProvider(repository);
      provider.setUser(repository.user);

      final updated = repository.user!.copyWith(firstName: 'Leonardo');
      final success = await provider.updateProfile(updated);

      expect(success, isTrue);
      expect(provider.user?.firstName, 'Leonardo');
      expect(repository.updatedUser?.firstName, 'Leonardo');
      expect(provider.isSaving, isFalse);
    });

    test(
      'missing backend profile does not clear existing local user',
      () async {
        final repository = _FakeUserRepository();
        final provider = UserProvider(repository);
        provider.setUser(
          const UserModel(
            id: 'user_1',
            email: 'leo@example.com',
            firstName: 'Leonardo',
            lastName: 'Molar',
            role: 'student',
          ),
        );

        await provider.loadProfile('user_1');

        expect(provider.user?.displayName, 'Leonardo Molar');
        expect(provider.user?.roleLabel, 'Student');
        expect(provider.isLoading, isFalse);
      },
    );

    test(
      'missing backend profile stays null when there is no local user',
      () async {
        final repository = _FakeUserRepository();
        final provider = UserProvider(repository);

        await provider.loadProfile('user_1');

        expect(provider.user, isNull);
        expect(provider.isLoading, isFalse);
      },
    );

    test('exposes error and restores local state on update failure', () async {
      final repository = _FakeUserRepository(
        user: const UserModel(id: 'user_1', email: 'leo@example.com'),
        failUpdate: true,
      );
      final provider = UserProvider(repository);
      provider.setUser(repository.user);

      final success = await provider.updateProfile(
        repository.user!.copyWith(firstName: 'Broken'),
      );

      expect(success, isFalse);
      expect(provider.user?.firstName, isNull);
      expect(provider.errorMessage, 'Unable to update profile.');
      expect(provider.isSaving, isFalse);
    });

    test('marks activity and increments local day streak', () async {
      final repository = _FakeUserRepository(
        user: const UserModel(
          id: 'user_1',
          email: 'leo@example.com',
          dayStreak: 2,
          longestStreak: 2,
        ),
      );
      final provider = UserProvider(repository)..setUser(repository.user);

      await provider.markActivity('user_1');

      expect(repository.markedActivityUid, 'user_1');
      expect(provider.user?.dayStreak, 3);
      expect(provider.user?.longestStreak, 3);
      expect(provider.user?.activeDateKeys, contains('2026-07-03'));
    });
  });

  group('StreakCalculator', () {
    test('first activity creates streak one', () {
      final update = StreakCalculator.calculate(
        occurredAt: DateTime(2026, 7, 3),
      );

      expect(update.dayStreak, 1);
      expect(update.longestStreak, 1);
      expect(update.lastActivityDateKey, '2026-07-03');
    });

    test('same-day activity does not increment', () {
      final update = StreakCalculator.calculate(
        occurredAt: DateTime(2026, 7, 3, 18),
        previousDateKey: '2026-07-03',
        currentStreak: 4,
        longestStreak: 5,
      );

      expect(update.dayStreak, 4);
      expect(update.longestStreak, 5);
    });

    test('yesterday activity increments streak', () {
      final update = StreakCalculator.calculate(
        occurredAt: DateTime(2026, 7, 3),
        previousDateKey: '2026-07-02',
        currentStreak: 4,
        longestStreak: 4,
      );

      expect(update.dayStreak, 5);
      expect(update.longestStreak, 5);
    });

    test('missed day resets streak', () {
      final update = StreakCalculator.calculate(
        occurredAt: DateTime(2026, 7, 3),
        previousDateKey: '2026-07-01',
        currentStreak: 4,
        longestStreak: 8,
      );

      expect(update.dayStreak, 1);
      expect(update.longestStreak, 8);
      expect(update.wasReset, isTrue);
    });

    test('longest streak updates only when exceeded', () {
      final update = StreakCalculator.calculate(
        occurredAt: DateTime(2026, 7, 3),
        previousDateKey: '2026-07-02',
        currentStreak: 2,
        longestStreak: 10,
      );

      expect(update.dayStreak, 3);
      expect(update.longestStreak, 10);
    });

    test('only mood check-ins count toward the streak', () {
      for (final type in UserActivityType.values) {
        expect(
          StreakCalculator.countsTowardStreak(type),
          type == UserActivityType.moodCheckIn,
          reason: type.name,
        );
      }
    });

    test('effective streak keeps today and yesterday, drops older', () {
      final now = DateTime(2026, 11, 12, 9);
      expect(
        StreakCalculator.effectiveStreak(
          storedStreak: 4,
          lastActivityDateKey: '2026-11-12',
          now: now,
        ),
        4,
      );
      expect(
        StreakCalculator.effectiveStreak(
          storedStreak: 4,
          lastActivityDateKey: '2026-11-11',
          now: now,
        ),
        4,
      );
      expect(
        StreakCalculator.effectiveStreak(
          storedStreak: 4,
          lastActivityDateKey: '2026-11-10',
          now: now,
        ),
        0,
      );
      expect(
        StreakCalculator.effectiveStreak(
          storedStreak: 4,
          lastActivityDateKey: null,
          now: now,
        ),
        0,
      );
      expect(
        StreakCalculator.effectiveStreak(
          storedStreak: 4,
          lastActivityDateKey: 'bad',
          now: now,
        ),
        0,
      );
      expect(
        StreakCalculator.effectiveStreak(
          storedStreak: -2,
          lastActivityDateKey: '2026-11-12',
          now: now,
        ),
        0,
      );
    });
  });
}

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository({this.user, this.failUpdate = false});

  UserModel? user;
  UserModel? updatedUser;
  String? markedActivityUid;
  bool failUpdate;

  @override
  Future<UserModel?> fetchUserProfile(String uid) async => user;

  @override
  Future<void> updateUserProfile(String uid, UserModel user) async {
    if (failUpdate) throw StateError('failed');
    updatedUser = user;
    this.user = user;
  }

  @override
  Future<UserModel?> markUserActivity(String uid) async {
    markedActivityUid = uid;
    user = user?.copyWith(
      dayStreak: user!.dayStreak + 1,
      longestStreak: user!.dayStreak + 1,
      lastActivityDateKey: '2026-07-03',
      lastActiveAt: DateTime(2026, 7, 3),
      activeDateKeys: ['2026-07-03'],
    );
    return user;
  }

  @override
  Future<UserModel?> recordActivity(
    String uid,
    UserActivityType type, {
    DateTime? occurredAt,
  }) {
    return markUserActivity(uid);
  }
}
