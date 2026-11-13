/// There is no page to unload outside the browser, so this is a no-op.
Object? registerUnloadGuard(bool Function() shouldWarn) => null;

void removeUnloadGuard(Object? handle) {}
