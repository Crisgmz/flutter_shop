import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/petty_cash_repository.dart';

final pettyCashRepositoryProvider = Provider<PettyCashRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return PettyCashRepository(client);
});

final pettyCashDataProvider = FutureProvider<PettyCashData>((ref) async {
  final repo = ref.watch(pettyCashRepositoryProvider);
  return repo.fetchData();
});
