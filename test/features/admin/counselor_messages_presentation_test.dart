import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/counselor_message_presentation.dart';
import 'package:mind_mates/features/counseling/domain/counselor_inbox_read_state.dart';

void main() {
  group('Timestamp & day-label formatting (Asia/Manila)', () {
    test(
      'formats stored createdAt deterministically in Manila time (12h & 24h)',
      () {
        // 2026-11-22 10:05 UTC == 2026-11-22 18:05 Asia/Manila
        final dt = DateTime.utc(2026, 11, 22, 10, 5);
        expect(formatCounselorMessageTimestamp(dt), '6:05 PM');
        expect(
          formatCounselorMessageTimestamp(dt, use24HourFormat: true),
          '18:05',
        );

        // Midnight & noon Manila edge cases
        final manilaMidnight = DateTime.utc(2026, 11, 21, 16, 0);
        final manilaNoon = DateTime.utc(2026, 11, 22, 4, 0);
        expect(formatManilaTimeOfDay(manilaMidnight), '12:00 AM');
        expect(formatManilaTimeOfDay(manilaNoon), '12:00 PM');
      },
    );

    test('returns safe pending strings when createdAt is null', () {
      expect(formatCounselorMessageTimestamp(null), 'Time pending');
      expect(
        formatCounselorMessageTimestamp(null, isSending: true),
        'Sending…',
      );
    });

    test(
      'computes Today, Yesterday, and formatted date using Manila calendar days',
      () {
        // Manila now: 2026-11-22 01:00 AM (which is 2026-11-21 17:00 UTC)
        final now = DateTime.utc(2026, 11, 21, 17, 0);
        final sameManilaDay = DateTime.utc(
          2026,
          11,
          22,
          15,
          30,
        ); // 23:30 Manila
        final yesterdayManila = DateTime.utc(
          2026,
          11,
          21,
          10,
          0,
        ); // Nov 21 18:00 Manila
        final older = DateTime.utc(2026, 11, 18, 8, 0);

        expect(counselorMessageDayLabel(sameManilaDay, now: now), 'Today');
        expect(
          counselorMessageDayLabel(yesterdayManila, now: now),
          'Yesterday',
        );
        expect(counselorMessageDayLabel(older, now: now), 'Nov 18, 2026');
        expect(isSameCounselorMessageDay(now, sameManilaDay), isTrue);
        expect(isSameCounselorMessageDay(now, yesterdayManila), isFalse);
      },
    );

    test('formats thread last-activity timestamp across recency buckets', () {
      final now = DateTime.utc(2026, 11, 22, 6, 0); // Nov 22, 2:00 PM Manila
      final todayTs = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 4, 30));
      final yesterdayTs = Timestamp.fromDate(DateTime.utc(2026, 11, 21, 10, 0));
      final sameYearTs = Timestamp.fromDate(DateTime.utc(2026, 11, 10, 10, 0));
      final priorYearTs = Timestamp.fromDate(DateTime.utc(2025, 12, 25, 10, 0));

      expect(formatCounselorThreadActivityTime(null, now: now), 'No activity');
      expect(formatCounselorThreadActivityTime(todayTs, now: now), '12:30 PM');
      expect(
        formatCounselorThreadActivityTime(yesterdayTs, now: now),
        'Yesterday',
      );
      expect(formatCounselorThreadActivityTime(sameYearTs, now: now), 'Nov 10');
      expect(
        formatCounselorThreadActivityTime(priorYearTs, now: now),
        'Dec 25, 2025',
      );
    });

    test('extracts max activity timestamp and maps Task 4 status labels', () {
      final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 8, 0));
      final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 9, 0));
      final t3 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
      final state = CounselorThreadReadState(
        studentId: 's1',
        collegeId: 'CITE',
        studentName: 'Ana',
        updatedAt: t1,
        lastStudentMessageAt: t2,
        lastStudentMessageId: 'm2',
        lastCounselorMessageAt: t3,
        serverReadAt: null,
        receiptHasPendingWrites: false,
        status: CounselorReadStatus.unread,
      );
      expect(counselorThreadLastActivityAt(state), t3);
      expect(counselorThreadStatusLabel(state), 'Unread');
      expect(
        counselorThreadStatusLabel(
          CounselorThreadReadState(
            studentId: 's1',
            collegeId: null,
            studentName: null,
            updatedAt: null,
            lastStudentMessageAt: null,
            lastStudentMessageId: null,
            lastCounselorMessageAt: null,
            serverReadAt: null,
            receiptHasPendingWrites: false,
            status: CounselorReadStatus.pendingRead,
          ),
        ),
        'Syncing…',
      );
      expect(
        counselorThreadStatusLabel(
          CounselorThreadReadState(
            studentId: 's1',
            collegeId: null,
            studentName: null,
            updatedAt: null,
            lastStudentMessageAt: null,
            lastStudentMessageId: null,
            lastCounselorMessageAt: null,
            serverReadAt: null,
            receiptHasPendingWrites: false,
            status: CounselorReadStatus.read,
          ),
        ),
        'Read',
      );
    });
  });

  group('Message merge, pending timestamp sorting & deduplication', () {
    test(
      'places unresolved createdAt messages after confirmed messages and deduplicates sending items cleanly',
      () {
        final t1 = DateTime.utc(2026, 11, 22, 10, 0);
        final t2 = DateTime.utc(2026, 11, 22, 10, 1);

        final olderHello = CounselorTimelineMessage(
          id: 'm1',
          text: 'Hello',
          senderId: 'counselor-a',
          senderRole: 'counselor',
          createdAt: t1,
        );
        final studentMsg = CounselorTimelineMessage(
          id: 'm2',
          text: 'Need help',
          senderId: 's1',
          senderRole: 'user',
          createdAt: t2,
        );

        // Sending a duplicate text 'Hello' while an older 'Hello' (m1) already existed:
        // must NOT collide with m1 because m1 is in knownServerIdsAtSend.
        final localSending = LocalCounselorOutgoingMessage(
          localId: 'out_1',
          uid: 'counselor-a',
          studentId: 's1',
          text: 'Hello',
          queuedAt: DateTime.utc(2026, 11, 22, 10, 2),
          knownServerIdsAtSend: {'m1', 'm2'},
          status: CounselorOutgoingStatus.sending,
        );

        final beforeServerEmit = mergeAndSortCounselorMessages(
          serverMessages: [studentMsg, olderHello],
          localOutgoing: [localSending],
        );
        expect(beforeServerEmit.map((m) => m.id).toList(), [
          'm1',
          'm2',
          'local:out_1',
        ]);
        expect(
          beforeServerEmit.last.deliveryState,
          CounselorMessageDeliveryState.sending,
        );
        expect(
          resolvedLocalOutgoingIds(
            serverMessages: [studentMsg, olderHello],
            localOutgoing: [localSending],
          ),
          isEmpty,
        );

        // Server emits pending doc (hasPendingWrites: true, createdAt: null) -> deduplicated!
        final pendingDoc = CounselorTimelineMessage(
          id: 'm3',
          text: 'Hello',
          senderId: 'counselor-a',
          senderRole: 'counselor',
          createdAt: null,
          hasPendingWrites: true,
        );
        final withPendingDoc = mergeAndSortCounselorMessages(
          serverMessages: [pendingDoc, studentMsg, olderHello],
          localOutgoing: [localSending],
        );
        expect(withPendingDoc.map((m) => m.id).toList(), ['m1', 'm2', 'm3']);
        expect(
          resolvedLocalOutgoingIds(
            serverMessages: [pendingDoc, studentMsg, olderHello],
            localOutgoing: [localSending],
          ),
          isEmpty,
        );

        // Server commits m3 with createdAt -> deduplicated and marked resolved!
        final committedDoc = CounselorTimelineMessage(
          id: 'm3',
          text: 'Hello',
          senderId: 'counselor-a',
          senderRole: 'counselor',
          createdAt: DateTime.utc(2026, 11, 22, 10, 2, 1),
          hasPendingWrites: false,
        );
        final afterCommit = mergeAndSortCounselorMessages(
          serverMessages: [committedDoc, studentMsg, olderHello],
          localOutgoing: [localSending],
        );
        expect(afterCommit.map((m) => m.id).toList(), ['m1', 'm2', 'm3']);
        expect(
          afterCommit.last.deliveryState,
          CounselorMessageDeliveryState.confirmed,
        );
        expect(
          resolvedLocalOutgoingIds(
            serverMessages: [committedDoc, studentMsg, olderHello],
            localOutgoing: [localSending],
          ),
          {'out_1'},
        );
      },
    );

    test('retains failed local outgoing items for Retry / Dismiss', () {
      final failedLocal = LocalCounselorOutgoingMessage(
        localId: 'out_2',
        uid: 'counselor-a',
        studentId: 's1',
        text: 'Offline reply',
        queuedAt: DateTime.utc(2026, 11, 22, 10, 5),
        knownServerIdsAtSend: const {'m1'},
        status: CounselorOutgoingStatus.failed,
      );
      final merged = mergeAndSortCounselorMessages(
        serverMessages: [
          CounselorTimelineMessage(
            id: 'm1',
            text: 'Question',
            senderId: 's1',
            senderRole: 'user',
            createdAt: DateTime.utc(2026, 11, 22, 10, 0),
          ),
        ],
        localOutgoing: [failedLocal],
      );
      expect(merged, hasLength(2));
      expect(merged.last.id, 'local:out_2');
      expect(merged.last.deliveryState, CounselorMessageDeliveryState.failed);
    });
  });

  group('Smart auto-scroll decision helpers', () {
    test('detects near-bottom within 96px threshold', () {
      expect(
        isCounselorTimelineNearBottom(hasClients: false, pixels: 300),
        isTrue,
      );
      expect(
        isCounselorTimelineNearBottom(hasClients: true, pixels: 0),
        isTrue,
      );
      expect(
        isCounselorTimelineNearBottom(hasClients: true, pixels: 96),
        isTrue,
      );
      expect(
        isCounselorTimelineNearBottom(hasClients: true, pixels: 96.1),
        isFalse,
      );
    });

    test(
      'resolves scroll actions for own send, near-bottom, scrolled-up incoming, and older history load',
      () {
        // Near-bottom incoming message -> scrollToBottom
        expect(
          resolveCounselorTimelineScrollAction(
            hasNewAtEnd: true,
            hasAnyAdditions: true,
            ownSendStarted: false,
            newAtEndContainsCounselor: false,
            nearBottom: true,
          ),
          CounselorScrollAction.scrollToBottom,
        );

        // Scrolled up + incoming student message -> defer & preserve anchor (do NOT yank!)
        expect(
          resolveCounselorTimelineScrollAction(
            hasNewAtEnd: true,
            hasAnyAdditions: true,
            ownSendStarted: false,
            newAtEndContainsCounselor: false,
            nearBottom: false,
          ),
          CounselorScrollAction.deferAndPreserveAnchor,
        );

        // Scrolled up + own send started -> scrollToBottom
        expect(
          resolveCounselorTimelineScrollAction(
            hasNewAtEnd: true,
            hasAnyAdditions: true,
            ownSendStarted: true,
            newAtEndContainsCounselor: false,
            nearBottom: false,
          ),
          CounselorScrollAction.scrollToBottom,
        );

        // Scrolled up + older history prepended (no newAtEnd) -> preserveAnchor
        expect(
          resolveCounselorTimelineScrollAction(
            hasNewAtEnd: false,
            hasAnyAdditions: true,
            ownSendStarted: false,
            newAtEndContainsCounselor: false,
            nearBottom: false,
          ),
          CounselorScrollAction.preserveAnchor,
        );
      },
    );
  });
}
