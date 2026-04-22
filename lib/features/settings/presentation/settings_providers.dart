import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SettingsRepository(client);
});

final settingsDataProvider = FutureProvider<SettingsData>((ref) async {
  final repository = ref.watch(settingsRepositoryProvider);
  return repository.fetchSettings();
});

final businessProfileProvider =
    FutureProvider<BusinessProfile?>((ref) async {
  final repository = ref.watch(settingsRepositoryProvider);
  return repository.fetchBusinessProfile();
});
