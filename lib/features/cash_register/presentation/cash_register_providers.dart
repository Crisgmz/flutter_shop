import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/cash_register_repository.dart';

final cashRegisterRepositoryProvider = Provider<CashRegisterRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return CashRegisterRepository(client);
});

final cashRegisterDataProvider = FutureProvider<CashRegisterData>((ref) async {
  final repository = ref.watch(cashRegisterRepositoryProvider);
  return repository.fetchData();
});
