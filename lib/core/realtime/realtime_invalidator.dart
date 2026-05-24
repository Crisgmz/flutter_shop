// Servicio que suscribe canales Postgres Realtime de Supabase y, ante
// cada evento, invalida los providers de Riverpod correspondientes para
// que la UI se actualice sola sin que el usuario tenga que refrescar.
//
// Patrón: por cada (tabla → set de providers) configurado en
// `_table_to_providers`, se abre un channel filtrado por la sucursal
// actual (branch_id=eq.<id>) y se invalidan los providers asociados al
// recibir INSERT/UPDATE/DELETE.
//
// Lifecycle:
//   - Se inicia desde [_RealtimeBootstrap] (lib/app/app.dart) cuando hay
//     branch_id disponible.
//   - Cuando el usuario cambia de sucursal, [reattach] re-suscribe con
//     el branch nuevo cancelando los canales viejos.
//   - Al hacer logout o cerrar la pestaña, [stop] cierra todo.
//
// Diseño:
//   - Una instancia por usuario (singleton del scope Riverpod).
//   - Los canales se nombran `realtime:<tabla>:<branchId>` para que
//     Supabase los multiplexee correctamente.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/cash_register/presentation/cash_register_providers.dart';
import '../../features/clients/presentation/clients_providers.dart';
import '../../features/cobros/presentation/cobros_providers.dart';
import '../../features/dashboard/presentation/dashboard_providers.dart';
import '../../features/inventory/presentation/inventory_providers.dart';
import '../../features/sales/presentation/sales_history_providers.dart';
import '../../features/sales/presentation/sales_providers.dart';

/// Lista de providers que se invalidan ante un evento de cada tabla.
///
/// Mantener esto en un map único es a propósito: cuando agregás una tabla
/// nueva al realtime (en la migration SQL), solo hay un lugar acá donde
/// declarar qué providers se enteran.
typedef _ProviderList = List<ProviderOrFamily>;

class RealtimeInvalidator {
  RealtimeInvalidator(this._ref);

  final Ref _ref;
  final Map<String, RealtimeChannel> _channels = {};
  String? _attachedBranchId;

  /// Suscribe los canales filtrados por `branchId`. Si ya hay
  /// suscripciones activas para otro branch, las cierra y reabre.
  Future<void> attach(String? branchId) async {
    if (branchId == null || branchId.isEmpty) {
      await stop();
      return;
    }
    if (_attachedBranchId == branchId && _channels.isNotEmpty) {
      return; // Ya suscriptos al branch correcto.
    }

    await stop();
    _attachedBranchId = branchId;

    final client = _ref.read(supabaseClientProvider);

    for (final entry in _tableToProviders.entries) {
      final table = entry.key;
      final providers = entry.value;

      final channel = client
          .channel('realtime:$table:$branchId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'branch_id',
              value: branchId,
            ),
            callback: (_) => _invalidate(providers, table),
          )
          .subscribe();
      _channels[table] = channel;
    }

    if (kDebugMode) {
      debugPrint(
        'RealtimeInvalidator: attached ${_channels.length} channels '
        'for branch $branchId',
      );
    }
  }

  /// Equivalente a [attach] tras un cambio de sucursal.
  Future<void> reattach(String? newBranchId) => attach(newBranchId);

  /// Cierra todas las suscripciones.
  Future<void> stop() async {
    if (_channels.isEmpty) return;
    final client = _ref.read(supabaseClientProvider);
    for (final channel in _channels.values) {
      try {
        await client.removeChannel(channel);
      } catch (e) {
        if (kDebugMode) debugPrint('RealtimeInvalidator: unsubscribe error: $e');
      }
    }
    _channels.clear();
    _attachedBranchId = null;
  }

  void _invalidate(_ProviderList providers, String table) {
    for (final p in providers) {
      _ref.invalidate(p);
    }
    if (kDebugMode) {
      debugPrint(
        'RealtimeInvalidator: $table changed → invalidated ${providers.length} providers',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Mapeo tabla → providers a invalidar
  //
  // Mantener sincronizado con la migration que habilita realtime
  // (supabase/sql-next/20260520_24_*.sql y 20260522_41_*.sql).
  // ──────────────────────────────────────────────────────────────────────
  static final Map<String, _ProviderList> _tableToProviders = {
    'products': [
      inventoryProductsProvider,
      salesProductsProvider,
    ],
    'product_categories': [
      inventoryCategoriesProvider,
    ],
    'sales': [
      salesHistoryPageProvider,
      dashboardKpisProvider,
      dashboardChartProvider,
      dashboardCloseoutProvider,
      cobrosReceivablesProvider,
    ],
    'payments': [
      cobrosPaymentsProvider,
      cobrosReceivablesProvider,
      cashRegisterDataProvider,
      dashboardCloseoutProvider,
    ],
    'cash_sessions': [
      cashRegisterDataProvider,
      dashboardCloseoutProvider,
    ],
    'cash_register_movements': [
      cashRegisterDataProvider,
    ],
    'clients': [
      clientsListProvider,
      salesClientsProvider,
      cobrosReceivablesProvider,
    ],
    'returns': [
      salesHistoryPageProvider,
      dashboardCloseoutProvider,
    ],
  };
}

/// Provider singleton de RealtimeInvalidator (se crea al primer uso).
final realtimeInvalidatorProvider = Provider<RealtimeInvalidator>((ref) {
  final invalidator = RealtimeInvalidator(ref);
  ref.onDispose(invalidator.stop);
  return invalidator;
});
