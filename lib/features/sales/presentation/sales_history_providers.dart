import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/sales_history_repository.dart';

final salesHistoryRepositoryProvider =
    Provider<SalesHistoryRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SalesHistoryRepository(client);
});

/// Filtros activos en el historial (fecha + búsqueda + status).
final salesHistoryFilterProvider =
    StateProvider<SalesHistoryFilter>((ref) {
  return const SalesHistoryFilter();
});

/// Página actual (0-indexada). Cambia con los botones de paginación.
final salesHistoryPageIndexProvider = StateProvider<int>((ref) => 0);

/// Datos de la página actual (re-fetch cuando cambian filtros o índice).
final salesHistoryPageProvider =
    FutureProvider.autoDispose<SalesHistoryPage>((ref) async {
  final repo = ref.watch(salesHistoryRepositoryProvider);
  final filter = ref.watch(salesHistoryFilterProvider);
  final index = ref.watch(salesHistoryPageIndexProvider);
  return repo.fetchPage(pageIndex: index, filter: filter);
});

/// Clave del detalle: id del documento + si es una devolución. El historial es
/// unificado, así que el id solo no alcanza para saber en qué tabla buscar.
typedef SalesHistoryDetailKey = ({String id, bool isReturn});

/// Detalle bajo demanda (venta o devolución).
final salesHistoryDetailProvider = FutureProvider.autoDispose
    .family<SalesHistoryDetail?, SalesHistoryDetailKey>((ref, key) async {
  final repo = ref.watch(salesHistoryRepositoryProvider);
  return key.isReturn
      ? repo.fetchReturnDetail(key.id)
      : repo.fetchDetail(key.id);
});
