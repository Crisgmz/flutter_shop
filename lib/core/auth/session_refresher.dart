import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mantiene la sesión de Supabase viva cuando la app vuelve al foreground.
///
/// Problema que arregla: en Flutter web, si la pestaña queda en background
/// mucho tiempo el browser throttlea los setTimeout del SDK y el JWT
/// expira sin que el auto-refresh se dispare. Al volver, cualquier query
/// falla con `PGRST303 JWT expired`.
///
/// Solución: escucha [AppLifecycleState.resumed] y dispara
/// `refreshSession()`. Si el refresh falla (refresh token expirado o
/// sesión revocada), el SDK emite `signedOut` y el router redirige a
/// /login automáticamente.
///
/// También revalida cada 4 minutos mientras la app está activa para
/// adelantar el fallo de refresh — los JWT de Supabase suelen durar
/// 3600s (1h), así que cualquier ventana < 1h alcanza.
class SessionRefresher with WidgetsBindingObserver {
  SessionRefresher._();
  static final SessionRefresher instance = SessionRefresher._();

  Timer? _periodicTimer;
  bool _started = false;

  static const _periodicInterval = Duration(minutes: 4);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _periodicTimer = Timer.periodic(_periodicInterval, (_) => _refreshIfActive());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfActive();
    }
  }

  Future<void> _refreshIfActive() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) return;
    try {
      await client.auth.refreshSession();
    } catch (e) {
      // Refresh token caducó o fue revocado — el SDK ya emitió signedOut
      // y el router redirige a /login. Solo logueamos para diagnóstico.
      if (kDebugMode) debugPrint('SessionRefresher: refresh falló: $e');
    }
  }
}
