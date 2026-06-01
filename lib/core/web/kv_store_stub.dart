// Stub para mobile/desktop: almacén en memoria (no persiste a disco).
// Mantiene la misma API que la versión web para que el código de llamada sea
// idéntico en todas las plataformas.
final Map<String, String> _mem = <String, String>{};

String? kvRead(String key) => _mem[key];

void kvWrite(String key, String value) => _mem[key] = value;

void kvRemove(String key) => _mem.remove(key);
