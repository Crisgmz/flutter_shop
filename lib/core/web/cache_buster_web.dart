import 'dart:async';
import 'dart:js_interop';

/// Limpia agresivamente el caché del browser y recarga la app:
///   1. Borra todas las entradas de Cache Storage (`caches.delete(...)`).
///   2. Desregistra todos los Service Workers activos.
///   3. Conserva los tokens de auth en localStorage (claves `sb-*-auth-token`)
///      para no patear al usuario fuera de la sesión.
///   4. Recarga con `?_=<timestamp>` para forzar bypass de proxies/CDNs.
///
/// Solo se ejecuta en Flutter web — en mobile/desktop es no-op (stub).
Future<void> clearWebCachesAndReload() async {
  try {
    await _clearCacheStorage();
  } catch (_) {
    // Continuar aunque falle alguna parte — no queremos bloquear el reload.
  }
  try {
    await _unregisterServiceWorkers();
  } catch (_) {}
  _hardReload();
}

@JS('window.caches')
external _CacheStorageJS? get _caches;

@JS('navigator.serviceWorker')
external _SwContainerJS? get _swContainer;

@JS('window.location')
external _LocationJS get _location;

@JS('Date.now')
external double _dateNow();

extension type _CacheStorageJS._(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSString>> keys();
  external JSPromise<JSBoolean> delete(JSString key);
}

extension type _SwContainerJS._(JSObject _) implements JSObject {
  external JSPromise<JSArray<_SwRegistrationJS>> getRegistrations();
}

extension type _SwRegistrationJS._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> unregister();
}

extension type _LocationJS._(JSObject _) implements JSObject {
  external String get origin;
  external String get pathname;
  external set href(String value);
}

Future<void> _clearCacheStorage() async {
  final cs = _caches;
  if (cs == null) return;
  final keysJs = await cs.keys().toDart;
  final keys = keysJs.toDart;
  for (final k in keys) {
    await cs.delete(k).toDart;
  }
}

Future<void> _unregisterServiceWorkers() async {
  final sw = _swContainer;
  if (sw == null) return;
  final regsJs = await sw.getRegistrations().toDart;
  final regs = regsJs.toDart;
  for (final r in regs) {
    await r.unregister().toDart;
  }
}

void _hardReload() {
  final loc = _location;
  final stamp = _dateNow().toInt();
  loc.href = '${loc.origin}${loc.pathname}?_=$stamp';
}
