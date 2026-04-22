import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/expenses_repository.dart';

final expensesSearchProvider = StateProvider<String>((ref) => '');

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ExpensesRepository(client);
});

final expensesListProvider = FutureProvider<List<ExpenseEntity>>((ref) async {
  final repository = ref.watch(expensesRepositoryProvider);
  return repository.fetchExpenses();
});

final expenseSuppliersProvider = FutureProvider<List<ExpenseSupplier>>((
  ref,
) async {
  final repository = ref.watch(expensesRepositoryProvider);
  return repository.fetchSuppliers();
});
