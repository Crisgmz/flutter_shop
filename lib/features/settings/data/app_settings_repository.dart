// AppSettingsRepository: lectura y escritura del singleton `app_settings`.
//
// Patrón:
//   - fetch(): SELECT * FROM app_settings WHERE id = 1
//   - updateField(column, value): UPDATE one column. Auto-save por campo.
//   - updatePatch(patch): UPDATE varias columnas en una sola RPC.
//   - fetchAuditLog: lee últimas N entradas de `app_settings_audit` (admin).
//
// Errores:
//   - Si no hay sesión, lanza Exception.
//   - Si el RLS rechaza el update (no admin), Supabase lanza PostgrestException
//     que se propaga.

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';

class AppSettingsRepository {
  AppSettingsRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'app_settings';
  static const _auditTable = 'app_settings_audit';

  /// Bucket compartido para assets globales de la empresa (logo, sello, firma).
  /// Reutiliza `product_images` (público + RLS para autenticados); los archivos
  /// de empresa se guardan bajo el prefijo `_company/` para diferenciarlos.
  static const _assetsBucket = 'product_images';

  /// Sube los bytes del logo de la empresa a Storage y devuelve el URL público.
  /// El path se construye como `_company/logo-<timestamp>.<ext>`.
  Future<String> uploadCompanyLogo({
    required Uint8List bytes,
    required String extension,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '_company/logo-$timestamp.$extension';

    final storage = _client.storage.from(_assetsBucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: _contentTypeFor(extension),
      ),
    );
    return storage.getPublicUrl(path);
  }

  String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// Devuelve la fila singleton. Si por alguna razón no existe, llama a la
  /// función de inicialización y reintenta.
  Future<AppSettings> fetch() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión para leer la configuración.');
    }

    // Multi-tenant: la RLS de `app_settings` ya garantiza que el usuario
    // solo ve la fila de SU empresa (la asociada vía `has_company_access`).
    // No filtramos por `id` aquí.
    final rows = await _client.from(_table).select().limit(1);

    if (rows.isEmpty) {
      // Sin fila visible: puede pasar para usuarios nuevos antes del
      // bootstrap (fase 2 onboarding) o cuentas en estado raro. Devolvemos
      // defaults locales en vez de fallar.
      return const AppSettings(<String, dynamic>{});
    }

    return AppSettings(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Actualiza una sola columna y devuelve la fila completa actualizada.
  /// Lanza si el RLS bloquea (no admin).
  Future<AppSettings> updateField(String column, dynamic value) async {
    return updatePatch({column: value});
  }

  /// Actualiza múltiples columnas en un solo UPDATE.
  Future<AppSettings> updatePatch(Map<String, dynamic> patch) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión para editar la configuración.');
    }
    if (patch.isEmpty) {
      return fetch();
    }

    final payload = <String, dynamic>{
      ...patch,
      'updated_by': user.id,
    };

    // Multi-tenant: la RLS limita el UPDATE a la fila de la empresa del
    // usuario. Usamos un filtro siempre-verdadero (`id > 0`) para satisfacer
    // la política de Supabase que exige WHERE en updates.
    final rows = await _client
        .from(_table)
        .update(payload)
        .gt('id', 0)
        .select()
        .limit(1);

    if (rows.isEmpty) {
      throw Exception(
        'No se pudo actualizar la configuración. Verifica permisos.',
      );
    }
    return AppSettings(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Devuelve las últimas N entradas de auditoría (solo admin por RLS).
  Future<List<AppSettingsAuditEntry>> fetchAuditLog({int limit = 100}) async {
    final rows = await _client
        .from(_auditTable)
        .select()
        .order('changed_at', ascending: false)
        .limit(limit);

    return rows
        .map(
          (item) => AppSettingsAuditEntry.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }
}
