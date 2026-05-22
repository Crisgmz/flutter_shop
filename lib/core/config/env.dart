class Env {
  // Default deploy: subdominio dedicado para Supabase con Let's Encrypt
  // emitido en Coolify. Frontend y backend en orígenes separados.
  //
  // Para apuntar a otra instancia, pasar --dart-define al `flutter run`:
  //   --dart-define=SUPABASE_URL=https://otro.supabase.co
  //   --dart-define=SUPABASE_ANON_KEY=...
  static const _devSupabaseUrl = 'https://supabase.busiposweb.com';
  static const _devSupabasePublishableKey =
      'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3OTQ2MTI4MCwiZXhwIjo0OTM1MTM0ODgwLCJyb2xlIjoiYW5vbiJ9.CdZEf7Ux9iGEvc2TXl-hMTOyqpZ3AFTCiN7yD1saswI';

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
