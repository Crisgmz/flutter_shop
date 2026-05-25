// Punto de entrada cross-platform para limpiar el caché del browser.
// En Flutter web carga cache_buster_web.dart (JS interop real).
// En mobile/desktop carga cache_buster_stub.dart (no-op).
export 'cache_buster_stub.dart'
    if (dart.library.js_interop) 'cache_buster_web.dart';
