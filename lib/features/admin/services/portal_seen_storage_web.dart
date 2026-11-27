import 'package:web/web.dart' as web;

String? readPortalSeenStorage(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writePortalSeenStorage(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {
    // Ignore storage quota or private browsing errors cleanly.
  }
}
