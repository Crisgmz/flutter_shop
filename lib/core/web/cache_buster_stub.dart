/// Stub para plataformas no-web (mobile/desktop). No hace nada porque
/// no hay cache de Service Worker ni Cache Storage que limpiar.
Future<void> clearWebCachesAndReload() async {
  // no-op
}
