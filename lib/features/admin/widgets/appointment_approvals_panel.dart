import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';
import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/appointment_approvals.dart';
import '../theme/admin_theme.dart';

Stream<String?> _safeAuthUidStream() {
  if (Firebase.apps.isEmpty) return Stream<String?>.value(null);
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
}

String? _safeCurrentAuthUid() {
  if (Firebase.apps.isEmpty) return null;
  return FirebaseAuth.instance.currentUser?.uid;
}

/// Counselors: "My College's Approvals" (appointments for students in the
/// colleges they serve). Super-administrator: "Approval exceptions"
/// (appointments whose college cannot be confirmed or has no counselor).
/// Pages are loaded from the server; every action is re-authorised there.
class AppointmentApprovalsPanel extends StatefulWidget {
  const AppointmentApprovalsPanel({
    super.key,
    required this.repository,
    required this.appointments,
    required this.onOpen,
    this.authUidChanges,
    this.currentUserIdProvider,
  });

  final AdminPortalRepository repository;

  /// Appointments the page already streams; used for names and to open one.
  final List<AppointmentModel> appointments;
  final ValueChanged<AppointmentModel> onOpen;
  final Stream<String?>? authUidChanges;
  final String? Function()? currentUserIdProvider;

  @override
  State<AppointmentApprovalsPanel> createState() =>
      _AppointmentApprovalsPanelState();
}

class _AppointmentApprovalsPanelState extends State<AppointmentApprovalsPanel> {
  final List<AppointmentApprovalItem> _items = <AppointmentApprovalItem>[];
  String? _nextCursor;
  bool _hasMore = false;
  bool _initialLoading = false;
  bool _loadingMore = false;
  bool _hasLoadedAny = false;
  Object? _error;
  bool _loadMoreFailed = false;
  String? _openingId;
  int _requestEpoch = 0;
  StreamSubscription<String?>? _authSubscription;
  String? _activeUid;
  String _lastAppointmentsSignature = '';

  bool get _isCounselor =>
      widget.repository.currentAccessRole == AccessRole.counselor;
  bool get _isSuperAdmin =>
      widget.repository.currentAccessRole == AccessRole.admin &&
      widget.repository.isSuperAdmin;
  bool get _canViewApprovals => _isCounselor || _isSuperAdmin;

  String _appointmentsSignature(List<AppointmentModel> list) => list
      .map(
        (a) =>
            '${a.id}:${a.status}:${a.scheduleRevision}:${a.proposalRevision}:${a.archivedAt?.millisecondsSinceEpoch ?? ''}',
      )
      .join('|');

  @override
  void initState() {
    super.initState();
    _activeUid = (widget.currentUserIdProvider ?? _safeCurrentAuthUid)();
    _lastAppointmentsSignature = _appointmentsSignature(widget.appointments);
    _subscribeAuth();
    if (_canViewApprovals) {
      _loadInitial();
    }
  }

  @override
  void didUpdateWidget(covariant AppointmentApprovalsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authUidChanges != widget.authUidChanges) {
      _subscribeAuth();
    }
    final nextUid = (widget.currentUserIdProvider ?? _safeCurrentAuthUid)();
    final nextSig = _appointmentsSignature(widget.appointments);
    final repoChanged = oldWidget.repository != widget.repository;
    final uidChanged = nextUid != _activeUid;
    final appointmentsChanged = nextSig != _lastAppointmentsSignature;

    if (uidChanged) {
      _activeUid = nextUid;
    }
    if (appointmentsChanged) {
      _lastAppointmentsSignature = nextSig;
    }

    if (!_canViewApprovals) {
      _resetQueueState();
      return;
    }
    if (repoChanged || uidChanged || appointmentsChanged) {
      _loadInitial();
    }
  }

  void _subscribeAuth() {
    _authSubscription?.cancel();
    final stream = widget.authUidChanges ?? _safeAuthUidStream();
    _authSubscription = stream.listen((uid) {
      if (!mounted) return;
      final resolved = widget.authUidChanges != null
          ? uid
          : (uid ?? widget.currentUserIdProvider?.call());
      if (resolved != _activeUid) {
        _activeUid = resolved;
        if (!_canViewApprovals) {
          setState(_resetQueueState);
        } else {
          _loadInitial();
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _resetQueueState() {
    _requestEpoch += 1;
    _items.clear();
    _nextCursor = null;
    _hasMore = false;
    _initialLoading = false;
    _loadingMore = false;
    _hasLoadedAny = false;
    _error = null;
    _loadMoreFailed = false;
    _openingId = null;
  }

  Future<void> _loadInitial() async {
    if (!_canViewApprovals) return;
    final epoch = ++_requestEpoch;
    setState(() {
      _items.clear();
      _nextCursor = null;
      _hasMore = false;
      _initialLoading = true;
      _loadingMore = false;
      _hasLoadedAny = false;
      _error = null;
      _loadMoreFailed = false;
    });
    try {
      final page = await widget.repository.listAppointmentApprovalsPage();
      if (!mounted || epoch != _requestEpoch || !_canViewApprovals) return;
      setState(() {
        _mergePage(page);
        _initialLoading = false;
        _hasLoadedAny = true;
      });
    } catch (error) {
      if (!mounted || epoch != _requestEpoch) return;
      setState(() {
        _initialLoading = false;
        _error = error;
        _loadMoreFailed = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_canViewApprovals || _loadingMore || _initialLoading || !_hasMore) {
      return;
    }
    final cursor = _nextCursor;
    if (cursor == null || cursor.isEmpty) return;
    final epoch = _requestEpoch;
    setState(() {
      _loadingMore = true;
      _error = null;
      _loadMoreFailed = false;
    });
    try {
      final page = await widget.repository.listAppointmentApprovalsPage(
        cursor: cursor,
      );
      if (!mounted || epoch != _requestEpoch || !_canViewApprovals) return;
      setState(() {
        _mergePage(page);
        _loadingMore = false;
        _hasLoadedAny = true;
      });
    } catch (error) {
      if (!mounted || epoch != _requestEpoch) return;
      setState(() {
        _loadingMore = false;
        _error = error;
        _loadMoreFailed = true;
      });
    }
  }

  void _mergePage(AppointmentApprovalsPage page) {
    final existing = {for (final item in _items) item.appointmentId};
    for (final item in page.items) {
      if (item.appointmentId.isNotEmpty &&
          !existing.contains(item.appointmentId)) {
        _items.add(item);
        existing.add(item.appointmentId);
      }
    }
    _items.sort((a, b) {
      final timeCmp = (a.scheduledAt?.millisecondsSinceEpoch ?? 0).compareTo(
        b.scheduledAt?.millisecondsSinceEpoch ?? 0,
      );
      return timeCmp != 0
          ? timeCmp
          : a.appointmentId.compareTo(b.appointmentId);
    });
    _nextCursor = page.hasMore ? page.nextCursor : null;
    _hasMore = page.hasMore && _nextCursor != null;
  }

  Future<void> _handleOpen(
    AppointmentApprovalItem item,
    AppointmentModel? local,
  ) async {
    if (local != null) {
      widget.onOpen(local);
      return;
    }
    if (_openingId != null) return;
    final epoch = _requestEpoch;
    setState(() => _openingId = item.appointmentId);
    try {
      final fetched = await widget.repository.fetchAppointmentById(
        item.appointmentId,
      );
      if (!mounted || epoch != _requestEpoch || !_canViewApprovals) return;
      setState(() => _openingId = null);
      if (fetched == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This appointment is no longer available. Refresh approvals to update the queue.',
            ),
          ),
        );
        return;
      }
      widget.onOpen(fetched);
    } catch (error) {
      if (!mounted || epoch != _requestEpoch) return;
      setState(() => _openingId = null);
      final denied =
          error is FirebaseFunctionsException &&
          error.code == 'permission-denied';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? 'You are not authorized to open this appointment. Refresh approvals to update the queue.'
                : 'Unable to open this appointment right now. Refresh approvals to retry.',
          ),
        ),
      );
      if (denied && _canViewApprovals) {
        _loadInitial();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canViewApprovals) return const SizedBox.shrink();
    final title = _isCounselor
        ? "My College's Approvals"
        : 'Approval exceptions';
    final countSuffix = _hasLoadedAny
        ? _hasMore
              ? ' (${_items.length}+)'
              : ' (${_items.length})'
        : '';
    final byId = {for (final a in widget.appointments) a.id: a};
    return Material(
      color: AdminColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title$countSuffix',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh approvals',
                  onPressed: _initialLoading || _loadingMore
                      ? null
                      : _loadInitial,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_isSuperAdmin)
              const Text(
                'Appointments whose college cannot be confirmed or has no '
                'eligible counselor. Acting on an appointment that a '
                'counselor is assigned to requires an exception reason.',
                style: TextStyle(color: AdminColors.muted),
              ),
            const SizedBox(height: 8),
            if (_initialLoading)
              const LinearProgressIndicator()
            else if (_error != null && !_loadMoreFailed) ...[
              const Text(
                'Approvals could not be loaded. Refresh or retry to try again.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ] else if (_items.isEmpty && _hasMore) ...[
              const Text(
                'No matching approvals were found in the scanned records yet; additional appointments remain.',
                style: TextStyle(color: AdminColors.muted),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: const Icon(Icons.expand_more),
                label: Text(
                  _loadingMore ? 'Loading more…' : 'Load more approvals',
                ),
              ),
            ] else if (_items.isEmpty)
              const Text(
                'No appointments are waiting for a decision.',
                style: TextStyle(color: AdminColors.muted),
              )
            else ...[
              for (final item in _items)
                _ApprovalRow(
                  item: item,
                  appointment: byId[item.appointmentId],
                  showReason: _isSuperAdmin,
                  opening: _openingId == item.appointmentId,
                  onOpen: () => _handleOpen(item, byId[item.appointmentId]),
                ),
              if (_loadingMore) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (_error != null && _loadMoreFailed) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Additional approvals could not be loaded. Retry to continue.',
                        style: TextStyle(color: AdminColors.muted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _loadMore,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ] else if (_hasMore) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Load more approvals'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({
    required this.item,
    required this.appointment,
    required this.showReason,
    required this.opening,
    required this.onOpen,
  });

  final AppointmentApprovalItem item;
  final AppointmentModel? appointment;
  final bool showReason;
  final bool opening;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final when = item.scheduledAt?.toLocal();
    final details = [
      if (when != null)
        '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}',
      if (item.pendingStudentProposal) 'Student proposed a new time',
      if ((appointment?.department ?? '').trim().isNotEmpty)
        appointment!.department!,
      if (showReason) item.reasonLabel,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(appointment?.fullName ?? 'Appointment ${item.appointmentId}'),
      subtitle: Text(details),
      trailing: OutlinedButton(
        onPressed: opening ? null : onOpen,
        child: Text(opening ? 'Opening…' : 'Review'),
      ),
    );
  }
}
