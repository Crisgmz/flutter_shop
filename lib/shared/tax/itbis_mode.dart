/// Tipo de ITBIS de un producto o servicio (`products.itbis_mode`, migración
/// 109). Cada línea vendida guarda el suyo en `sale_items.itbis_mode`.
abstract final class ItbisMode {
  static const regular = 'regular';

  /// Norma 07-2007 (servicios de construcción): el 18% se cobra sobre el 10%
  /// del monto. El producto guarda la tasa EFECTIVA en `tax_rate` para que
  /// las RPC de venta, que calculan con esa columna, cobren bien; un
  /// disparador de la base la mantiene pegada al modo.
  static const norma0707 = 'norma_07_2007';

  /// Tasa que se ve en pantalla y en la factura: "ITBIS 18% (Norma 07-2007)".
  static const normaNominalRate = 18.0;

  /// Tasa con que se cobra: 18% × 10%.
  static const normaEffectiveRate = 1.8;
}

/// Cualquier valor desconocido o vacío es ITBIS regular.
String normalizeItbisMode(String? value) =>
    value == ItbisMode.norma0707 ? ItbisMode.norma0707 : ItbisMode.regular;
