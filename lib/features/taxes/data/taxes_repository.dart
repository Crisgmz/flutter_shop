import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fiscal_documents/data/fiscal_documents_repository.dart'
    show FiscalSalePayment, fetchPaymentsBySale, salePaymentBreakdown;

class TaxesDateRange {
  const TaxesDateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class TaxKpis {
  TaxKpis({
    required this.salesCount,
    required this.salesTotal,
    required this.salesTax,
    required this.purchasesCount,
    required this.purchasesTotal,
    required this.purchasesTax,
  });

  final int salesCount;
  final double salesTotal;
  final double salesTax;
  final int purchasesCount;
  final double purchasesTotal;
  final double purchasesTax;
}

class TaxSaleRecord {
  TaxSaleRecord({
    required this.saleDate,
    required this.clientName,
    required this.receiptType,
    required this.ncf,
    required this.totalAmount,
    required this.taxAmount,
    required this.dgiiStatus,
    this.clientDocument,
    this.saleNumber,
    this.status,
    this.payments = const [],
  });

  final DateTime saleDate;
  final String clientName;
  final String receiptType;
  final String? ncf;
  final double totalAmount;
  final double taxAmount;
  final String dgiiStatus;

  /// RNC o cédula del cliente (el mismo dato que usa el 607 de la DGII).
  final String? clientDocument;
  final String? saleNumber;
  final String? status;
  final List<FiscalSalePayment> payments;

  /// Cómo se pagó al vender (ver `salePaymentBreakdown`). Vacío si la venta
  /// no está cobrada ni a crédito (ej. una cuenta guardada).
  Map<String, double> get paymentBreakdown {
    final saleStatus = status;
    if (saleStatus != 'completed' && saleStatus != 'credit') return const {};
    return salePaymentBreakdown(
      total: totalAmount,
      saleNumber: saleNumber,
      saleDate: saleDate,
      saleStatus: saleStatus!,
      payments: payments,
    );
  }

  factory TaxSaleRecord.fromMap(Map<String, dynamic> map) {
    final client = Map<String, dynamic>.from(
      (map['clients'] as Map?) ?? const <String, dynamic>{},
    );
    final document = client['document_number']?.toString().trim() ?? '';

    return TaxSaleRecord(
      saleDate:
          DateTime.tryParse((map['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      clientName: (client['full_name'] ?? 'Cliente contado').toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      ncf: map['ncf']?.toString(),
      totalAmount: _toDouble(map['total_amount']),
      taxAmount: _toDouble(map['tax_amount']),
      dgiiStatus: (map['dgii_status'] ?? '').toString(),
      clientDocument: document.isEmpty ? null : document,
      saleNumber: map['sale_number']?.toString(),
      status: map['status']?.toString(),
      payments: [
        for (final raw in (map['payments'] as List?) ?? const [])
          if (raw is Map)
            FiscalSalePayment.fromMap(Map<String, dynamic>.from(raw)),
      ],
    );
  }
}

class TaxPurchaseRecord {
  TaxPurchaseRecord({
    required this.purchaseDate,
    required this.supplierName,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.taxAmount,
    required this.status,
  });

  final DateTime purchaseDate;
  final String supplierName;
  final String? invoiceNumber;
  final double totalAmount;
  final double taxAmount;
  final String status;

  factory TaxPurchaseRecord.fromMap(Map<String, dynamic> map) {
    final supplier = Map<String, dynamic>.from(
      (map['suppliers'] as Map?) ?? const <String, dynamic>{},
    );
    final tradeName = (supplier['trade_name'] ?? '').toString().trim();
    final legalName = (supplier['legal_name'] ?? '').toString().trim();
    final supplierName = tradeName.isNotEmpty
        ? tradeName
        : (legalName.isNotEmpty ? legalName : 'Suplidor');

    return TaxPurchaseRecord(
      purchaseDate:
          DateTime.tryParse((map['purchase_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      supplierName: supplierName,
      invoiceNumber: map['invoice_number']?.toString(),
      totalAmount: _toDouble(map['total_amount']),
      taxAmount: _toDouble(map['tax_amount']),
      status: (map['status'] ?? '').toString(),
    );
  }
}

class NcfTaxItem {
  NcfTaxItem({
    required this.id,
    required this.receiptType,
    required this.prefix,
    required this.currentNumber,
    required this.maxNumber,
    required this.expiresOn,
    required this.isActive,
  });

  final String id;
  final String receiptType;
  final String prefix;
  final int currentNumber;
  final int? maxNumber;
  final DateTime? expiresOn;
  final bool isActive;

  int? get available {
    if (maxNumber == null) return null;
    final value = maxNumber! - currentNumber;
    return value < 0 ? 0 : value;
  }

  factory NcfTaxItem.fromMap(Map<String, dynamic> map) {
    return NcfTaxItem(
      id: (map['id'] ?? '').toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      prefix: (map['prefix'] ?? '').toString(),
      currentNumber: _toInt(map['current_number']),
      maxNumber: map['max_number'] == null ? null : _toInt(map['max_number']),
      expiresOn: map['expires_on'] == null
          ? null
          : DateTime.tryParse(map['expires_on'].toString()),
      isActive: map['is_active'] == true,
    );
  }
}

class TaxesData {
  TaxesData({
    required this.range,
    required this.kpis,
    required this.sales,
    required this.purchases,
    required this.ncfItems,
  });

  final TaxesDateRange range;
  final TaxKpis kpis;
  final List<TaxSaleRecord> sales;
  final List<TaxPurchaseRecord> purchases;
  final List<NcfTaxItem> ncfItems;
}

class TaxesRepository {
  TaxesRepository(this._client);

  final SupabaseClient _client;

  Future<TaxesData> fetchTaxes(TaxesDateRange range) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      return TaxesData(
        range: range,
        kpis: TaxKpis(
          salesCount: 0,
          salesTotal: 0,
          salesTax: 0,
          purchasesCount: 0,
          purchasesTotal: 0,
          purchasesTax: 0,
        ),
        sales: const [],
        purchases: const [],
        ncfItems: const [],
      );
    }

    final futures = await Future.wait<dynamic>([
      _fetchSales(branchId, range),
      _fetchPurchases(branchId, range),
      _fetchNcf(branchId),
    ]);

    final sales = futures[0] as List<TaxSaleRecord>;
    final purchases = futures[1] as List<TaxPurchaseRecord>;
    final ncfItems = futures[2] as List<NcfTaxItem>;

    final salesTotal = sales.fold<double>(
      0,
      (sum, item) => sum + item.totalAmount,
    );
    final salesTax = sales.fold<double>(0, (sum, item) => sum + item.taxAmount);
    final purchasesTotal = purchases.fold<double>(
      0,
      (sum, item) => sum + item.totalAmount,
    );
    final purchasesTax = purchases.fold<double>(
      0,
      (sum, item) => sum + item.taxAmount,
    );

    return TaxesData(
      range: range,
      kpis: TaxKpis(
        salesCount: sales.length,
        salesTotal: salesTotal,
        salesTax: salesTax,
        purchasesCount: purchases.length,
        purchasesTotal: purchasesTotal,
        purchasesTax: purchasesTax,
      ),
      sales: sales,
      purchases: purchases,
      ncfItems: ncfItems,
    );
  }

  String build607Csv(List<TaxSaleRecord> rows) {
    final buffer = StringBuffer();
    buffer.writeln(
      'fecha,cliente,rnc,tipo_comprobante,ncf,metodo_pago,total,itbis,estado_dgii',
    );
    for (final row in rows) {
      final methods = row.paymentBreakdown.keys.join('+');
      buffer.writeln(
        '${_escapeCsv(_date(row.saleDate))},${_escapeCsv(row.clientName)},${_escapeCsv(row.clientDocument ?? '')},${_escapeCsv(row.receiptType)},${_escapeCsv(row.ncf ?? '')},${_escapeCsv(methods)},${row.totalAmount.toStringAsFixed(2)},${row.taxAmount.toStringAsFixed(2)},${_escapeCsv(row.dgiiStatus)}',
      );
    }
    return buffer.toString();
  }

  String build606Csv(List<TaxPurchaseRecord> rows) {
    final buffer = StringBuffer();
    buffer.writeln('fecha,suplidor,numero_factura,total,itbis,estado');
    for (final row in rows) {
      buffer.writeln(
        '${_escapeCsv(_date(row.purchaseDate))},${_escapeCsv(row.supplierName)},${_escapeCsv(row.invoiceNumber ?? '')},${row.totalAmount.toStringAsFixed(2)},${row.taxAmount.toStringAsFixed(2)},${_escapeCsv(row.status)}',
      );
    }
    return buffer.toString();
  }

  /// Ventas del período, de 1000 en 1000. Antes había un tope de 500: en un
  /// mes con más ventas el 607 (y los totales) salían incompletos sin avisar.
  Future<List<TaxSaleRecord>> _fetchSales(
    String branchId,
    TaxesDateRange range,
  ) async {
    // En UTC: sin la zona, el servidor leía la medianoche local como UTC y
    // el rango se corría 4 horas (se perdía la noche del último día).
    final startIso = _atStartOfDay(range.start).toUtc().toIso8601String();
    final endIso = _atEndExclusive(range.end).toUtc().toIso8601String();

    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client
          .from('sales')
          .select(
            'id, sale_date, sale_number, status, receipt_type, ncf, '
            'total_amount, tax_amount, dgii_status, '
            'clients(full_name, document_number)',
          )
          .eq('branch_id', branchId)
          .neq('status', 'voided')
          .gte('sale_date', startIso)
          .lt('sale_date', endIso)
          .order('sale_date', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
      if (page.length < pageSize) break;
      offset += page.length;
    }

    // Los pagos aparte y por id: unidos a esta consulta, con la RLS, la
    // consulta podía recorrer todos los pagos de la sucursal (57014).
    final payments = await fetchPaymentsBySale(
      _client,
      rows.map((row) => row['id'].toString()),
    );
    return [
      for (final row in rows)
        TaxSaleRecord.fromMap({
          ...row,
          'payments': payments[row['id'].toString()] ?? const [],
        }),
    ];
  }

  Future<List<TaxPurchaseRecord>> _fetchPurchases(
    String branchId,
    TaxesDateRange range,
  ) async {
    final start = _date(range.start);
    final end = _date(range.end);

    final rows = await _client
        .from('purchases')
        .select(
          'purchase_date, invoice_number, total_amount, tax_amount, status, suppliers(legal_name, trade_name)',
        )
        .eq('branch_id', branchId)
        .neq('status', 'cancelled')
        .gte('purchase_date', start)
        .lte('purchase_date', end)
        .order('purchase_date', ascending: false)
        .limit(500);

    return rows
        .map(
          (row) =>
              TaxPurchaseRecord.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<List<NcfTaxItem>> _fetchNcf(String branchId) async {
    final rows = await _client
        .from('ncf_sequences')
        .select(
          'id, receipt_type, prefix, current_number, max_number, expires_on, is_active',
        )
        .eq('branch_id', branchId)
        .order('receipt_type')
        .order('prefix');

    return rows
        .map((row) => NcfTaxItem.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

DateTime _atStartOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _atEndExclusive(DateTime value) =>
    DateTime(value.year, value.month, value.day).add(const Duration(days: 1));

String _date(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString();
  return '$year-$month-$day';
}

String _escapeCsv(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
