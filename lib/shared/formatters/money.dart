/// Format a number as Dominican Peso currency: RD$ X,XXX.XX
String formatMoney(num value) {
  final absolute = value.abs().toStringAsFixed(2);
  final parts = absolute.split('.');
  final integer = parts[0];
  final decimal = parts[1];
  final withCommas = integer.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final sign = value < 0 ? '-' : '';
  return '${sign}RD\$ $withCommas.$decimal';
}

/// Compact money for chart axes: 1M, 100k, etc.
String compactMoney(num value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(0)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}k';
  return value.toStringAsFixed(0);
}

/// Format a date as DD/MM/YYYY
String formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString();
  return '$day/$month/$year';
}
