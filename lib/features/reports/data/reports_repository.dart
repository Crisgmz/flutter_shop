import 'package:supabase_flutter/supabase_flutter.dart';

enum ReportPeriod { monthly, weekly }

class ReportSalesPoint {
  ReportSalesPoint({
    required this.periodStart,
    required this.periodLabel,
    required this.totalAmount,
    required this.transactionCount,
  });

  final DateTime periodStart;
  final String periodLabel;
  final double totalAmount;
  final int transactionCount;

  factory ReportSalesPoint.fromMap(Map<String, dynamic> map) {
    return ReportSalesPoint(
      periodStart: DateTime.tryParse((map['period_start'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      periodLabel: (map['period_label'] ?? '').toString(),
      totalAmount: _toDouble(map['total_amount']),
      transactionCount: _toInt(map['transaction_count']),
    );
  }
}

class ReceivableReport {
  ReceivableReport({
    required this.invoicesOpen,
    required this.totalBalanceDue,
    required this.totalInvoiced,
    required this.totalCollected,
  });

  final int invoicesOpen;
  final double totalBalanceDue;
  final double totalInvoiced;
  final double totalCollected;

  factory ReceivableReport.fromMap(Map<String, dynamic> map) {
    return ReceivableReport(
      invoicesOpen: _toInt(map['invoices_open']),
      totalBalanceDue: _toDouble(map['total_balance_due']),
      totalInvoiced: _toDouble(map['total_invoiced']),
      totalCollected: _toDouble(map['total_collected']),
    );
  }
}

class LowStockReportItem {
  LowStockReportItem({
    required this.name,
    required this.sku,
    required this.stock,
    required this.minStock,
    required this.price,
  });

  final String name;
  final String? sku;
  final double stock;
  final double minStock;
  final double price;

  factory LowStockReportItem.fromMap(Map<String, dynamic> map) {
    return LowStockReportItem(
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      stock: _toDouble(map['stock']),
      minStock: _toDouble(map['min_stock']),
      price: _toDouble(map['price']),
    );
  }
}

class NcfUsageItem {
  NcfUsageItem({
    required this.receiptType,
    required this.prefix,
    required this.currentNumber,
    required this.maxNumber,
    required this.available,
    required this.expiresOn,
  });

  final String receiptType;
  final String prefix;
  final int currentNumber;
  final int? maxNumber;
  final int available;
  final DateTime? expiresOn;

  factory NcfUsageItem.fromMap(Map<String, dynamic> map) {
    return NcfUsageItem(
      receiptType: (map['receipt_type'] ?? '').toString(),
      prefix: (map['prefix'] ?? '').toString(),
      currentNumber: _toInt(map['current_number']),
      maxNumber: map['max_number'] == null ? null : _toInt(map['max_number']),
      available: _toInt(map['available']),
      expiresOn: map['expires_on'] == null
          ? null
          : DateTime.tryParse(map['expires_on'].toString()),
    );
  }
}

class ReportsData {
  ReportsData({
    required this.period,
    required this.salesPoints,
    required this.receivable,
    required this.lowStockItems,
    required this.ncfItems,
  });

  final ReportPeriod period;
  final List<ReportSalesPoint> salesPoints;
  final ReceivableReport? receivable;
  final List<LowStockReportItem> lowStockItems;
  final List<NcfUsageItem> ncfItems;
}

// ── Sales Tax Breakdown ───────────────────────────────────────────────────────

class SalesTaxRow {
  SalesTaxRow({
    required this.saleId,
    required this.saleNumber,
    required this.saleDate,
    required this.receiptType,
    required this.clientName,
    required this.taxableAmount,
    required this.exemptAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.totalAmount,
  });

  final String saleId;
  final String saleNumber;
  final DateTime saleDate;
  final String receiptType;
  final String clientName;
  final double taxableAmount;
  final double exemptAmount;
  final double taxAmount;
  final double serviceChargeAmount;
  final double totalAmount;

  factory SalesTaxRow.fromMap(Map<String, dynamic> map) {
    return SalesTaxRow(
      saleId: (map['sale_id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '').toString(),
      saleDate: DateTime.tryParse((map['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      receiptType: (map['receipt_type'] ?? '').toString(),
      clientName: (map['client_name'] ?? '').toString(),
      taxableAmount: _toDouble(map['taxable_amount']),
      exemptAmount: _toDouble(map['exempt_amount']),
      taxAmount: _toDouble(map['tax_amount']),
      serviceChargeAmount: _toDouble(map['service_charge_amount']),
      totalAmount: _toDouble(map['total_amount']),
    );
  }
}

// ── Report Presets ────────────────────────────────────────────────────────────

class ReportPreset {
  ReportPreset({
    required this.id,
    required this.branchId,
    required this.reportKey,
    required this.name,
    required this.isDefault,
    required this.isActive,
    this.description,
    this.filtersJson = const {},
  });

  final String id;
  final String branchId;
  final String reportKey;
  final String name;
  final String? description;
  final Map<String, dynamic> filtersJson;
  final bool isDefault;
  final bool isActive;

  factory ReportPreset.fromMap(Map<String, dynamic> map) {
    return ReportPreset(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      reportKey: (map['report_key'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description']?.toString(),
      filtersJson: map['filters_json'] is Map
          ? Map<String, dynamic>.from(map['filters_json'] as Map)
          : const {},
      isDefault: map['is_default'] == true,
      isActive: map['is_active'] != false,
    );
  }
}

// ── Report Exports ────────────────────────────────────────────────────────────

class ReportExport {
  ReportExport({
    required this.id,
    required this.branchId,
    required this.reportKey,
    required this.exportFormat,
    required this.status,
    required this.requestedAt,
    this.generatedAt,
    this.expiresAt,
    this.downloadUrl,
    this.fileName,
    this.fileSizeBytes,
    this.errorMessage,
  });

  final String id;
  final String branchId;
  final String reportKey;
  final String exportFormat;
  final String status;
  final DateTime requestedAt;
  final DateTime? generatedAt;
  final DateTime? expiresAt;
  final String? downloadUrl;
  final String? fileName;
  final int? fileSizeBytes;
  final String? errorMessage;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isPending => status == 'pending' || status == 'processing';
  bool get hasDownload => downloadUrl != null && downloadUrl!.isNotEmpty;

  factory ReportExport.fromMap(Map<String, dynamic> map) {
    return ReportExport(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      reportKey: (map['report_key'] ?? '').toString(),
      exportFormat: (map['export_format'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      requestedAt:
          DateTime.tryParse((map['requested_at'] ?? '').toString()) ??
              DateTime.now(),
      generatedAt: map['generated_at'] == null
          ? null
          : DateTime.tryParse(map['generated_at'].toString()),
      expiresAt: map['expires_at'] == null
          ? null
          : DateTime.tryParse(map['expires_at'].toString()),
      downloadUrl: map['download_url']?.toString(),
      fileName: map['file_name']?.toString(),
      fileSizeBytes: map['file_size_bytes'] == null
          ? null
          : _toInt(map['file_size_bytes']),
      errorMessage: map['error_message']?.toString(),
    );
  }
}

class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient _client;

  Future<ReportsData> fetchReports(ReportPeriod period) async {
    final branchId = await _currentBranchId();

    final futures = await Future.wait<dynamic>([
      _fetchSalesPoints(branchId, period),
      _fetchReceivable(branchId),
      _fetchLowStock(branchId),
      _fetchNcfUsage(branchId),
    ]);

    return ReportsData(
      period: period,
      salesPoints: futures[0] as List<ReportSalesPoint>,
      receivable: futures[1] as ReceivableReport?,
      lowStockItems: futures[2] as List<LowStockReportItem>,
      ncfItems: futures[3] as List<NcfUsageItem>,
    );
  }

  Future<List<ReportSalesPoint>> _fetchSalesPoints(
    String? branchId,
    ReportPeriod period,
  ) async {
    final view = period == ReportPeriod.monthly
        ? 'sales_monthly_summary'
        : 'sales_weekly_summary';

    final rows = await (branchId == null
        ? _client.from(view).select().order('period_start')
        : _client
            .from(view)
            .select()
            .eq('branch_id', branchId)
            .order('period_start'));

    return rows
        .map((item) =>
            ReportSalesPoint.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<ReceivableReport?> _fetchReceivable(String? branchId) async {
    final rows = await (branchId == null
        ? _client.from('accounts_receivable_summary').select().limit(1)
        : _client
            .from('accounts_receivable_summary')
            .select()
            .eq('branch_id', branchId)
            .limit(1));

    if (rows.isEmpty) return null;

    return ReceivableReport.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<LowStockReportItem>> _fetchLowStock(String? branchId) async {
    final rows = await (branchId == null
        ? _client.from('inventory_low_stock_view').select().limit(30)
        : _client
            .from('inventory_low_stock_view')
            .select()
            .eq('branch_id', branchId)
            .limit(30));

    return rows
        .map((item) =>
            LowStockReportItem.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<NcfUsageItem>> _fetchNcfUsage(String? branchId) async {
    final rows = await (branchId == null
        ? _client.from('ncf_usage_summary').select().limit(30)
        : _client
            .from('ncf_usage_summary')
            .select()
            .eq('branch_id', branchId)
            .limit(30));

    return rows
        .map((item) => NcfUsageItem.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<ReportPreset>> fetchPresets() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('report_presets')
        .select('id, branch_id, report_key, name, description, filters_json, is_default, is_active')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('is_default', ascending: false)
        .order('name');

    return rows
        .map((item) =>
            ReportPreset.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<SalesTaxRow>> fetchSalesTaxBreakdown({
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    var query = _client
        .from('sales_tax_breakdown_view')
        .select(
          'sale_id, sale_number, sale_date, receipt_type, '
          'taxable_amount, exempt_amount, tax_amount, '
          'service_charge_amount, total_amount, client_name',
        )
        .eq('branch_id', branchId);

    if (from != null) {
      query = query.gte('sale_date', from.toIso8601String().split('T').first);
    }
    if (to != null) {
      query = query.lte('sale_date', to.toIso8601String().split('T').first);
    }

    final rows = await query
        .order('sale_date', ascending: false)
        .limit(limit);

    return rows
        .map((item) =>
            SalesTaxRow.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<void> requestExport({
    required String reportKey,
    required String exportFormat,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client.from('report_exports').insert({
      'branch_id': branchId,
      'report_key': reportKey,
      'export_format': exportFormat,
      'status': 'pending',
    });
  }

  Future<List<ReportExport>> fetchRecentExports({int limit = 20}) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('report_exports')
        .select(
          'id, branch_id, report_key, export_format, status, '
          'requested_at, generated_at, expires_at, download_url, '
          'file_name, file_size_bytes, error_message',
        )
        .eq('branch_id', branchId)
        .order('requested_at', ascending: false)
        .limit(limit);

    return rows
        .map((item) =>
            ReportExport.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
