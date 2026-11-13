export 'admin_unload_guard_stub.dart'
    if (dart.library.html) 'admin_unload_guard_web.dart';

/// Registers a browser `beforeunload` prompt that fires while [shouldWarn]
/// returns true, and returns a handle to pass back to the remover. Non-web
/// builds get the stub, which does nothing and returns null.
typedef UnloadGuardRegistrar = Object? Function(bool Function() shouldWarn);

/// Removes a guard previously registered with an [UnloadGuardRegistrar].
typedef UnloadGuardRemover = void Function(Object? handle);
