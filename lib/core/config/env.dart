class Env {
  // Local fallback for development only.
  static const _devSupabaseUrl = 'https://dybodnxsvzwkzauofkza.supabase.co';
  static const _devSupabasePublishableKey =
      'sb_publishable_ZFqbCM83-7iI0uuSHUTKKQ_ithcc-XB';

  // Treat an empty dart-define the same as "not defined" → fall back to dev value.
  static const _rawSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseUrl =
      _rawSupabaseUrl != '' ? _rawSupabaseUrl : _devSupabaseUrl;

  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const _rawPublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _supabasePublishableKey =
      _rawPublishableKey != '' ? _rawPublishableKey : _devSupabasePublishableKey;

  static String get supabaseAnonKey {
    if (_supabaseAnonKey.isNotEmpty) return _supabaseAnonKey;
    return _supabasePublishableKey;
  }

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
