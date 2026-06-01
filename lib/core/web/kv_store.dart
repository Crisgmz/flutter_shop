// Almacén clave→valor síncrono y cross-platform para persistir borradores.
//
// En Flutter web usa `window.localStorage` (kv_store_web.dart): sobrevive
// recargas de página (F5 / banner "Actualizar"). En mobile/desktop usa un
// mapa en memoria (kv_store_stub.dart) — ahí los borradores ya sobreviven la
// navegación vía los providers de Riverpod, y persistir a disco no es el caso
// de uso que perseguimos.
export 'kv_store_stub.dart' if (dart.library.js_interop) 'kv_store_web.dart';
