import 'package:url_launcher/url_launcher.dart';
import '../models/announcement.dart';

typedef AnnouncementSourceLauncher = Future<bool> Function(Uri uri);
Future<bool> openAnnouncementSource(Uri uri) async {
  if (announcementHttpUri(uri) == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
