/// Centralized formatters for Shop+ RD.
///
/// Replaces per-page `_money()`, `_date()`, `_pretty()` helpers with a single
/// import. All pages should use these instead of defining local copies.
library;

// ── Number helpers ──────────────────────────────────────────────────────────

/// Safely coerce any value to [double].
double toDouble(Object? v) {
  if (v == null) return 0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

/// Safely coerce any value to [int].
int toInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

// ── Money ───────────────────────────────────────────────────────────────────

/// Format a number as Dominican Peso (DOP).
///
/// Examples: `money(1500)` → `"RD\$ 1,500.00"`, `money(0)` → `"RD\$ 0.00"`
String money(Object? amount) {
  final value = toDouble(amount);
  final formatted = value
      .toStringAsFixed(2)
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+\.)'),
        (m) => '${m[1]},',
      );
  return 'RD\$ $formatted';
}

/// Short money format without decimals for KPIs / compact display.
String moneyShort(Object? amount) {
  final value = toDouble(amount);
  if (value.abs() >= 1000000) {
    return 'RD\$ ${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value.abs() >= 1000) {
    return 'RD\$ ${(value / 1000).toStringAsFixed(1)}K';
  }
  return 'RD\$ ${value.toStringAsFixed(0)}';
}

// ── Dates ───────────────────────────────────────────────────────────────────

/// Format a date string or DateTime as `"dd/MM/yyyy"`.
String formatDate(Object? value) {
  final dt = _parseDate(value);
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

/// Format as `"dd/MM/yyyy HH:mm"`.
String formatDateTime(Object? value) {
  final dt = _parseDate(value);
  if (dt == null) return '—';
  return '${formatDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// Relative date label: "Hoy", "Ayer", or `dd/MM/yyyy`.
String formatDateRelative(Object? value) {
  final dt = _parseDate(value);
  if (dt == null) return '—';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  return formatDate(dt);
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

// ── Percentage ──────────────────────────────────────────────────────────────

/// Format as percentage: `percent(0.152)` → `"15.2%"`
String percent(Object? value) {
  final v = toDouble(value);
  return '${(v * 100).toStringAsFixed(1)}%';
}

// ── Quantity ─────────────────────────────────────────────────────────────────

/// Integer with thousand separators: `qty(12500)` → `"12,500"`
String qty(Object? value) {
  final v = toInt(value);
  return v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}
