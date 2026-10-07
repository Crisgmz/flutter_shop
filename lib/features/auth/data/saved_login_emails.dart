import 'dart:convert';

import '../../../core/web/kv_store.dart';

// Correos que ya entraron en este navegador, para no tener que escribirlos en
// cada inicio de sesión. SOLO el correo: la clave nunca se guarda.

const _key = 'busipos.saved_login_emails';

/// Cuántos correos se recuerdan; el más viejo sale cuando entra uno nuevo.
const _maxEmails = 10;

/// Del más reciente al más viejo.
List<String> readSavedLoginEmails() {
  final raw = kvRead(_key);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList(growable: false);
  } catch (_) {
    return const [];
  }
}

/// Lo pone de primero. Se llama después de entrar con éxito, para no guardar
/// correos mal escritos.
void rememberLoginEmail(String email) {
  final normalized = email.trim().toLowerCase();
  if (normalized.isEmpty) return;
  final emails = [
    normalized,
    ...readSavedLoginEmails().where((e) => e != normalized),
  ].take(_maxEmails).toList();
  kvWrite(_key, jsonEncode(emails));
}

/// La X de la lista: ese correo ya no se sugiere.
void forgetLoginEmail(String email) {
  final normalized = email.trim().toLowerCase();
  final emails =
      readSavedLoginEmails().where((e) => e != normalized).toList();
  if (emails.isEmpty) {
    kvRemove(_key);
  } else {
    kvWrite(_key, jsonEncode(emails));
  }
}
