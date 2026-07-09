// Implementación web: cambia el favicon de la pestaña en runtime según la
// empresa logueada (multi-tenant sobre un mismo frontend). El <title> lo maneja
// Flutter vía `MaterialApp.title`; aquí solo tocamos el ícono, que Flutter no
// gestiona.
//
// Nota: esto cambia el ícono de la PESTAÑA del navegador. El ícono de la PWA
// ya instalada viene de `manifest.json` (estático) y no puede cambiarse por
// empresa en caliente.
import 'dart:js_interop';

@JS('document')
external _DocumentJS get _document;

extension type _DocumentJS._(JSObject _) implements JSObject {
  external _ElementJS? querySelector(String selectors);
  external _ElementJS createElement(String tag);
  external _ElementJS? get head;
}

extension type _ElementJS._(JSObject _) implements JSObject {
  external void setAttribute(String name, String value);
  external void appendChild(_ElementJS child);
}

/// Fija el favicon de la pestaña a [url]. Si es null/vacío, restaura el ícono
/// por defecto de la plataforma (`favicon.png`, bundleado en `web/`).
void setBrowserFavicon(String? url) {
  final href = (url == null || url.trim().isEmpty) ? 'favicon.png' : url.trim();
  final doc = _document;

  var link = doc.querySelector("link[rel~='icon']");
  if (link == null) {
    final created = doc.createElement('link');
    created.setAttribute('rel', 'icon');
    doc.head?.appendChild(created);
    link = created;
  }
  link.setAttribute('href', href);

  // Si existe un apple-touch-icon (iOS "Agregar a inicio"), lo alineamos.
  doc.querySelector("link[rel='apple-touch-icon']")?.setAttribute('href', href);
}
