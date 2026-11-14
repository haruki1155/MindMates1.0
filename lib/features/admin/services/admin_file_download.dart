export 'admin_file_download_stub.dart'
    if (dart.library.html) 'admin_file_download_web.dart';

/// Signature shared by the real downloader and test fakes.
typedef AdminFileDownloader =
    void Function(String fileName, List<int> bytes, String mimeType);
