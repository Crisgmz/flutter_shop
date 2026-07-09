// Punto de entrada cross-platform para cambiar el favicon de la pestaña.
// En Flutter web carga favicon_web.dart (JS interop real).
// En mobile/desktop carga favicon_stub.dart (no-op).
export 'favicon_stub.dart' if (dart.library.js_interop) 'favicon_web.dart';
