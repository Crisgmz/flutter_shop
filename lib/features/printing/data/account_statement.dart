import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/io/storage_image_loader.dart';

/// De qué lado está la deuda: el cliente nos debe (cuentas por cobrar) o le
/// debemos al proveedor (cuentas por pagar).
enum AccountStatementKind { receivable, payable }

/// Empresa que emite el documento: los mismos datos del encabezado de la
/// factura (nombre de la sucursal + datos de la empresa en Configuración).
class StatementIssuer {
  const StatementIssuer({
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.taxId,
    this.logoBytes,
  });

  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? taxId;
  final List<int>? logoBytes;
}

/// Cliente o proveedor al que va dirigido el estado de cuenta.
class StatementParty {
  const StatementParty({
    required this.name,
    this.document,
    this.phone,
    this.address,
    this.email,
  });

  final String name;

  /// Ya rotulado: "RNC: 130...", "Cédula: 001...".
  final String? document;
  final String? phone;
  final String? address;
  final String? email;
}

/// Una factura con saldo pendiente: venta a crédito o compra sin saldar.
class StatementDocument {
  const StatementDocument({
    required this.id,
    required this.date,
    required this.number,
    required this.partyName,
    required this.total,
    required this.paid,
    required this.balance,
    this.reference,
    this.dueDate,
  });

  final String id;
  final DateTime date;

  /// FA-000110 o el número de la compra.
  final String number;

  /// NCF de la venta o número de factura del proveedor.
  final String? reference;
  final String partyName;
  final DateTime? dueDate;
  final double total;
  final double paid;
  final double balance;

  /// Días de atraso al [asOf]. Sin fecha de vencimiento se cuenta desde la
  /// fecha de la factura, para que una deuda vieja sin plazo no pase por
  /// corriente.
  int daysOverdue(DateTime asOf) {
    final due = dueDate ?? date;
    final d = DateTime(due.year, due.month, due.day);
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    final days = today.difference(d).inDays;
    return days < 0 ? 0 : days;
  }
}

/// Abono aplicado a una de las facturas del estado de cuenta.
class StatementPayment {
  const StatementPayment({
    required this.date,
    required this.documentNumber,
    required this.method,
    required this.amount,
    this.reference,
  });

  final DateTime date;
  final String documentNumber;

  /// Ya en español ("Efectivo", "Transferencia").
  final String method;
  final double amount;
  final String? reference;
}

/// Estado de cuenta de un cliente o proveedor: sus facturas pendientes y los
/// abonos que se les aplicaron. Se arma sobre `balance_due` de cada factura,
/// que es lo que el sistema dice que se debe, en vez de reconstruir un saldo
/// desde el historial.
class AccountStatement {
  const AccountStatement({
    required this.kind,
    required this.issuer,
    required this.party,
    required this.documents,
    required this.payments,
    required this.generatedAt,
    this.from,
    this.to,
  });

  final AccountStatementKind kind;
  final StatementIssuer issuer;
  final StatementParty party;
  final List<StatementDocument> documents;
  final List<StatementPayment> payments;
  final DateTime generatedAt;

  /// Rango de fechas de las facturas incluidas. Null = todas las pendientes.
  final DateTime? from;
  final DateTime? to;

  double get totalAmount => documents.fold(0, (s, d) => s + d.total);
  double get totalPaid => documents.fold(0, (s, d) => s + d.paid);
  double get totalBalance => documents.fold(0, (s, d) => s + d.balance);
  double get overdueBalance => documents
      .where((d) => d.daysOverdue(generatedAt) > 0)
      .fold(0, (s, d) => s + d.balance);

  /// Saldo por antigüedad: [por vencer, 1-30, 31-60, 61-90, más de 90] días.
  List<double> get agingBuckets {
    final buckets = List<double>.filled(5, 0);
    for (final d in documents) {
      final days = d.daysOverdue(generatedAt);
      final index = days <= 0
          ? 0
          : days <= 30
              ? 1
              : days <= 60
                  ? 2
                  : days <= 90
                      ? 3
                      : 4;
      buckets[index] += d.balance;
    }
    return buckets;
  }
}

/// Tipo de movimiento del historial del cliente.
enum StatementMovementKind { sale, payment, refund, voided }

/// Un renglón del historial del cliente (ventas, pagos y devoluciones) para
/// el estado de cuenta en PDF.
class StatementMovement {
  const StatementMovement({
    required this.date,
    required this.document,
    required this.type,
    required this.amount,
    required this.kind,
    this.detail,
  });

  final DateTime date;

  /// FA-000110, NC-00012...
  final String document;

  /// "Venta a crédito", "Pago · Efectivo", "Devolución · Nota de crédito".
  final String type;

  /// Pendiente de la venta, factura que paga el abono, referencia...
  final String? detail;
  final double amount;
  final StatementMovementKind kind;
}

/// Si [when] cae entre [from] y [to], contando días completos (el día [to]
/// entra entero). Un extremo null no limita.
bool isWithinStatementDays(DateTime when, DateTime? from, DateTime? to) {
  if (from != null && when.isBefore(DateTime(from.year, from.month, from.day))) {
    return false;
  }
  if (to != null && !when.isBefore(DateTime(to.year, to.month, to.day + 1))) {
    return false;
  }
  return true;
}

/// Encabezado del emisor, igual al de la factura: nombre de la sucursal y,
/// de Configuración, dirección, teléfono, correo, RNC y logo.
Future<StatementIssuer> loadStatementIssuer(
  SupabaseClient client,
  String branchId,
) async {
  final branchRows = await client
      .from('branches')
      .select('name, address, phone')
      .eq('id', branchId)
      .limit(1);
  final branch = branchRows.isEmpty
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from(branchRows.first as Map);
  final settingsRows = await client.from('app_settings').select().limit(1);
  final settings = settingsRows.isEmpty
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from(settingsRows.first as Map);
  final logoBytes = await downloadStorageImageBytes(
    client,
    settings['company_logo_url']?.toString(),
  );
  return StatementIssuer(
    name: _firstNonEmpty([branch['name']]) ?? 'Sucursal',
    address: _firstNonEmpty([settings['company_address'], branch['address']]),
    phone: _firstNonEmpty([settings['company_phone'], branch['phone']]),
    email: _firstNonEmpty([settings['company_email']]),
    taxId: _firstNonEmpty([settings['company_tax_id']]),
    logoBytes: logoBytes,
  );
}

/// Método de pago en español (abonos del estado de cuenta y pagos recibidos).
String statementPaymentMethodLabel(String value) {
  switch (value) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    case 'mobile':
      return 'Pago móvil';
    case 'check':
      return 'Cheque';
    case 'mixed':
      return 'Mixto';
    case 'credit':
      return 'Crédito';
    case 'credit_note':
      return 'Nota de crédito';
    case 'other':
      return 'Otro';
    default:
      return value.trim().isEmpty ? 'Pago' : value;
  }
}

String? _firstNonEmpty(List<dynamic> values) {
  for (final v in values) {
    final s = v?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}
