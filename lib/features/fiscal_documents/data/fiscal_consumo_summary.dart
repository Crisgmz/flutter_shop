/// Lo que el resumen necesita de cada comprobante. Lo cumplen los
/// comprobantes (`FiscalDocument`) y las ventas del 607 (`FiscalSale`).
abstract interface class FiscalSummarySource {
  String get receiptType;
  bool get isCancelled;
  double get totalAmount;
  double get taxAmount;
  double get serviceChargeAmount;

  /// Monto por método de pago al vender; `credit` = lo que quedó debiendo.
  Map<String, double> get paymentBreakdown;
}

/// Formas de venta del "Resumen de Facturas de Consumo" de la DGII (formato
/// 607), con el número de línea que usa el formulario.
enum DgiiSaleType {
  cash(11, 'EFECTIVO'),
  checkTransfer(12, 'CHEQUE / TRANSFERENCIA'),
  card(13, 'TARJETA DÉBITO / CRÉDITO'),
  credit(14, 'A CRÉDITO'),
  giftCard(15, 'BONOS O CERTIFICADOS DE REGALO'),
  barter(16, 'PERMUTA'),
  other(17, 'OTRAS FORMAS DE VENTAS');

  const DgiiSaleType(this.line, this.label);

  final int line;
  final String label;

  /// A qué línea va cada valor del enum `payment_method`. El pago móvil es
  /// una transferencia; la nota de crédito, "Otro" y el "Mixto" viejo (sin
  /// desglose) van a otras formas.
  static DgiiSaleType fromPaymentMethod(String method) {
    switch (method) {
      case 'cash':
        return DgiiSaleType.cash;
      case 'transfer':
      case 'mobile':
        return DgiiSaleType.checkTransfer;
      case 'card':
        return DgiiSaleType.card;
      case 'credit':
        return DgiiSaleType.credit;
      default:
        return DgiiSaleType.other;
    }
  }
}

/// Una línea del resumen: número, concepto y valor. `amount` null = celda
/// vacía (así salen en el formulario los conceptos en cero).
class FiscalSummaryLine {
  const FiscalSummaryLine(this.line, this.label, this.amount,
      {this.isCount = false});

  final int line;
  final String label;
  final double? amount;
  final bool isCount;
}

/// "Resumen Facturas Consumo" del período, armado desde los comprobantes de
/// consumo (B02 / E32). Los anulados no cuentan.
class FiscalConsumoSummary {
  FiscalConsumoSummary._({
    required this.from,
    required this.to,
    required this.count,
    required this.billedAmount,
    required this.taxAmount,
    required this.legalTipAmount,
    required this.bySaleType,
    required this.cancelledCount,
  });

  factory FiscalConsumoSummary.fromDocuments(
    Iterable<FiscalSummarySource> docs, {
    required DateTime from,
    required DateTime to,
  }) {
    var count = 0;
    var cancelled = 0;
    var billed = 0.0;
    var tax = 0.0;
    var tip = 0.0;
    final bySaleType = {for (final type in DgiiSaleType.values) type: 0.0};

    for (final doc in docs) {
      if (doc.receiptType != 'consumer_final') continue;
      if (doc.isCancelled) {
        cancelled++;
        continue;
      }
      count++;
      // Monto facturado = sin ITBIS ni propina legal (precios con ITBIS
      // incluido: el total ya lo trae dentro).
      billed += doc.totalAmount - doc.taxAmount - doc.serviceChargeAmount;
      tax += doc.taxAmount;
      tip += doc.serviceChargeAmount;

      final breakdown = doc.paymentBreakdown;
      if (breakdown.isEmpty) {
        bySaleType[DgiiSaleType.other] =
            bySaleType[DgiiSaleType.other]! + doc.totalAmount;
        continue;
      }
      for (final entry in breakdown.entries) {
        final type = DgiiSaleType.fromPaymentMethod(entry.key);
        bySaleType[type] = bySaleType[type]! + entry.value;
      }
    }

    return FiscalConsumoSummary._(
      from: from,
      to: to,
      count: count,
      billedAmount: billed,
      taxAmount: tax,
      legalTipAmount: tip,
      bySaleType: bySaleType,
      cancelledCount: cancelled,
    );
  }

  static const title = 'Resumen Facturas Consumo';
  static const generalSectionTitle = 'Resumen General de Facturas de Consumo';
  static const saleTypeSectionTitle = 'TIPO DE VENTA';

  final DateTime from;
  final DateTime to;
  final int count;
  final double billedAmount;
  final double taxAmount;
  final double legalTipAmount;
  final Map<DgiiSaleType, double> bySaleType;

  /// Comprobantes de consumo del período que no se sumaron por anulados.
  final int cancelledCount;

  /// Período DGII `AAAAMM`. Si el rango cruza meses: `AAAAMM-AAAAMM`.
  String get period {
    String ym(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}';
    final start = ym(from);
    final end = ym(to);
    return start == end ? start : '$start-$end';
  }

  /// Líneas 1 a 6 del formulario. La app no maneja selectivo ni otros
  /// impuestos: salen vacíos.
  List<FiscalSummaryLine> get generalLines => [
        FiscalSummaryLine(1, 'Cantidad NCFs Emitidos de F.C.',
            count.toDouble(),
            isCount: true),
        FiscalSummaryLine(2, 'Total Monto Facturado', billedAmount),
        FiscalSummaryLine(3, 'Total Itbis Facturado', taxAmount),
        const FiscalSummaryLine(4, 'Impuesto Selectivo al Consumo', null),
        const FiscalSummaryLine(5, 'Total Otros Impuestos/Tasas', null),
        FiscalSummaryLine(6, 'Total Monto Propina Legal', _orBlank(legalTipAmount)),
      ];

  /// Líneas 11 a 17: cómo se cobraron las facturas.
  List<FiscalSummaryLine> get saleTypeLines => [
        for (final type in DgiiSaleType.values)
          FiscalSummaryLine(type.line, type.label, _orBlank(bySaleType[type]!)),
      ];

  static double? _orBlank(double value) => value.abs() < 0.005 ? null : value;
}
