import 'package:supabase_flutter/supabase_flutter.dart';

import '../../printing/data/printing.dart';
import '../domain/sale_checkout_service.dart';

class SalesProduct {
  SalesProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.taxRate,
    required this.stock,
    required this.isActive,
    this.sku,
    this.barcode,
    this.categoryId,
    this.categoryName,
  });

  final String id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? categoryName;
  final double price;
  final double taxRate;
  final double stock;
  final bool isActive;

  factory SalesProduct.fromMap(
    Map<String, dynamic> map,
    Map<String, String> categoryNames,
  ) {
    final categoryId = map['category_id']?.toString();

    return SalesProduct(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      categoryId: categoryId,
      categoryName: categoryId == null ? null : categoryNames[categoryId],
      price: _toDouble(map['price']),
      taxRate: _toDouble(map['tax_rate']),
      stock: _toDouble(map['stock']),
      isActive: map['is_active'] == true,
    );
  }
}

class SalesCategory {
  SalesCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory SalesCategory.fromMap(Map<String, dynamic> map) {
    return SalesCategory(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
    );
  }
}

class SalesClient {
  SalesClient({required this.id, required this.fullName});

  final String id;
  final String fullName;

  factory SalesClient.fromMap(Map<String, dynamic> map) {
    return SalesClient(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
    );
  }
}

class SaleCartItem {
  SaleCartItem({required this.product, required this.quantity});

  final SalesProduct product;
  final double quantity;

  double get lineSubtotal => _round2(quantity * product.price);
  double get lineTax => _round2(lineSubtotal * (product.taxRate / 100));
  double get lineTotal => _round2(lineSubtotal + lineTax);
}

class SaleCheckoutInput {
  SaleCheckoutInput({
    required this.items,
    required this.receiptType,
    required this.asCredit,
    this.paymentMethod,
    this.clientId,
    this.notes,
  });

  final List<SaleCartItem> items;
  final String receiptType;
  final bool asCredit;
  final String? paymentMethod;
  final String? clientId;
  final String? notes;
}

class SaleCheckoutResult {
  SaleCheckoutResult({
    required this.saleId,
    required this.saleNumber,
    required this.receiptType,
    required this.status,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.itemsCount,
    this.cashSessionId,
    this.preparedPrintJob,
  });

  final String saleId;
  final String saleNumber;
  final String receiptType;
  final String status;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final int itemsCount;
  final String? cashSessionId;
  final PreparedPrintJobData? preparedPrintJob;
}

class SalesRepository {
  SalesRepository(this._client);

  final SupabaseClient _client;
  static const SalePrintJobPreparationService _salePrintPreparationService =
      SalePrintJobPreparationService();
  static const SaleCheckoutService _saleCheckoutService = SaleCheckoutService();

  Future<List<SalesCategory>> fetchCategories() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('product_categories')
        .select('id, name')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');

    return rows
        .map(
          (item) =>
              SalesCategory.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<SalesProduct>> fetchProducts() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final categories = await fetchCategories();
    final categoryNames = <String, String>{
      for (final category in categories) category.id: category.name,
    };

    final rows = await _client
        .from('products')
        .select(
          'id, name, sku, barcode, category_id, price, tax_rate, stock, is_active',
        )
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');

    return rows
        .map(
          (item) => SalesProduct.fromMap(
            Map<String, dynamic>.from(item as Map),
            categoryNames,
          ),
        )
        .toList(growable: false);
  }

  Future<List<SalesClient>> fetchClients() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('clients')
        .select('id, full_name')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('full_name');

    return rows
        .map(
          (item) => SalesClient.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<SaleCheckoutResult> checkoutSale(SaleCheckoutInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('La sesión no es válida. Inicia sesión de nuevo.');
    }

    final normalizedCheckout = _saleCheckoutService.normalize(
      SaleCheckoutServiceInput(
        items: input.items
            .map(
              (item) => SaleCheckoutSourceItem(
                product: SaleCheckoutSourceProduct(
                  id: item.product.id,
                  name: item.product.name,
                  price: item.product.price,
                  taxRate: item.product.taxRate,
                  stock: item.product.stock,
                  isActive: item.product.isActive,
                ),
                quantity: item.quantity,
              ),
            )
            .toList(growable: false),
        receiptType: input.receiptType,
        asCredit: input.asCredit,
        paymentMethod: input.paymentMethod,
        clientId: _nullIfEmpty(input.clientId),
        notes: input.notes,
      ),
    );

    final rpcResult = await _client.rpc(
      'checkout_sale_transactional',
      params: {
        'p_items': normalizedCheckout.toRpcItems(),
        'p_receipt_type': normalizedCheckout.receiptType,
        'p_as_credit': normalizedCheckout.asCredit,
        'p_payment_method': normalizedCheckout.paymentMethod,
        'p_client_id': normalizedCheckout.clientId,
        'p_notes': normalizedCheckout.notes,
      },
    );

    final payload = Map<String, dynamic>.from(rpcResult as Map);
    final saleId = (payload['sale_id'] ?? '').toString();
    if (saleId.isEmpty) {
      throw Exception('No se pudo crear la venta.');
    }

    PreparedPrintJobData? preparedPrintJob;
    final status = (payload['status'] ?? '').toString();
    if (status == 'completed') {
      preparedPrintJob = await prepareCompletedSalePrintJob(saleId: saleId);
    }

    return SaleCheckoutResult(
      saleId: saleId,
      saleNumber: (payload['sale_number'] ?? '').toString(),
      receiptType: (payload['receipt_type'] ?? normalizedCheckout.receiptType)
          .toString(),
      status: status,
      subtotal: _toDouble(payload['subtotal']),
      taxAmount: _toDouble(payload['tax_amount']),
      totalAmount: _toDouble(payload['total_amount']),
      paidAmount: _toDouble(payload['paid_amount']),
      balanceDue: _toDouble(payload['balance_due']),
      itemsCount: _toInt(payload['items_count']),
      cashSessionId: _nullIfEmpty(payload['cash_session_id']?.toString()),
      preparedPrintJob: preparedPrintJob,
    );
  }

  Future<PreparedPrintJobData?> prepareCompletedSalePrintJob({
    required String saleId,
    PrintPaperSize paperSize = PrintPaperSize.thermal80mm,
  }) async {
    final saleRows = await _client
        .from('sales')
        .select(
          'id, branch_id, sale_number, sale_date, receipt_type, status, ncf, notes, '
          'subtotal, discount_amount, tax_amount, total_amount, paid_amount, balance_due, '
          'service_charge_amount, taxable_amount, exempt_amount, '
          'client_id, cashier_id',
        )
        .eq('id', saleId)
        .limit(1);

    if (saleRows.isEmpty) return null;

    final sale = Map<String, dynamic>.from(saleRows.first as Map);
    final status = (sale['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'completed') {
      return null;
    }

    final branchId = (sale['branch_id'] ?? '').toString();
    if (branchId.isEmpty) {
      throw Exception('La venta no tiene sucursal asociada.');
    }

    final branchRows = await _client
        .from('branches')
        .select('name, address, phone')
        .eq('id', branchId)
        .limit(1);
    final branch = branchRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(branchRows.first as Map);

    final clientId = sale['client_id']?.toString();
    Map<String, dynamic> client = const <String, dynamic>{};
    if (clientId != null && clientId.isNotEmpty) {
      final clientRows = await _client
          .from('clients')
          .select(
            'full_name, document_type, document_number, address, phone, email',
          )
          .eq('id', clientId)
          .eq('branch_id', branchId)
          .limit(1);
      if (clientRows.isNotEmpty) {
        client = Map<String, dynamic>.from(clientRows.first as Map);
      }
    }

    final cashierId = sale['cashier_id']?.toString();
    Map<String, dynamic> cashier = const <String, dynamic>{};
    if (cashierId != null && cashierId.isNotEmpty) {
      final cashierRows = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', cashierId)
          .limit(1);
      if (cashierRows.isNotEmpty) {
        cashier = Map<String, dynamic>.from(cashierRows.first as Map);
      }
    }

    final itemRows = await _client
        .from('sale_items')
        .select(
          'description, quantity, unit_price, line_subtotal, line_tax, line_total, '
          'sku_snapshot, unit_name',
        )
        .eq('sale_id', saleId)
        .order('created_at');

    final paymentRows = await _client
        .from('payments')
        .select('payment_method, amount, reference')
        .eq('sale_id', saleId)
        .order('paid_at');

    final saleSource = SalePrintSource(
      saleId: (sale['id'] ?? saleId).toString(),
      branchId: branchId,
      saleNumber: (sale['sale_number'] ?? '').toString(),
      status: (sale['status'] ?? '').toString(),
      saleDate:
          DateTime.tryParse((sale['sale_date'] ?? '').toString()) ??
          DateTime.now(),
      receiptType: (sale['receipt_type'] ?? '').toString(),
      branchName: (branch['name'] ?? 'Sucursal').toString(),
      branchAddress: branch['address']?.toString(),
      branchPhone: branch['phone']?.toString(),
      clientName: client['full_name']?.toString(),
      clientDocument: _buildClientDocumentLabel(
        documentType: client['document_type']?.toString(),
        documentNumber: client['document_number']?.toString(),
      ),
      clientAddress: client['address']?.toString(),
      clientPhone: client['phone']?.toString(),
      clientEmail: client['email']?.toString(),
      cashierName: cashier['full_name']?.toString(),
      ncf: sale['ncf']?.toString(),
      notes: sale['notes']?.toString(),
      items: itemRows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (item) => SalePrintItemSource(
              description: (item['description'] ?? '').toString(),
              quantity: _toDouble(item['quantity']),
              unitPrice: _toDouble(item['unit_price']),
              lineSubtotal: _toDouble(item['line_subtotal']),
              lineTax: _toDouble(item['line_tax']),
              lineTotal: _toDouble(item['line_total']),
              sku: item['sku_snapshot']?.toString(),
              unitLabel: item['unit_name']?.toString(),
            ),
          )
          .toList(growable: false),
      payments: paymentRows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (payment) => SalePrintPaymentSource(
              method: (payment['payment_method'] ?? '').toString(),
              amount: _toDouble(payment['amount']),
              reference: payment['reference']?.toString(),
            ),
          )
          .toList(growable: false),
      subtotal: _toDouble(sale['subtotal']),
      discountAmount: _toDouble(sale['discount_amount']),
      serviceChargeAmount: _toDouble(sale['service_charge_amount']),
      taxAmount: _toDouble(sale['tax_amount']),
      totalAmount: _toDouble(sale['total_amount']),
      paidAmount: _toDouble(sale['paid_amount']),
      balanceDue: _toDouble(sale['balance_due']),
    );

    return _salePrintPreparationService.prepareCompletedSaleReceipt(
      sale: saleSource,
      paperSize: paperSize,
    );
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _buildClientDocumentLabel({
  required String? documentType,
  required String? documentNumber,
}) {
  final normalizedNumber = _nullIfEmpty(documentNumber);
  if (normalizedNumber == null) return null;

  final normalizedType = _nullIfEmpty(documentType);
  if (normalizedType == null) return normalizedNumber;

  return '${normalizedType.toUpperCase()}: $normalizedNumber';
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
  if (value is double) return value.round();
  return int.tryParse(value.toString()) ?? 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
