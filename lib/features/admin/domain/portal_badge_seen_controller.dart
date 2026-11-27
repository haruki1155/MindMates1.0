import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../models/admin_inquiry_model.dart';
import '../../../models/appointment_model.dart';
import '../../../models/appointment_queue_item.dart';
import '../../../models/testing_service_schedule.dart';
import '../services/portal_seen_storage_stub.dart'
    if (dart.library.js_interop) '../services/portal_seen_storage_web.dart'
    as seen_storage;
import 'appointment_workflow.dart';

/// Tracks which actionable appointments and inquiries a read-only supervising
/// user (Admin / PACC operational viewer) has already viewed in the current
/// state revision, persisted across page refreshes on Web via `localStorage`.
///
/// Each item is keyed by a deterministic version key including status,
/// revision counters, and latest update timestamp, so any subsequent student
/// update or new submission automatically surfaces the badge again.
class PortalBadgeSeenController extends ChangeNotifier {
  PortalBadgeSeenController({
    String? userId,
    String? Function(String key)? readStorage,
    void Function(String key, String value)? writeStorage,
  }) : _storageKey =
           'mindmate_portal_seen_v1:${(userId ?? '').trim().isEmpty ? 'anon' : userId!.trim()}',
       _readStorage = readStorage ?? seen_storage.readPortalSeenStorage,
       _writeStorage = writeStorage ?? seen_storage.writePortalSeenStorage {
    _load();
  }

  static const int _maxStoredKeys = 300;

  final String _storageKey;
  final String? Function(String key) _readStorage;
  final void Function(String key, String value) _writeStorage;

  final List<String> _appointmentKeys = <String>[];
  final Set<String> _appointmentKeySet = <String>{};

  final List<String> _inquiryKeys = <String>[];
  final Set<String> _inquiryKeySet = <String>{};

  static String appointmentVersionKey(AppointmentModel a) =>
      '${a.id}|${a.status}|${a.scheduleRevision}|${a.proposalRevision}|'
      '${(a.updatedAt ?? a.createdAt).millisecondsSinceEpoch}';

  static String portalAppointmentQueueVersionKey(AppointmentQueueItem a) =>
      'q|${a.id}|${a.status}|${a.scheduledAt.millisecondsSinceEpoch}|'
      '${a.scheduledTime}|${a.assignedCounselor ?? ''}';

  static String inquiryVersionKey(AdminInquiryModel i) =>
      '${i.id}|${i.status.name}|${i.routingRevision}|'
      '${i.testingSchedule?.status.storedValue ?? ''}|'
      '${i.testingSchedule?.revision ?? 0}|'
      '${(i.lastResponseAt ?? i.createdAt).millisecondsSinceEpoch}';

  void _load() {
    try {
      final raw = _readStorage(_storageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final appts = decoded['appointments'];
      if (appts is List) {
        for (final item in appts) {
          final key = item?.toString() ?? '';
          if (key.isNotEmpty && _appointmentKeySet.add(key)) {
            _appointmentKeys.add(key);
          }
        }
      }
      final inqs = decoded['inquiries'];
      if (inqs is List) {
        for (final item in inqs) {
          final key = item?.toString() ?? '';
          if (key.isNotEmpty && _inquiryKeySet.add(key)) {
            _inquiryKeys.add(key);
          }
        }
      }
    } catch (_) {
      // Malformed storage payload must never break portal initialization.
    }
  }

  void _persist() {
    while (_appointmentKeys.length > _maxStoredKeys) {
      final evicted = _appointmentKeys.removeAt(0);
      _appointmentKeySet.remove(evicted);
    }
    while (_inquiryKeys.length > _maxStoredKeys) {
      final evicted = _inquiryKeys.removeAt(0);
      _inquiryKeySet.remove(evicted);
    }
    try {
      _writeStorage(
        _storageKey,
        jsonEncode({
          'appointments': _appointmentKeys,
          'inquiries': _inquiryKeys,
        }),
      );
    } catch (_) {
      // Ignore write failures cleanly.
    }
  }

  bool isAppointmentSeen(AppointmentModel a) =>
      _appointmentKeySet.contains(appointmentVersionKey(a));

  bool isQueueAppointmentSeen(AppointmentQueueItem a) =>
      _appointmentKeySet.contains(portalAppointmentQueueVersionKey(a));

  bool isInquirySeen(AdminInquiryModel i) =>
      _inquiryKeySet.contains(inquiryVersionKey(i));

  bool markAppointmentsSeen(Iterable<AppointmentModel> items) {
    var changed = false;
    for (final item in items) {
      final key = appointmentVersionKey(item);
      if (_appointmentKeySet.add(key)) {
        _appointmentKeys.add(key);
        changed = true;
      }
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
    return changed;
  }

  bool markQueueAppointmentsSeen(Iterable<AppointmentQueueItem> items) {
    var changed = false;
    for (final item in items) {
      final key = portalAppointmentQueueVersionKey(item);
      if (_appointmentKeySet.add(key)) {
        _appointmentKeys.add(key);
        changed = true;
      }
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
    return changed;
  }

  bool markInquiriesSeen(Iterable<AdminInquiryModel> items) {
    var changed = false;
    for (final item in items) {
      final key = inquiryVersionKey(item);
      if (_inquiryKeySet.add(key)) {
        _inquiryKeys.add(key);
        changed = true;
      }
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
    return changed;
  }

  int countUnseenAppointments(List<AppointmentModel> items, DateTime now) =>
      items
          .where(
            (a) =>
                !a.isArchived &&
                classifyAppointment(a, now) == AppointmentQueue.needsAction &&
                !isAppointmentSeen(a),
          )
          .length;

  int countUnseenQueueAppointments(List<AppointmentQueueItem> items) =>
      items.where((item) {
        if (item.isArchived) return false;
        final st = AppointmentStatus.parse(item.status);
        final needsAction =
            st == AppointmentStatus.requested ||
            st == AppointmentStatus.legacyRequested ||
            st == AppointmentStatus.rescheduleProposed;
        return needsAction && !isQueueAppointmentSeen(item);
      }).length;

  static bool isActionableInquiry(AdminInquiryModel item) {
    if (item.isTestingService) {
      final status =
          item.testingSchedule?.status ??
          TestingScheduleStatus.awaitingSchedule;
      return status == TestingScheduleStatus.awaitingSchedule ||
          status == TestingScheduleStatus.rescheduleRequested;
    }
    return item.status == InquiryStatus.pending;
  }

  int countUnseenInquiries(
    List<AdminInquiryModel> items, {
    bool? testingOnly,
  }) => items.where((item) {
    if (testingOnly == true && !item.isTestingService) return false;
    if (testingOnly == false && item.isTestingService) return false;
    return isActionableInquiry(item) && !isInquirySeen(item);
  }).length;
}
