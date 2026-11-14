import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../domain/session_evidence.dart';
import '../services/clinical_file_download_stub.dart'
    if (dart.library.js_interop) '../services/clinical_file_download_web.dart'
    as clinical_download;

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
      Text('Session attachments',
          style: Theme.of(context).textTheme.titleMedium),
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
          leading: Icon(files[index].contentType.startsWith('image/')
              ? Icons.image_outlined : Icons.description_outlined),
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
  });

  final AdminPortalRepository repository;
  final String appointmentId;

  @override
  State<ClinicalInterviewRecordViewer> createState() =>
      _ClinicalInterviewRecordViewerState();
}

class _ClinicalInterviewRecordViewerState
    extends State<ClinicalInterviewRecordViewer> {
  Future<SessionEvidenceRecord?>? _future;
  bool _downloading = false;

  Future<void> _download(SessionEvidenceAttachment file) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await widget.repository.getClinicalEvidenceBytes(file.path);
      await clinical_download.saveClinicalFileBytes(
        bytes, file.name, file.contentType,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Unable to download this private file.')),
        );
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
            final request = widget.repository
                .getClinicalSessionEvidence(widget.appointmentId);
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
                  final request = widget.repository
                      .getClinicalSessionEvidence(widget.appointmentId);
                  setState(() {
                    _future = request;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Unable to load session documentation. Retry'),
              );
            }
            if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            final record = snapshot.data;
            if (record == null) {
              return const Text('No session documentation was recorded.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Private session documentation',
                    style: Theme.of(context).textTheme.titleMedium),
                _PrivateField(label: 'Session summary', value: record.summary),
                if (record.attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Private attachments',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final file in record.attachments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file_outlined),
                      title: Text(file.name),
                      subtitle: Text('${(file.size / 1024).toStringAsFixed(0)} KB'),
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
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        Text(value.isEmpty ? 'Not recorded' : value),
      ],
    ),
  );
}
