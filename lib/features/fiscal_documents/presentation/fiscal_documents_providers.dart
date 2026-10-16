import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/fiscal_consumo_summary.dart';
import '../data/fiscal_documents_repository.dart';

final fiscalDocumentsRepositoryProvider =
    Provider<FiscalDocumentsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return FiscalDocumentsRepository(client);
});

final fiscalStatusFilterProvider = StateProvider<String?>((ref) => null);
final fiscalReceiptTypeFilterProvider = StateProvider<String?>((ref) => null);
final fiscalDateFromProvider = StateProvider<DateTime?>((ref) => null);
final fiscalDateToProvider = StateProvider<DateTime?>((ref) => null);

enum FiscalDocumentsView { summary, detail }

final fiscalViewProvider =
    StateProvider<FiscalDocumentsView>((ref) => FiscalDocumentsView.detail);

/// Rango del resumen: el elegido o, si no hay, el mes en curso (el resumen
/// de la DGII es mensual).
final fiscalSummaryRangeProvider = Provider<({DateTime from, DateTime to})>((ref) {
  final from = ref.watch(fiscalDateFromProvider);
  final to = ref.watch(fiscalDateToProvider);
  final now = DateTime.now();
  return (
    from: from ?? DateTime(now.year, now.month, 1),
    to: to ?? DateTime(now.year, now.month, now.day),
  );
});

final fiscalDocumentsProvider =
    FutureProvider<List<FiscalDocument>>((ref) async {
  final repo = ref.watch(fiscalDocumentsRepositoryProvider);
  final statusFilter = ref.watch(fiscalStatusFilterProvider);
  final receiptTypeFilter = ref.watch(fiscalReceiptTypeFilterProvider);
  final dateFrom = ref.watch(fiscalDateFromProvider);
  final dateTo = ref.watch(fiscalDateToProvider);
  // Con rango de fechas trae todos los del rango (la exportación debe ir
  // completa); sin rango, los 100 más recientes como siempre.
  final hasRange = dateFrom != null || dateTo != null;
  return repo.fetchDocuments(
    statusFilter: statusFilter,
    receiptTypeFilter: receiptTypeFilter,
    from: dateFrom,
    to: dateTo,
    limit: hasRange ? null : 100,
  );
});

/// "Resumen Facturas Consumo": todos los comprobantes de consumo del rango,
/// sin mirar los filtros de tipo y estado del detallado.
final fiscalConsumoSummaryProvider =
    FutureProvider<FiscalConsumoSummary>((ref) async {
  final repo = ref.watch(fiscalDocumentsRepositoryProvider);
  final range = ref.watch(fiscalSummaryRangeProvider);
  final docs = await repo.fetchDocuments(
    receiptTypeFilter: 'consumer_final',
    from: range.from,
    to: range.to,
    limit: null,
  );
  return FiscalConsumoSummary.fromDocuments(
    docs,
    from: range.from,
    to: range.to,
  );
});

final fiscalDocumentDetailProvider =
    FutureProvider.family<FiscalDocument?, String>((ref, id) async {
  final repo = ref.watch(fiscalDocumentsRepositoryProvider);
  return repo.fetchDocument(id);
});
