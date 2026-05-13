import 'live_settings.dart';

/// Formatea un número como moneda según los settings globales.
/// Lee símbolo, decimales, separadores de [LiveSettings] (sincronizado
/// con `app_settings`).
String formatMoney(num value) {
  final decimals = LiveSettings.currencyDecimals;
  final thousands = LiveSettings.thousandsSep;
  final decimalPoint = LiveSettings.decimalPoint;
  final symbol = LiveSettings.currencySymbol;

  final absolute = value.abs().toStringAsFixed(decimals);
  final parts = absolute.split('.');
  final integer = parts[0];
  final decimal = parts.length > 1 ? parts[1] : '';
  final withSep = integer.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => thousands,
  );
  final sign = value < 0 ? '-' : '';
  if (decimals == 0 || decimal.isEmpty) {
    return '$sign$symbol $withSep';
  }
  return '$sign$symbol $withSep$decimalPoint$decimal';
}

/// Compact money for chart axes: 1M, 100k, etc.
String compactMoney(num value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(0)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}k';
  return value.toStringAsFixed(0);
}

/// Format a date según el formato configurado (default DD/MM/YYYY).
String formatDate(DateTime value) {
  // Si viene en UTC (timestamptz de Supabase), pasarlo a hora local del
  // usuario antes de extraer componentes.
  final local = value.isUtc ? value.toLocal() : value;
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  switch (LiveSettings.dateFormat) {
    case 'dd-MM-yyyy':
      return '$day-$month-$year';
    case 'MM-dd-yyyy':
      return '$month-$day-$year';
    case 'yyyy-MM-dd':
      return '$year-$month-$day';
    case 'dd/MM/yyyy':
    default:
      return '$day/$month/$year';
  }
}
