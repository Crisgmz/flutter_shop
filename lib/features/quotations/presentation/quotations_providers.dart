import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/quotations_models.dart';
import '../data/quotations_repository.dart';

final quotationsRepositoryProvider = Provider<QuotationsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return QuotationsRepository(client);
});

final quotationsSearchProvider = StateProvider<String>((ref) => '');

/// Snapshot del borrador de una cotización NUEVA (no aplica al editar una
/// existente, que se carga del servidor). Se guarda al salir de la pantalla
/// y se restaura al volver, para no perder el borrador al navegar.
class QuotationDraft {
  const QuotationDraft({
    this.items = const [],
    this.clientId,
    this.validUntil,
    this.status,
    this.notes = '',
  });

  final List<QuoteDraftLine> items;
  final String? clientId;
  final DateTime? validUntil;
  final QuoteStatus? status;
  final String notes;

  bool get isEmpty => items.isEmpty && notes.isEmpty && clientId == null;
}

final quotationDraftProvider =
    StateProvider<QuotationDraft>((ref) => const QuotationDraft());

final quotationProductsProvider = FutureProvider<List<QuoteCatalogProduct>>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchProducts();
});

final quotationClientsProvider = FutureProvider<List<QuoteClientOption>>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchClients();
});

final quotationDetailProvider = FutureProvider.family<QuoteDetail, String>((
  ref,
  quoteId,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchQuoteDetail(quoteId);
});

final quotationsFoundationProvider = FutureProvider<QuoteFoundationBundle>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.loadFoundation();
});
