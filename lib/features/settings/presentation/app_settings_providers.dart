// Providers Riverpod para `app_settings` (PRD 06).
//
// - appSettingsRepositoryProvider: instancia del repo.
// - appSettingsProvider: AsyncNotifier<AppSettings>. Cachea en memoria,
//   expone updateField/updatePatch con actualización optimista + rollback.
// - appSettingsAuditProvider: últimas entradas de auditoría (admin).
// - Selectores tipados para hot-paths (currency, prefijos, flags).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/app_settings.dart';
import '../data/app_settings_repository.dart';

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AppSettingsRepository(client);
});

class AppSettingsController extends AsyncNotifier<AppSettings> {
  AppSettingsRepository get _repo => ref.read(appSettingsRepositoryProvider);

  @override
  Future<AppSettings> build() {
    return _repo.fetch();
  }

  /// Refresh manual (útil tras un evento externo o cambio de sesión).
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetch);
  }

  /// Auto-save por campo. Aplica optimismo: refleja el cambio en memoria
  /// antes del UPDATE; si el server falla, revierte y re-lanza el error.
  Future<void> updateField(String column, dynamic value) async {
    await updatePatch({column: value});
  }

  /// Auto-save de múltiples campos.
  Future<void> updatePatch(Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final previous = state.valueOrNull;
    if (previous != null) {
      state = AsyncValue.data(previous.copyWith(patch));
    }

    try {
      final updated = await _repo.updatePatch(patch);
      state = AsyncValue.data(updated);
    } catch (error, stack) {
      if (previous != null) {
        state = AsyncValue.data(previous);
      }
      if (kDebugMode) {
        debugPrint('AppSettings updatePatch error: $error');
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

/// Lista de auditoría (lazy, solo se dispara cuando una pantalla la observa).
final appSettingsAuditProvider =
    FutureProvider.autoDispose<List<AppSettingsAuditEntry>>((ref) async {
  final repo = ref.watch(appSettingsRepositoryProvider);
  return repo.fetchAuditLog(limit: 200);
});

// ─── Selectores tipados (hot-path) ─────────────────────────────────────────
//
// Pensados para que widgets en módulos críticos (recibo, venta, panel)
// puedan suscribirse solo al campo que les importa, sin re-build cuando
// cambia un campo no relacionado.

T _withSettings<T>(Ref ref, T Function(AppSettings settings) selector,
    {required T fallback}) {
  final value = ref.watch(appSettingsProvider).valueOrNull;
  if (value == null) return fallback;
  return selector(value);
}

final currencySymbolProvider = Provider<String>((ref) {
  return _withSettings(ref, (s) => s.currencySymbol, fallback: r'RD$');
});

final currencyDecimalsProvider = Provider<int>((ref) {
  return _withSettings(ref, (s) => s.currencyDecimals, fallback: 2);
});

final prefixSaleProvider = Provider<String>((ref) {
  return _withSettings(ref, (s) => s.prefixSale, fallback: 'FA');
});

final prefixCreditNoteProvider = Provider<String>((ref) {
  return _withSettings(ref, (s) => s.prefixCreditNote, fallback: 'NC');
});

final disableQuickSaleProvider = Provider<bool>((ref) {
  return _withSettings(ref, (s) => s.saleDisableQuickSale, fallback: false);
});

final printAfterSaleProvider = Provider<bool>((ref) {
  return _withSettings(ref, (s) => s.receiptPrintAfterSale, fallback: true);
});
