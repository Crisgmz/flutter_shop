import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/branches_repository.dart';

final branchesSearchProvider = StateProvider<String>((ref) => '');
final branchesShowInactiveProvider = StateProvider<bool>((ref) => false);
final selectedBranchIdProvider = StateProvider<String?>((ref) => null);

final branchesRepositoryProvider = Provider<BranchesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return BranchesRepository(client);
});

final branchesListProvider = FutureProvider<List<BranchEntity>>((ref) async {
  final repository = ref.watch(branchesRepositoryProvider);
  return repository.fetchBranches();
});

final branchMembersProvider = FutureProvider<List<BranchMember>>((ref) async {
  final branchId = ref.watch(selectedBranchIdProvider);
  if (branchId == null || branchId.isEmpty) return const [];
  final repository = ref.watch(branchesRepositoryProvider);
  return repository.fetchBranchMembers(branchId);
});

final branchUsersProvider = FutureProvider<List<BranchUserOption>>((ref) async {
  final repository = ref.watch(branchesRepositoryProvider);
  return repository.fetchActiveUsers();
});
