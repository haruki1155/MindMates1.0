import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// A badge counts conversations, not individual messages.
class CounselorInboxUnreadBadge extends StatelessWidget {
  const CounselorInboxUnreadBadge({super.key});

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return const SizedBox.shrink();
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('counselor_threads').snapshots(),
      builder: (context, threads) {
        if (!threads.hasData || threads.hasError) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('counselor_inbox_reads')
              .doc(uid)
              .collection('threads')
              .snapshots(),
          builder: (context, receipts) {
            if (!receipts.hasData || receipts.hasError) {
              return const SizedBox.shrink();
            }
            final seen = {
              for (final doc in receipts.data!.docs)
                doc.id: doc.data()['readAt'],
            };
            final count = threads.data!.docs
                .where((doc) => counselorThreadUnread(doc.data(), seen[doc.id]))
                .length;
            return UnreadCountBadge(count: count);
          },
        );
      },
    );
  }
}

bool counselorThreadUnread(Map<String, dynamic> data, dynamic readAt) {
  final last = data['lastStudentMessageAt'];
  return last is Timestamp &&
      (readAt is! Timestamp || last.compareTo(readAt) > 0);
}

bool studentThreadUnread(Map<String, dynamic> data) {
  final last = data['lastCounselorMessageAt'];
  final seen = data['studentReadAt'];
  return last is Timestamp && (seen is! Timestamp || last.compareTo(seen) > 0);
}

class StudentCounselorUnreadBadge extends StatelessWidget {
  const StudentCounselorUnreadBadge({
    super.key,
    this.backgroundColor,
    this.foregroundColor,
  });
  final Color? backgroundColor;
  final Color? foregroundColor;
  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return const SizedBox.shrink();
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('counselor_threads')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return const SizedBox.shrink();
        }
        return UnreadCountBadge(
          count: studentThreadUnread(snapshot.data!.data() ?? {}) ? 1 : 0,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        );
      },
    );
  }
}

class UnreadCountBadge extends StatelessWidget {
  const UnreadCountBadge({
    super.key,
    required this.count,
    this.backgroundColor,
    this.foregroundColor,
  });
  final Color? backgroundColor;
  final Color? foregroundColor;
  final int count;
  @override
  Widget build(BuildContext context) {
    if (count < 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.red.shade700,
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foregroundColor ?? Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
