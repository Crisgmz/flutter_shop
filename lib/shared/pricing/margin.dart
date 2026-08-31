/// Margen sobre el COSTO (markup), no sobre el precio de venta.
///
/// Es como se fijan los precios en el mostrador: "este me costó 200 y lo
/// vendo con un 20" → 200 + 20% = 240. El ITBIS queda fuera de este cálculo;
/// se aplica después según `price_includes_tax` del producto.
library;

/// Precio de venta a partir del costo y el margen %: `costo + costo × %`.
///
/// Ej: `priceFromMargin(200, 20) == 240`.
double priceFromMargin(double cost, double marginPct) {
  final price = cost + (cost * marginPct / 100);
  return double.parse(price.toStringAsFixed(2));
}

/// Margen % implícito de un precio ya escrito a mano. Null si el costo es 0
/// (sin costo no hay margen que calcular).
double? marginFromPrice(double cost, double price) {
  if (cost <= 0) return null;
  final margin = (price - cost) / cost * 100;
  return double.parse(margin.toStringAsFixed(2));
}

/// Texto del margen para el input: sin decimales cuando son ceros ("20", no
/// "20.00"), para que se pueda seguir escribiendo encima sin estorbo.
String formatMargin(double value) {
  final fixed = value.toStringAsFixed(2);
  if (fixed.endsWith('.00')) return fixed.substring(0, fixed.length - 3);
  if (fixed.endsWith('0')) return fixed.substring(0, fixed.length - 1);
  return fixed;
}
