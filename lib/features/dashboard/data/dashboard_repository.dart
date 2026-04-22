import 'package:supabase_flutter/supabase_flutter.dart';

enum DashboardPeriod { monthly, weekly }

class DashboardKpis {
  DashboardKpis({
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.salesTodayAmount,
    required this.salesTodayCount,
    required this.salesMonthAmount,
    required this.salesMonthCount,
    required this.productsActive,
    required this.clientsActive,
    required this.ecfIssuedMonth,
    required this.ncfConsumed,
    required this.ncfAvailable,
  });

  final String branchId;
  final String branchCode;
  final String branchName;
  final double salesTodayAmount;
  final int salesTodayCount;
  final double salesMonthAmount;
  final int salesMonthCount;
  final int productsActive;
  final int clientsActive;
  final int ecfIssuedMonth;
  final int ncfConsumed;
  final int ncfAvailable;

  factory DashboardKpis.fromMap(Map<String, dynamic> map) {
    return DashboardKpis(
      branchId: (map['branch_id'] ?? '').toString(),
      branchCode: (map['branch_code'] ?? '').toString(),
      branchName: (map['branch_name'] ?? '').toString(),
      salesTodayAmount: _toDouble(map['sales_today_amount']),
      salesTodayCount: _toInt(map['sales_today_count']),
      salesMonthAmount: _toDouble(map['sales_month_amount']),
      salesMonthCount: _toInt(map['sales_month_count']),
      productsActive: _toInt(map['products_active']),
      clientsActive: _toInt(map['clients_active']),
      ecfIssuedMonth: _toInt(map['ecf_issued_month']),
      ncfConsumed: _toInt(map['ncf_consumed']),
      ncfAvailable: _toInt(map['ncf_available']),
    );
  }
}

class SalesSummaryPoint {
  SalesSummaryPoint({
    required this.periodStart,
    required this.periodLabel,
    required this.totalAmount,
    required this.transactionCount,
  });

  final DateTime periodStart;
  final String periodLabel;
  final double totalAmount;
  final int transactionCount;

  factory SalesSummaryPoint.fromMap(Map<String, dynamic> map) {
    return SalesSummaryPoint(
      periodStart: DateTime.tryParse((map['period_start'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      periodLabel: (map['period_label'] ?? '').toString(),
      totalAmount: _toDouble(map['total_amount']),
      transactionCount: _toInt(map['transaction_count']),
    );
  }
}

class LatestSale {
  LatestSale({
    required this.saleDate,
    required this.clientName,
    required this.receiptType,
    required this.ncf,
    required this.totalAmount,
    required this.dgiiStatus,
  });

  final DateTime saleDate;
  final String clientName;
  final String receiptType;
  final String? ncf;
  final double totalAmount;
  final String dgiiStatus;

  factory LatestSale.fromMap(Map<String, dynamic> map) {
    return LatestSale(
      saleDate: DateTime.tryParse((map['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      clientName: (map['client_name'] ?? '').toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      ncf: map['ncf']?.toString(),
      totalAmount: _toDouble(map['total_amount']),
      dgiiStatus: (map['dgii_status'] ?? '').toString(),
    );
  }
}

class DashboardData {
  DashboardData({
    required this.kpis,
    required this.salesSummary,
    required this.latestSales,
    required this.period,
  });

  final DashboardKpis? kpis;
  final List<SalesSummaryPoint> salesSummary;
  final List<LatestSale> latestSales;
  final DashboardPeriod period;
}

class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Future<DashboardData> fetchDashboard(DashboardPeriod period) async {
    final branchId = await _currentBranchId();

    final futures = await Future.wait<dynamic>([
      _fetchKpis(branchId),
      _fetchSalesSummary(branchId, period),
      _fetchLatestSales(branchId),
    ]);

    return DashboardData(
      kpis: futures[0] as DashboardKpis?,
      salesSummary: futures[1] as List<SalesSummaryPoint>,
      latestSales: futures[2] as List<LatestSale>,
      period: period,
    );
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  Future<DashboardKpis?> _fetchKpis(String? branchId) async {
    final rows = await (branchId == null
        ? _client.from('dashboard_kpis_by_branch').select().limit(1)
        : _client
            .from('dashboard_kpis_by_branch')
            .select()
            .eq('branch_id', branchId)
            .limit(1));

    if (rows.isEmpty) return null;

    return DashboardKpis.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<SalesSummaryPoint>> _fetchSalesSummary(
    String? branchId,
    DashboardPeriod period,
  ) async {
    final viewName = period == DashboardPeriod.monthly
        ? 'sales_monthly_summary'
        : 'sales_weekly_summary';

    final rows = await (branchId == null
        ? _client.from(viewName).select().order('period_start')
        : _client
            .from(viewName)
            .select()
            .eq('branch_id', branchId)
            .order('period_start'));

    return rows
        .map((item) =>
            SalesSummaryPoint.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<LatestSale>> _fetchLatestSales(String? branchId) async {
    final rows = await (branchId == null
        ? _client.from('latest_sales_view').select().limit(8)
        : _client
            .from('latest_sales_view')
            .select()
            .eq('branch_id', branchId)
            .limit(8));

    return rows
        .map((item) => LatestSale.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }
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
