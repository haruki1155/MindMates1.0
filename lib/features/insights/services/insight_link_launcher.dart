import 'package:url_launcher/url_launcher.dart';
import '../models/insights_models.dart';

typedef InsightSourceLauncher = Future<bool> Function(Uri uri);
Future<bool> openInsightSource(Uri uri) async {
  if (validInsightSourceUri(uri.toString()) == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
