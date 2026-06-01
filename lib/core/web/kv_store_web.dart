// Implementación web: persiste en `window.localStorage` (síncrono).
// Sobrevive recargas de la página, así que los borradores en curso no se
// pierden al hacer F5 o al aceptar el banner "Actualizar".
import 'dart:js_interop';

@JS('window.localStorage')
external _Storage get _localStorage;

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

String? kvRead(String key) {
  try {
    return _localStorage.getItem(key);
  } catch (_) {
    // localStorage puede no estar disponible (modo privado, cuota llena).
    return null;
  }
}

void kvWrite(String key, String value) {
  try {
    _localStorage.setItem(key, value);
  } catch (_) {}
}

void kvRemove(String key) {
  try {
    _localStorage.removeItem(key);
  } catch (_) {}
}
