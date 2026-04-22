import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

class SupabaseBootstrap {
  static Future<void> initialize() async {
    if (!Env.isSupabaseConfigured) return;

    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }
}
