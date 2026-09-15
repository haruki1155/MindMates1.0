import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_notification_model.dart';
import '../repositories/notification_repository.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider(this._repository);
  final NotificationRepository _repository;
  StreamSubscription<List<AppNotificationModel>>? _subscription;
  List<AppNotificationModel> _notifications = const [];
  String? _userId;
  bool _loading = false;
  String? _error;

  List<AppNotificationModel> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((item) => !item.isRead).length;
  bool get isLoading => _loading;
  String? get errorMessage => _error;

  Future<void> loadForUser(String userId) async {
    if (_userId == userId && _subscription != null) return;
    _userId = userId;
    _loading = true;
    _error = null;
    notifyListeners();
    await _subscription?.cancel();
    _subscription = _repository
        .watchNotifications(userId)
        .listen(
          (items) {
            if (_userId != userId) return;
            _notifications = items;
            _loading = false;
            _error = null;
            notifyListeners();
          },
          onError: (_) {
            if (_userId != userId) return;
            _loading = false;
            _error = 'We couldn\'t load notifications.';
            notifyListeners();
          },
        );
  }

  Future<void> markRead(AppNotificationModel item) async {
    if (item.isRead) return;
    try {
      await _repository.markRead(item.id);
    } catch (_) {
      // Navigation must not be blocked when marking an item read fails.
    }
  }

  Future<void> markAllRead() => _repository.markAllRead(_notifications);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
