/// Supported client download formats for a complete Firestore backup.
enum BackupExportFormat {
  csv('csv', 'backup.zip', 'application/zip'),
  xlsx('xlsx', 'backup.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

  const BackupExportFormat(this.wireName, this.defaultExtensionHint, this.mimeType);

  final String wireName;
  final String defaultExtensionHint;
  final String mimeType;
}

/// Progress update emitted while paging through `exportFirestoreBackupPage`.
class BackupExportProgress {
  const BackupExportProgress({
    required this.pagesLoaded,
    required this.documentsLoaded,
    required this.collectionsDiscovered,
  });

  final int pagesLoaded;
  final int documentsLoaded;
  final int collectionsDiscovered;
}

/// A single Firestore document serialized by the server for backup export.
class BackupDocumentRecord {
  const BackupDocumentRecord({
    required this.documentId,
    required this.documentPath,
    required this.collectionPath,
    required this.collectionKey,
    this.parentCollection,
    this.parentDocumentId,
    this.createTime,
    this.updateTime,
    this.fields = const <String, Object?>{},
  });

  final String documentId;
  final String documentPath;
  final String collectionPath;
  final String collectionKey;
  final String? parentCollection;
  final String? parentDocumentId;
  final String? createTime;
  final String? updateTime;
  final Map<String, Object?> fields;

  factory BackupDocumentRecord.fromJson(Map<String, dynamic> json) {
    final documentId = json['documentId']?.toString() ?? '';
    final documentPath = json['documentPath']?.toString() ?? '';
    final collectionPath = json['collectionPath']?.toString() ?? '';
    final collectionKey = json['collectionKey']?.toString() ?? '';
    if (documentId.isEmpty ||
        documentPath.isEmpty ||
        collectionPath.isEmpty ||
        collectionKey.isEmpty) {
      throw const FormatException(
        'Incomplete backup document metadata received from server.',
      );
    }
    final rawFields = json['fields'];
    final fields = rawFields is Map
        ? rawFields.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    return BackupDocumentRecord(
      documentId: documentId,
      documentPath: documentPath,
      collectionPath: collectionPath,
      collectionKey: collectionKey,
      parentCollection: _nullableText(json['parentCollection']),
      parentDocumentId: _nullableText(json['parentDocumentId']),
      createTime: _nullableText(json['createTime']),
      updateTime: _nullableText(json['updateTime']),
      fields: fields,
    );
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

/// One logical Firestore collection (or subcollection group) to export.
class BackupCollectionDataset {
  const BackupCollectionDataset({
    required this.collectionKey,
    required this.collectionPaths,
    required this.documents,
  });

  final String collectionKey;
  final List<String> collectionPaths;
  final List<BackupDocumentRecord> documents;
}

/// Complete, verified Firestore backup snapshot assembled across all pages.
class BackupExportDataset {
  const BackupExportDataset({
    required this.exportId,
    required this.exportedAt,
    required this.collections,
  });

  final String exportId;
  final DateTime exportedAt;
  final List<BackupCollectionDataset> collections;

  int get totalCollections => collections.length;

  int get totalDocuments =>
      collections.fold(0, (sum, col) => sum + col.documents.length);
}
