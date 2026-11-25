import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../domain/session_evidence.dart';
import '../services/clinical_file_download_stub.dart'
    if (dart.library.js_interop) '../services/clinical_file_download_web.dart'
    as clinical_download;

typedef ClinicalFileSaver =
    Future<void> Function(Uint8List bytes, String fileName, String contentType);

/// Display-only editor. The parent appointment review owns the draft and
/// submits it to the server exclusively on a confirmed session completion.
class ClinicalInterviewEditor extends StatelessWidget {
  const ClinicalInterviewEditor({
    super.key,
    required this.files,
    required this.busy,
    required this.onChooseFiles,
    required this.onRemoveFile,
  });

  final List<PendingSessionEvidenceFile> files;
  final bool busy;
  final VoidCallback onChooseFiles;
  final ValueChanged<int> onRemoveFile;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(
        'Session attachments',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      const Text(
        'Private counseling files. Visible only to authorized clinical staff, not the student.',
        style: TextStyle(fontSize: 12, color: Color(0xFF6B6660)),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy || files.length >= maxSessionEvidenceFiles
            ? null
            : onChooseFiles,
        icon: const Icon(Icons.attach_file_outlined),
        label: const Text('Add images / documents'),
      ),
      const SizedBox(height: 6),
      const Text(
        'PNG, JPG, PDF, DOC or DOCX. Up to 5 files, 5 MB each.',
        style: TextStyle(fontSize: 12, color: Color(0xFF6B6660)),
      ),
      for (var index = 0; index < files.length; index++)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            files[index].contentType.startsWith('image/')
                ? Icons.image_outlined
                : Icons.description_outlined,
          ),
          title: Text(files[index].name),
          subtitle: Text('${(files[index].size / 1024).toStringAsFixed(0)} KB'),
          trailing: IconButton(
            tooltip: 'Remove ${files[index].name}',
            icon: const Icon(Icons.close),
            onPressed: busy ? null : () => onRemoveFile(index),
          ),
        ),
    ],
  );
}

/// Loading is deliberate: no clinical note is fetched until the clinician
/// explicitly opens the review section. Authenticated Firestore rules apply.
class ClinicalInterviewRecordViewer extends StatefulWidget {
  const ClinicalInterviewRecordViewer({
    super.key,
    required this.repository,
    required this.appointmentId,
    this.saveFile,
  });

  final AdminPortalRepository repository;
  final String appointmentId;
  final ClinicalFileSaver? saveFile;

  @override
  State<ClinicalInterviewRecordViewer> createState() =>
      _ClinicalInterviewRecordViewerState();
}

class _ClinicalInterviewRecordViewerState
    extends State<ClinicalInterviewRecordViewer> {
  Future<SessionEvidenceRecord?>? _future;
  bool _downloading = false;

  static final RegExp _unsafeTextPattern = RegExp(
    r'counseling_session_files(?:/|\\|%2f|%5c|%252f|%255c)|gs(?::|%3a)(?://|%2f%2f)|https?(?::|%3a)(?://|%2f%2f)|token(?:=|%3d)|(?:firebase)?storage\.googleapis\.com',
    caseSensitive: false,
  );

  String _sanitizeDownloadMessage(String candidate, String fallback) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty ||
        trimmed.toUpperCase() == 'INTERNAL' ||
        _unsafeTextPattern.hasMatch(trimmed)) {
      return fallback;
    }
    return trimmed;
  }

  String _describeDownloadError(Object error) {
    const fallback =
        'Unable to download this private file right now. Please try again.';
    if (error is UnsupportedError) {
      return _sanitizeDownloadMessage(
        error.message ?? '',
        'Clinical file downloading is available in the Web portal.',
      );
    }
    if (error is TimeoutException) {
      return 'MindMate did not respond in time. Your request may still be processing; check your connection before trying again.';
    }
    if (error is FormatException || error is StateError) {
      return 'This private file cannot be downloaded because it is invalid or exceeds the 5 MB limit.';
    }
    final code = FirebaseErrorMessage.codeOf(error);
    switch (code) {
      case 'permission-denied':
      case 'unauthorized':
        return 'You do not have permission to download this private file.';
      case 'unauthenticated':
        return 'Please sign in again to continue.';
      case 'not-found':
      case 'object-not-found':
        return 'This private file is no longer available.';
      case 'failed-precondition':
      case 'invalid-argument':
        return 'This private file cannot be downloaded because it is invalid or exceeds the 5 MB limit.';
      case 'unavailable':
      case 'network-request-failed':
        return 'The connection to MindMates is unavailable. Check your internet connection and try again.';
      case 'internal':
      case 'already-exists':
        return fallback;
      default:
        if (error is FirebaseFunctionsException || error is FirebaseException) {
          return _sanitizeDownloadMessage(
            FirebaseErrorMessage.describe(error, fallback: fallback),
            fallback,
          );
        }
        return fallback;
    }
  }

  String _safeFileName(String rawName) {
    final cleaned = rawName
        .replaceAll(RegExp(r'[\x00-\x1f]'), '')
        .replaceAll(RegExp(r'[/\\]'), '_')
        .trim();
    if (cleaned.isEmpty || RegExp(r'^[._\s]+$').hasMatch(cleaned)) {
      return 'attachment';
    }
    return cleaned;
  }

  String _safeContentType(SessionEvidenceAttachment file, String safeName) {
    final declared = file.contentType.trim();
    if (declared.isNotEmpty) return declared;
    return sessionEvidenceMimeType(safeName) ?? 'application/octet-stream';
  }

  Future<void> _download(SessionEvidenceAttachment file) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await widget.repository.getClinicalEvidenceBytes(
        file.path,
        appointmentId: widget.appointmentId,
      );
      final safeName = _safeFileName(file.name);
      final safeContentType = _safeContentType(file, safeName);
      final saver = widget.saveFile ?? clinical_download.saveClinicalFileBytes;
      await saver(bytes, safeName, safeContentType);
    } catch (error) {
      if (mounted) {
        final message = _describeDownloadError(error);
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      if (_future == null)
        OutlinedButton.icon(
          onPressed: () {
            final request = widget.repository.getClinicalSessionEvidence(
              widget.appointmentId,
            );
            setState(() {
              _future = request;
            });
          },
          icon: const Icon(Icons.assignment_turned_in_outlined),
          label: const Text('View session documentation'),
        )
      else
        FutureBuilder<SessionEvidenceRecord?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton.icon(
                onPressed: () {
                  final request = widget.repository.getClinicalSessionEvidence(
                    widget.appointmentId,
                  );
                  setState(() {
                    _future = request;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text(
                  'Unable to load session documentation. Retry',
                ),
              );
            }
            if (!snapshot.hasData &&
                snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            final record = snapshot.data;
            if (record == null) {
              return const Text('No session documentation was recorded.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Private session documentation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _PrivateField(label: 'Session summary', value: record.summary),
                if (record.attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Private attachments',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final file in record.attachments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file_outlined),
                      title: Text(file.name),
                      subtitle: Text(
                        '${(file.size / 1024).toStringAsFixed(0)} KB',
                      ),
                      trailing: IconButton(
                        tooltip: 'Download ${file.name}',
                        onPressed: _downloading ? null : () => _download(file),
                        icon: const Icon(Icons.download_outlined),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
    ],
  );
}

class _PrivateField extends StatelessWidget {
  const _PrivateField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        Text(value.isEmpty ? 'Not recorded' : value),
      ],
    ),
  );
}
