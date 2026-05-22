import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Helpers para SnackBars consistentes en toda la app.
///
/// Antes: cada feature mostraba `SnackBar(content: Text('Error: $e'))` con
/// `e` formateado como `PostgrestException(message: ..., code: ..., hint:
/// null)`. Quedaba feo y filtraba detalles internos.
///
/// Ahora: `AppSnackBar.error(...)` extrae solo el mensaje legible y aplica
/// estilos (color por severidad, ícono, esquinas redondeadas, flotante).
class AppSnackBar {
  AppSnackBar._();

  /// Mensaje neutro (gris oscuro).
  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFF1E293B),
      icon: Icons.info_outline_rounded,
    );
  }

  /// Operación exitosa (verde).
  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFF16A34A),
      icon: Icons.check_circle_outline_rounded,
    );
  }

  /// Operación fallida (rojo). Acepta cualquier `Object?` y extrae el
  /// mensaje limpio si es un `PostgrestException` o `Exception`.
  static void error(BuildContext context, String title, [Object? error]) {
    final detail = friendlyErrorMessage(error);
    final message = detail.isEmpty ? title : '$title\n$detail';
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFFDC2626),
      icon: Icons.error_outline_rounded,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    required IconData icon,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convierte cualquier error en un mensaje legible para el usuario.
///
/// - `PostgrestException` → solo el `message` (sin code/hint/details).
/// - `Exception` (normalmente lanzados con `throw Exception('Texto.')`) →
///   solo el texto, sin el prefijo "Exception: ".
/// - Cualquier otra cosa → su `toString`.
String friendlyErrorMessage(Object? error) {
  if (error == null) return '';
  if (error is PostgrestException) {
    return error.message;
  }
  if (error is Exception) {
    final raw = error.toString();
    const prefix = 'Exception: ';
    if (raw.startsWith(prefix)) return raw.substring(prefix.length);
    return raw;
  }
  return error.toString();
}
