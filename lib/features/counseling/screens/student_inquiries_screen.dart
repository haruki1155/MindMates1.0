import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../models/student_inquiry_model.dart';
import '../../../repositories/inquiry_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../widgets/testing_service_schedule_card.dart';

class _StudentInquiryPalette {
  const _StudentInquiryPalette._();
  static const background = Color(0xFFF7F8F4);
  static const ink = Color(0xFF1D343C);
  static const muted = Color(0xFF73878E);
  static const border = Color(0xFFE5EAE5);
  static const gold = Color(0xFFF8BF3C);
  static const goldFaint = Color(0xFFFFFAEB);
}

Stream<String?> _safeAuthUidStream() {
  if (Firebase.apps.isEmpty) return Stream<String?>.value(null);
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
}

String? _safeCurrentAuthUid() {
  if (Firebase.apps.isEmpty) return null;
  return FirebaseAuth.instance.currentUser?.uid;
}

bool _isAccessError(Object error) {
  if (error is StateError) return true;
  final code = FirebaseErrorMessage.codeOf(error);
  return code == 'permission-denied' || code == 'unauthenticated';
}

Color _statusBackground(StudentInquiryStatus status) => switch (status) {
  StudentInquiryStatus.pending => const Color(0xFFFFF4D8),
  StudentInquiryStatus.inProgress => const Color(0xFFE5F0FF),
  StudentInquiryStatus.resolved => const Color(0xFFE3F1E6),
};

Color _statusForeground(StudentInquiryStatus status) => switch (status) {
  StudentInquiryStatus.pending => const Color(0xFF8C5B00),
  StudentInquiryStatus.inProgress => const Color(0xFF1D4D8F),
  StudentInquiryStatus.resolved => const Color(0xFF1F6B3A),
};

String _formatDateTime(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour < 12 ? 'AM' : 'PM';
  return '${months[value.month - 1]} ${value.day}, ${value.year} · $hour:$minute $period';
}

/// Student-facing read-only list of inquiries they submitted to PACC.
class MyInquiriesScreen extends StatefulWidget {
  const MyInquiriesScreen({
    super.key,
    this.userId,
    this.repository,
    this.currentUserIdProvider,
    this.authUidChanges,
  });

  final String? userId;
  final InquiryRepository? repository;
  final String? Function()? currentUserIdProvider;
  final Stream<String?>? authUidChanges;

  @override
  State<MyInquiriesScreen> createState() => _MyInquiriesScreenState();
}

class _MyInquiriesScreenState extends State<MyInquiriesScreen> {
  late InquiryRepository _repository;
  late String? _activeUid;
  StreamSubscription<String?>? _authSubscription;
  int _retryEpoch = 0;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        InquiryRepository(currentUserIdProvider: widget.currentUserIdProvider);
    _activeUid =
        (widget.currentUserIdProvider ??
            widget.repository?.currentUserIdProviderOrNull ??
            _safeCurrentAuthUid)() ??
        widget.userId;
    _subscribeAuth();
  }

  @override
  void didUpdateWidget(covariant MyInquiriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.currentUserIdProvider != widget.currentUserIdProvider) {
      _repository =
          widget.repository ??
          InquiryRepository(
            currentUserIdProvider: widget.currentUserIdProvider,
          );
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.authUidChanges != widget.authUidChanges) {
      _activeUid =
          (widget.currentUserIdProvider ??
              widget.repository?.currentUserIdProviderOrNull ??
              _safeCurrentAuthUid)() ??
          widget.userId;
      _retryEpoch = 0;
      _subscribeAuth();
    }
  }

  void _subscribeAuth() {
    _authSubscription?.cancel();
    final stream = widget.authUidChanges ?? _safeAuthUidStream();
    _authSubscription = stream.listen((uid) {
      if (!mounted) return;
      final resolved = widget.authUidChanges != null
          ? uid
          : (uid ?? widget.userId);
      if (resolved != _activeUid) {
        setState(() {
          _activeUid = resolved;
          _retryEpoch++;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _activeUid?.trim();
    final pinnedMismatch =
        widget.userId != null && uid != null && uid != widget.userId!.trim();
    return Scaffold(
      backgroundColor: _StudentInquiryPalette.background,
      appBar: AppBar(
        toolbarHeight: 92,
        backgroundColor: _StudentInquiryPalette.background,
        foregroundColor: _StudentInquiryPalette.ink,
        surfaceTintColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PACC COUNSELING',
              style: TextStyle(
                color: Color(0xFFA17720),
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'My Inquiries',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _StudentInquiryPalette.ink,
              ),
            ),
          ],
        ),
      ),
      body: uid == null || uid.isEmpty || pinnedMismatch
          ? const _StudentInquiryNoticePanel(
              icon: Icons.lock_outline,
              title: 'Sign in required',
              message:
                  'Please sign in with your MindMate account to view your submitted inquiries and PACC replies.',
            )
          : KeyedSubtree(
              key: ValueKey('my-inquiries-$uid-$_retryEpoch'),
              child: StreamBuilder<List<StudentInquiryRecord>>(
                stream: _repository.watchMyInquiries(uid),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final error = snapshot.error!;
                    final accessError = _isAccessError(error);
                    return _StudentInquiryNoticePanel(
                      icon: accessError
                          ? Icons.lock_outline
                          : Icons.cloud_off_outlined,
                      title: accessError
                          ? 'Unable to access inquiries'
                          : 'Could not load your inquiries',
                      message: accessError
                          ? 'Your session changed or does not have permission to view these inquiries.'
                          : FirebaseErrorMessage.describe(
                              error,
                              fallback:
                                  'Unable to load your submitted inquiries right now.',
                            ),
                      onRetry: accessError
                          ? null
                          : () => setState(() => _retryEpoch++),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data ?? const <StudentInquiryRecord>[];
                  if (items.isEmpty) {
                    return const _StudentInquiryNoticePanel(
                      icon: Icons.mark_email_read_outlined,
                      title: 'No submitted inquiries yet',
                      message:
                          'Service forms and inquiries you submit to PACC will appear here along with counselor replies.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        key: ValueKey('student-inquiry-${item.id}'),
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(
                            color: _StudentInquiryPalette.border,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(
                            16,
                            12,
                            12,
                            12,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => StudentInquiryDetailScreen(
                                inquiryId: item.id,
                                userId: uid,
                                repository: _repository,
                                currentUserIdProvider:
                                    widget.currentUserIdProvider,
                                authUidChanges: widget.authUidChanges,
                              ),
                            ),
                          ),
                          title: Text(
                            item.subject,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _StudentInquiryPalette.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _StatusChip(status: item.status),
                                    if (item.testingSchedule != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEAF2FF),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          item.testingSchedule!.status.label,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1D4D8F),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      item.responseCount > 0
                                          ? '${item.responseCount} ${item.responseCount == 1 ? 'reply' : 'replies'}'
                                          : 'Awaiting reply',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _StudentInquiryPalette.ink,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${item.category} · ${_formatDateTime(item.createdAt)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _StudentInquiryPalette.muted,
                                  ),
                                ),
                                if (item.processingCounselorName != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Handled by: ${item.processingCounselorName}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _StudentInquiryPalette.ink,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: _StudentInquiryPalette.muted,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}

/// Read-only student inquiry detail screen displaying the original submitted
/// message and authored counselor/administrator replies under
/// `inquiries/{inquiryId}/replies`.
class StudentInquiryDetailScreen extends StatefulWidget {
  const StudentInquiryDetailScreen({
    super.key,
    required this.inquiryId,
    required this.userId,
    this.repository,
    this.currentUserIdProvider,
    this.authUidChanges,
    this.showTestingSubmissionBanner = false,
  });

  final String inquiryId;
  final String userId;
  final InquiryRepository? repository;
  final String? Function()? currentUserIdProvider;
  final Stream<String?>? authUidChanges;
  final bool showTestingSubmissionBanner;

  @override
  State<StudentInquiryDetailScreen> createState() =>
      _StudentInquiryDetailScreenState();
}

class _StudentInquiryDetailScreenState
    extends State<StudentInquiryDetailScreen> {
  late InquiryRepository _repository;
  late String? _activeUid;
  StreamSubscription<String?>? _authSubscription;
  int _retryEpoch = 0;
  bool _updatingSchedule = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        InquiryRepository(currentUserIdProvider: widget.currentUserIdProvider);
    _activeUid =
        (widget.currentUserIdProvider ??
            widget.repository?.currentUserIdProviderOrNull ??
            _safeCurrentAuthUid)() ??
        widget.userId;
    _subscribeAuth();
  }

  @override
  void didUpdateWidget(covariant StudentInquiryDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.currentUserIdProvider != widget.currentUserIdProvider) {
      _repository =
          widget.repository ??
          InquiryRepository(
            currentUserIdProvider: widget.currentUserIdProvider,
          );
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.inquiryId != widget.inquiryId ||
        oldWidget.authUidChanges != widget.authUidChanges) {
      _activeUid =
          (widget.currentUserIdProvider ??
              widget.repository?.currentUserIdProviderOrNull ??
              _safeCurrentAuthUid)() ??
          widget.userId;
      _retryEpoch = 0;
      _subscribeAuth();
    }
  }

  void _subscribeAuth() {
    _authSubscription?.cancel();
    final stream = widget.authUidChanges ?? _safeAuthUidStream();
    _authSubscription = stream.listen((uid) {
      if (!mounted) return;
      final resolved = widget.authUidChanges != null
          ? uid
          : (uid ?? widget.userId);
      if (resolved != _activeUid) {
        setState(() {
          _activeUid = resolved;
          _retryEpoch++;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _acceptTestingSchedule(StudentInquiryRecord inquiry) async {
    if (_updatingSchedule) return;
    setState(() => _updatingSchedule = true);
    try {
      await _repository.acceptTestingServiceSchedule(
        inquiry.id,
        expectedScheduleRevision: inquiry.testingSchedule?.revision,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Testing Service schedule confirmed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FirebaseErrorMessage.describe(
              error,
              fallback: 'Unable to confirm the proposed schedule.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingSchedule = false);
    }
  }

  Future<void> _requestTestingReschedule(
    StudentInquiryRecord inquiry,
    String reason,
  ) async {
    if (_updatingSchedule) return;
    setState(() => _updatingSchedule = true);
    try {
      await _repository.requestTestingServiceReschedule(
        inquiry.id,
        reason: reason,
        expectedScheduleRevision: inquiry.testingSchedule?.revision,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reschedule request sent to PACC.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FirebaseErrorMessage.describe(
              error,
              fallback: 'Unable to send reschedule request.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingSchedule = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expectedUid = widget.userId.trim();
    final activeUid = _activeUid?.trim();
    final accountMismatch =
        activeUid == null || activeUid.isEmpty || activeUid != expectedUid;
    return Scaffold(
      backgroundColor: _StudentInquiryPalette.background,
      appBar: AppBar(
        toolbarHeight: 84,
        backgroundColor: _StudentInquiryPalette.background,
        foregroundColor: _StudentInquiryPalette.ink,
        surfaceTintColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PACC COUNSELING',
              style: TextStyle(
                color: Color(0xFFA17720),
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Inquiry Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _StudentInquiryPalette.ink,
              ),
            ),
          ],
        ),
      ),
      body: accountMismatch
          ? const _StudentInquiryNoticePanel(
              icon: Icons.lock_outline,
              title: 'Session access changed',
              message:
                  'Please sign in with the account that submitted this inquiry to view its details and PACC replies.',
            )
          : KeyedSubtree(
              key: ValueKey(
                'inquiry-detail-$activeUid-${widget.inquiryId}-$_retryEpoch',
              ),
              child: StreamBuilder<StudentInquiryRecord?>(
                stream: _repository.watchMyInquiry(
                  widget.inquiryId,
                  userId: expectedUid,
                ),
                builder: (context, inquirySnapshot) {
                  if (inquirySnapshot.hasError) {
                    final error = inquirySnapshot.error!;
                    final accessError = _isAccessError(error);
                    return _StudentInquiryNoticePanel(
                      icon: accessError
                          ? Icons.lock_outline
                          : Icons.cloud_off_outlined,
                      title: accessError
                          ? 'Inquiry access restricted'
                          : 'Could not load inquiry',
                      message: accessError
                          ? 'You do not have permission to view this inquiry.'
                          : FirebaseErrorMessage.describe(
                              error,
                              fallback:
                                  'Unable to load this inquiry right now.',
                            ),
                      onRetry: accessError
                          ? null
                          : () => setState(() => _retryEpoch++),
                    );
                  }
                  if (inquirySnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !inquirySnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final inquiry = inquirySnapshot.data;
                  if (inquiry == null) {
                    return const _StudentInquiryNoticePanel(
                      icon: Icons.inbox_outlined,
                      title: 'Inquiry not found',
                      message:
                          'This inquiry was deleted or is no longer available.',
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _StudentInquiryPalette.border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _StatusChip(status: inquiry.status),
                                  Text(
                                    inquiry.category,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _StudentInquiryPalette.muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                inquiry.subject,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: _StudentInquiryPalette.ink,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Submitted ${_formatDateTime(inquiry.createdAt)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _StudentInquiryPalette.muted,
                                ),
                              ),
                              if (!inquiry.isTestingService &&
                                  inquiry.processingCounselorName != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.badge_outlined,
                                      size: 16,
                                      color: _StudentInquiryPalette.ink,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Processing Counselor: ${inquiry.processingCounselorName}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _StudentInquiryPalette.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const Divider(height: 28),
                              const Text(
                                'Your message',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _StudentInquiryPalette.ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                inquiry.message.trim().isEmpty
                                    ? 'No message provided.'
                                    : inquiry.message,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: _StudentInquiryPalette.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (inquiry.isTestingService ||
                            inquiry.testingSchedule != null) ...[
                          TestingServiceScheduleCard(
                            inquiry: inquiry,
                            busy: _updatingSchedule,
                            showSubmissionBanner:
                                widget.showTestingSubmissionBanner,
                            onLoadDocument: (path) =>
                                _repository.downloadTestingServiceDocument(
                                  inquiryId: inquiry.id,
                                  path: path,
                                ),
                            onAccept: () => _acceptTestingSchedule(inquiry),
                            onRequestReschedule: (reason) =>
                                _requestTestingReschedule(inquiry, reason),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _RepliesSection(
                          inquiryId: inquiry.id,
                          repository: _repository,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _RepliesSection extends StatefulWidget {
  const _RepliesSection({required this.inquiryId, required this.repository});

  final String inquiryId;
  final InquiryRepository repository;

  @override
  State<_RepliesSection> createState() => _RepliesSectionState();
}

class _RepliesSectionState extends State<_RepliesSection> {
  int _replyEpoch = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _StudentInquiryPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.forum_outlined,
                size: 18,
                color: _StudentInquiryPalette.ink,
              ),
              SizedBox(width: 8),
              Text(
                'PACC Replies',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _StudentInquiryPalette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: ValueKey('replies-${widget.inquiryId}-$_replyEpoch'),
            child: StreamBuilder<List<StudentInquiryReply>>(
              stream: widget.repository.watchMyInquiryReplies(widget.inquiryId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Replies could not be loaded right now.',
                        style: TextStyle(color: _StudentInquiryPalette.muted),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _replyEpoch++),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final replies = snapshot.data ?? const <StudentInquiryReply>[];
                if (replies.isEmpty) {
                  return const Text(
                    'No reply from PACC yet. When a counselor responds, their reply will appear here.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: _StudentInquiryPalette.muted,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < replies.length; i++) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _StudentInquiryPalette.goldFaint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _StudentInquiryPalette.gold.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${replies[i].authorName} · ${replies[i].roleLabel}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: _StudentInquiryPalette.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (replies[i].createdAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                _formatDateTime(replies[i].createdAt!),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _StudentInquiryPalette.muted,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              replies[i].message,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: _StudentInquiryPalette.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < replies.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final StudentInquiryStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _statusBackground(status),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: _statusForeground(status),
      ),
    ),
  );
}

class _StudentInquiryNoticePanel extends StatelessWidget {
  const _StudentInquiryNoticePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _StudentInquiryPalette.muted),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _StudentInquiryPalette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: _StudentInquiryPalette.muted,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    ),
  );
}

extension on InquiryRepository {
  String? Function()? get currentUserIdProviderOrNull => () => currentUserId;
}
