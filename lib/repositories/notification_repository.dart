import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/app_notification_model.dart';
import '../services/firebase/firestore_service.dart';

class NotificationRepository {
  NotificationRepository({FirestoreService? firestoreService})
    : _firestoreService = firestoreService ?? FirestoreService();

  final FirestoreService _firestoreService;

  Stream<List<AppNotificationModel>> watchNotifications(String userId) =>
      _firestoreService
          .watchDocuments(
            FirestoreCollections.notifications,
            whereEquals: {'userId': userId},
            orderBy: 'createdAt',
            descending: true,
            limit: 100,
          )
          .map(
            (items) =>
                items
                    .map(
                      (item) => AppNotificationModel.fromJson(
                        item,
                        id: item['id']?.toString(),
                      ),
                    )
                    .where((item) => !item.isArchived)
                    .toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          );

  Future<void> markRead(String id) => _firestoreService.updateDocument(
    FirestoreCollections.notifications,
    id,
    {'readAt': FieldValue.serverTimestamp()},
  );

  Future<void> markAllRead(Iterable<AppNotificationModel> notifications) async {
    await Future.wait(
      notifications
          .where((item) => !item.isRead)
          .map((item) => markRead(item.id)),
    );
  }
}
