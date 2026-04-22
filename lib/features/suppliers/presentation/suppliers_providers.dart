import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/suppliers_repository.dart';

final suppliersSearchProvider = StateProvider<String>((ref) => '');
final suppliersShowInactiveProvider = StateProvider<bool>((ref) => false);

final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SuppliersRepository(client);
});

final suppliersListProvider = FutureProvider<List<SupplierEntity>>((ref) async {
  final repository = ref.watch(suppliersRepositoryProvider);
  return repository.fetchSuppliers();
});
