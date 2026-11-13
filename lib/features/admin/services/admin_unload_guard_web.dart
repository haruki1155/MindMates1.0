import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Asks the browser to confirm a tab close or refresh while [shouldWarn] is
/// true — activation codes are shown once, so an in-flight import or an
/// undownloaded slip file must not be lost to a stray Ctrl+W.
Object? registerUnloadGuard(bool Function() shouldWarn) {
  void handler(web.Event event) {
    if (!shouldWarn()) return;
    event.preventDefault();
    // Legacy browsers key off a non-empty returnValue; the text itself is
    // ignored by every current one, which shows its own copy.
    (event as web.BeforeUnloadEvent).returnValue = 'true';
  }

  final listener = handler.toJS;
  web.window.addEventListener('beforeunload', listener);
  return listener;
}

void removeUnloadGuard(Object? handle) {
  if (handle == null) return;
  web.window.removeEventListener('beforeunload', handle as JSFunction);
}
