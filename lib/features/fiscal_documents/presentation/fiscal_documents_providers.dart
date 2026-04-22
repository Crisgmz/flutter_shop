import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
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

final fiscalDocumentsProvider =
    FutureProvider<List<FiscalDocument>>((ref) async {
  final repo = ref.watch(fiscalDocumentsRepositoryProvider);
  final statusFilter = ref.watch(fiscalStatusFilterProvider);
  final receiptTypeFilter = ref.watch(fiscalReceiptTypeFilterProvider);
  final dateFrom = ref.watch(fiscalDateFromProvider);
  final dateTo = ref.watch(fiscalDateToProvider);
  return repo.fetchDocuments(
    statusFilter: statusFilter,
    receiptTypeFilter: receiptTypeFilter,
    from: dateFrom,
    to: dateTo,
  );
});

final fiscalDocumentDetailProvider =
    FutureProvider.family<FiscalDocument?, String>((ref, id) async {
  final repo = ref.watch(fiscalDocumentsRepositoryProvider);
  return repo.fetchDocument(id);
});
