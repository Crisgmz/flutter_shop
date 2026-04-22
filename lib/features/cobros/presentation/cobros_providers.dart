import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/cobros_repository.dart';

final cobrosSearchProvider = StateProvider<String>((ref) => '');

final cobrosRepositoryProvider = Provider<CobrosRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return CobrosRepository(client);
});

final cobrosReceivablesProvider = FutureProvider<List<ReceivableSale>>((
  ref,
) async {
  final repository = ref.watch(cobrosRepositoryProvider);
  return repository.fetchReceivables();
});

final cobrosPaymentsProvider = FutureProvider<List<ReceivedPayment>>((
  ref,
) async {
  final repository = ref.watch(cobrosRepositoryProvider);
  return repository.fetchReceivedPayments();
});
