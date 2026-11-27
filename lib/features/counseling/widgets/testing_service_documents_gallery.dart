import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../models/testing_service_schedule.dart';
import '../../../services/firebase/firebase_error_message.dart';

typedef TestingServiceDocumentLoader =
    Future<({String name, String contentType, Uint8List bytes})> Function(
      String path,
    );

typedef TestingServiceDocumentDownloader =
    Future<void> Function(({String name, String contentType, Uint8List bytes}));

/// Bounded in-memory cache so stream/widget rebuilds do not re-download
/// Testing Service images or trigger repeated download audit log entries.
class TestingServiceDocumentCache {
  TestingServiceDocumentCache._();

  static const int _maxEntries = 40;
  static final LinkedHashMap<
    String,
    ({String name, String contentType, Uint8List bytes})
  >
  _cache =
      LinkedHashMap<
        String,
        ({String name, String contentType, Uint8List bytes})
      >();

  static String _key(String inquiryId, String path) => '$inquiryId::$path';

  static ({String name, String contentType, Uint8List bytes})? get(
    String inquiryId,
    String path,
  ) {
    final key = _key(inquiryId, path);
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  static void put(
    String inquiryId,
    String path,
    ({String name, String contentType, Uint8List bytes}) value,
  ) {
    final key = _key(inquiryId, path);
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static void clearForTests() => _cache.clear();
}

/// Renders uploaded Testing Service documents with live inline image previews,
/// tap-to-zoom lightbox inspection, and PDF open/download controls.
class TestingServiceDocumentsGallery extends StatefulWidget {
  const TestingServiceDocumentsGallery({
    super.key,
    required this.inquiryId,
    required this.documents,
    required this.loadDocument,
    this.onDownloadFile,
    this.compact = false,
  });

  final String inquiryId;
  final TestingServiceDocuments documents;
  final TestingServiceDocumentLoader loadDocument;
  final TestingServiceDocumentDownloader? onDownloadFile;
  final bool compact;

  @override
  State<TestingServiceDocumentsGallery> createState() =>
      _TestingServiceDocumentsGalleryState();
}

class _TestingServiceDocumentsGalleryState
    extends State<TestingServiceDocumentsGallery> {
  final Map<String, ({String name, String contentType, Uint8List bytes})>
  _loaded = {};
  final Set<String> _loadingPaths = {};
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _syncAndLoadImages();
  }

  @override
  void didUpdateWidget(covariant TestingServiceDocumentsGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inquiryId != widget.inquiryId ||
        !_samePaths(oldWidget.documents, widget.documents)) {
      _syncAndLoadImages();
    }
  }

  bool _samePaths(TestingServiceDocuments a, TestingServiceDocuments b) {
    final aPaths = a.all.map((d) => d.path).toList(growable: false);
    final bPaths = b.all.map((d) => d.path).toList(growable: false);
    if (aPaths.length != bPaths.length) return false;
    for (var i = 0; i < aPaths.length; i++) {
      if (aPaths[i] != bPaths[i]) return false;
    }
    return true;
  }

  void _syncAndLoadImages() {
    for (final doc in widget.documents.all) {
      final displayName = _displayNameFor(doc, widget.documents.all);
      final cached = TestingServiceDocumentCache.get(widget.inquiryId, doc.path);
      if (cached != null) {
        _loaded[doc.path] = (
          name: displayName,
          contentType: cached.contentType,
          bytes: cached.bytes,
        );
        _errors.remove(doc.path);
      } else if (doc.isImage) {
        _fetchDocument(doc, openLightboxWhenDone: false);
      }
    }
  }

  String _displayNameFor(
    TestingServiceDocumentRef doc,
    List<TestingServiceDocumentRef> allDocs,
  ) {
    if (doc.kind != TestingDocumentKind.admissionRequirement) {
      return doc.displayFileName();
    }
    var admissionOrder = 0;
    for (final candidate in allDocs) {
      if (candidate.kind == TestingDocumentKind.admissionRequirement) {
        admissionOrder++;
        if (candidate.path == doc.path) {
          return doc.displayFileName(admissionIndex: admissionOrder);
        }
      }
    }
    return doc.displayFileName();
  }

  Future<void> _fetchDocument(
    TestingServiceDocumentRef doc, {
    required bool openLightboxWhenDone,
  }) async {
    final displayName = _displayNameFor(doc, widget.documents.all);
    final cached =
        _loaded[doc.path] ??
        TestingServiceDocumentCache.get(widget.inquiryId, doc.path);
    if (cached != null) {
      final normalized = (
        name: displayName,
        contentType: cached.contentType,
        bytes: cached.bytes,
      );
      _loaded[doc.path] = normalized;
      if (openLightboxWhenDone && mounted) {
        await _handleOpenResult(doc, normalized);
      }
      return;
    }
    if (_loadingPaths.contains(doc.path)) return;
    setState(() {
      _loadingPaths.add(doc.path);
      _errors.remove(doc.path);
    });
    try {
      final rawResult = await widget.loadDocument(doc.path);
      final result = (
        name: displayName,
        contentType: rawResult.contentType,
        bytes: rawResult.bytes,
      );
      TestingServiceDocumentCache.put(widget.inquiryId, doc.path, result);
      if (!mounted) return;
      setState(() {
        _loaded[doc.path] = result;
      });
      if (openLightboxWhenDone) {
        await _handleOpenResult(doc, result);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errors[doc.path] = FirebaseErrorMessage.describe(
          error,
          fallback: 'Could not load document preview.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPaths.remove(doc.path);
        });
      }
    }
  }

  Future<void> _handleOpenResult(
    TestingServiceDocumentRef doc,
    ({String name, String contentType, Uint8List bytes}) result,
  ) async {
    if (doc.isImage || result.contentType.startsWith('image/')) {
      await _showZoomDialog(result);
      return;
    }
    if (widget.onDownloadFile != null) {
      await widget.onDownloadFile!(result);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verified "${result.name}" (${math.max(1, (result.bytes.length / 1024).round())} KB).',
          ),
        ),
      );
    }
  }

  Future<void> _showZoomDialog(
    ({String name, String contentType, Uint8List bytes}) file,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        key: const ValueKey('testing-doc-lightbox'),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                actions: [
                  if (widget.onDownloadFile != null)
                    IconButton(
                      tooltip: 'Download ${file.name}',
                      onPressed: () => widget.onDownloadFile!(file),
                      icon: const Icon(Icons.download_outlined),
                    ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF141B1E),
                  padding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(
                      child: Image.memory(
                        file.bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Text(
                          'Unable to display image bytes.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  'Pinch or scroll to zoom and inspect details.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5D7077)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allDocs = widget.documents.all;
    if (allDocs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Uploaded Documents',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1D343C),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < allDocs.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildDocCard(allDocs[i], i),
        ],
      ],
    );
  }

  Widget _buildDocCard(TestingServiceDocumentRef doc, int index) {
    final sizeKb = math.max(1, (doc.size / 1024).round());
    final displayName = _displayNameFor(doc, widget.documents.all);
    final loaded = _loaded[doc.path];
    final loading = _loadingPaths.contains(doc.path);
    final error = _errors[doc.path];

    return Container(
      key: ValueKey('testing-doc-card-${doc.path}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E6E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5D8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  doc.kind.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A6810),
                  ),
                ),
              ),
              Text(
                '${doc.isPdf ? 'PDF' : 'Image'} · $sizeKb KB',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7D83),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (doc.isImage)
            _buildImagePreviewFrame(doc, index, loaded, loading, error)
          else
            _buildPdfCardRow(doc, index, loading, error),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                displayName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D343C),
                ),
              ),
              if (doc.isImage && loaded != null)
                TextButton.icon(
                  key: ValueKey('testing-doc-zoom-$index'),
                  onPressed: () => _showZoomDialog(loaded),
                  icon: const Icon(Icons.zoom_in_outlined, size: 17),
                  label: const Text('Zoom'),
                ),
              if (widget.onDownloadFile != null && loaded != null)
                TextButton.icon(
                  key: ValueKey('testing-doc-download-$index'),
                  onPressed: () => widget.onDownloadFile!(loaded),
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: const Text('Download'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreviewFrame(
    TestingServiceDocumentRef doc,
    int index,
    ({String name, String contentType, Uint8List bytes})? loaded,
    bool loading,
    String? error,
  ) {
    final previewHeight = widget.compact ? 150.0 : 190.0;
    if (loaded != null) {
      return Material(
        color: const Color(0xFFF3F6F4),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showZoomDialog(loaded),
          child: SizedBox(
            width: double.infinity,
            height: previewHeight,
            child: Image.memory(
              loaded.bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Unable to render image preview.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7D83)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5B8B8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9E2A2B)),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: ValueKey('testing-doc-retry-$index'),
              onPressed: () => _fetchDocument(doc, openLightboxWhenDone: false),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry preview'),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : OutlinedButton(
                onPressed: () =>
                    _fetchDocument(doc, openLightboxWhenDone: false),
                child: const Text('Load image preview'),
              ),
      ),
    );
  }

  Widget _buildPdfCardRow(
    TestingServiceDocumentRef doc,
    int index,
    bool loading,
    String? error,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8F4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.picture_as_pdf_outlined,
                color: Color(0xFF8A6810),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'PDF document attached (${math.max(1, (doc.size / 1024).round())} KB)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D343C),
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: ValueKey('testing-doc-open-$index'),
                onPressed: loading
                    ? null
                    : () => _fetchDocument(doc, openLightboxWhenDone: true),
                icon: loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 16),
                label: Text(
                  widget.onDownloadFile != null
                      ? 'Open / Download'
                      : 'Verify PDF',
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9E2A2B)),
          ),
        ],
      ],
    );
  }
}
