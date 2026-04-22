class Env {
  // Local fallback for development only. Replace/remove for production.
  static const _devSupabaseUrl = 'https://dybodnxsvzwkzauofkza.supabase.co';
  static const _devSupabasePublishableKey =
      'sb_publishable_ZFqbCM83-7iI0uuSHUTKKQ_ithcc-XB';

  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: _devSupabaseUrl);
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: _devSupabasePublishableKey,
  );

  static String get supabaseAnonKey {
    if (_supabaseAnonKey.isNotEmpty) return _supabaseAnonKey;
    return _supabasePublishableKey;
  }

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
