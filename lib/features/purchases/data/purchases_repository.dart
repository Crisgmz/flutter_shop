import 'package:supabase_flutter/supabase_flutter.dart';

class PurchaseSupplier {
  PurchaseSupplier({required this.id, required this.name});

  final String id;
  final String name;

  factory PurchaseSupplier.fromMap(Map<String, dynamic> map) {
    return PurchaseSupplier(
      id: (map['id'] ?? '').toString(),
      name: (map['legal_name'] ?? '').toString(),
    );
  }
}

class PurchaseProduct {
  PurchaseProduct({
    required this.id,
    required this.name,
    required this.cost,
    required this.stock,
    this.sku,
    this.barcode,
    this.unit,
  });

  final String id;
  final String name;
  final double cost;
  final double stock;
  final String? sku;
  final String? barcode;
  final String? unit;

  factory PurchaseProduct.fromMap(Map<String, dynamic> map) {
    return PurchaseProduct(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      cost: _toDouble(map['cost']),
      stock: _toDouble(map['stock']),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      unit: (map['sale_unit'] ?? map['unit'])?.toString(),
    );
  }
}

class PurchaseSummary {
  PurchaseSummary({
    required this.id,
    required this.purchaseNumber,
    required this.invoiceNumber,
    required this.supplierName,
    required this.status,
    required this.purchaseDate,
    required this.totalAmount,
    this.paymentStatus = 'pending',
    this.purchaseCategory,
    this.expectedAt,
    this.receivedAt,
    this.linesCount = 0,
    this.itemsQuantity = 0,
    this.receivedQuantity = 0,
  });

  final String id;
  final String? purchaseNumber;
  final String? invoiceNumber;
  final String supplierName;
  final String status;
  final String paymentStatus;
  final String? purchaseCategory;
  final DateTime purchaseDate;
  final DateTime? expectedAt;
  final DateTime? receivedAt;
  final double totalAmount;
  final int linesCount;
  final double itemsQuantity;
  final double receivedQuantity;

  double get receiptProgress =>
      itemsQuantity <= 0 ? 0 : (receivedQuantity / itemsQuantity).clamp(0, 1);

  factory PurchaseSummary.fromMap(Map<String, dynamic> map) {
    return PurchaseSummary(
      id: (map['id'] ?? '').toString(),
      purchaseNumber: map['purchase_number']?.toString(),
      invoiceNumber: map['invoice_number']?.toString(),
      supplierName: (map['supplier_name'] ?? '-').toString(),
      status: (map['status'] ?? '').toString(),
      paymentStatus: (map['payment_status'] ?? 'pending').toString(),
      purchaseCategory: map['purchase_category']?.toString(),
      purchaseDate:
          DateTime.tryParse((map['purchase_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expectedAt: map['expected_at'] == null
          ? null
          : DateTime.tryParse(map['expected_at'].toString()),
      receivedAt: map['received_at'] == null
          ? null
          : DateTime.tryParse(map['received_at'].toString()),
      totalAmount: _toDouble(map['total_amount']),
      linesCount: _toInt(map['lines_count']),
      itemsQuantity: _toDouble(map['items_quantity']),
      receivedQuantity: _toDouble(map['received_quantity']),
    );
  }
}

class PurchaseLineInput {
  PurchaseLineInput({
    required this.product,
    required this.quantity,
    required this.unitCost,
    required this.taxRate,
    this.notes,
  });

  final PurchaseProduct product;
  final double quantity;
  final double unitCost;
  final double taxRate;
  final String? notes;

  double get lineSubtotal => _round2(quantity * unitCost);
  double get lineTax => _round2(lineSubtotal * (taxRate / 100));
  double get lineTotal => _round2(lineSubtotal + lineTax);
}

class PurchaseCreateInput {
  PurchaseCreateInput({
    required this.supplierId,
    required this.purchaseDate,
    required this.items,
    this.invoiceNumber,
    this.notes,
    this.paymentStatus = 'pending',
    this.purchaseCategory,
    this.expectedAt,
  });

  final String supplierId;
  final DateTime purchaseDate;
  final List<PurchaseLineInput> items;
  final String? invoiceNumber;
  final String? notes;
  final String paymentStatus;
  final String? purchaseCategory;
  final DateTime? expectedAt;
}

class PurchasesRepository {
  PurchasesRepository(this._client);

  final SupabaseClient _client;

  Future<List<PurchaseSupplier>> fetchSuppliers() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('suppliers')
        .select('id, legal_name')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('legal_name');

    return rows
        .map(
          (item) =>
              PurchaseSupplier.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<PurchaseProduct>> fetchProducts() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('products')
        .select('id, name, cost, stock, sku, barcode, sale_unit, unit')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');

    return rows
        .map(
          (item) =>
              PurchaseProduct.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<PurchaseSummary>> fetchPurchases() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('purchase_operational_view')
        .select(
          'id, purchase_number, invoice_number, supplier_name, status, '
          'payment_status, purchase_category, purchase_date, expected_at, '
          'received_at, total_amount, lines_count, items_quantity, received_quantity',
        )
        .eq('branch_id', branchId)
        .order('purchase_date', ascending: false)
        .limit(100);

    return rows
        .map(
          (item) =>
              PurchaseSummary.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<void> createPurchase(PurchaseCreateInput input) async {
    if (input.items.isEmpty) {
      throw Exception('Agrega al menos un artículo.');
    }

    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final subtotal = _round2(
      input.items.fold<double>(0, (sum, item) => sum + item.lineSubtotal),
    );
    final taxAmount = _round2(
      input.items.fold<double>(0, (sum, item) => sum + item.lineTax),
    );
    final totalAmount = _round2(subtotal + taxAmount);

    final purchaseNumber = _buildPurchaseNumber();

    final createdPurchase = await _client
        .from('purchases')
        .insert({
          'branch_id': branchId,
          'supplier_id': input.supplierId,
          'purchase_number': purchaseNumber,
          'invoice_number': _nullIfEmpty(input.invoiceNumber),
          'status': 'posted',
          'payment_status': input.paymentStatus,
          'purchase_category': _nullIfEmpty(input.purchaseCategory),
          'purchase_date': input.purchaseDate.toIso8601String().split('T').first,
          'expected_at': input.expectedAt?.toIso8601String(),
          'notes': _nullIfEmpty(input.notes),
          'subtotal': subtotal,
          'discount_amount': 0,
          'tax_amount': taxAmount,
          'total_amount': totalAmount,
        })
        .select('id')
        .single();

    final purchaseId = (createdPurchase['id'] ?? '').toString();
    if (purchaseId.isEmpty) {
      throw Exception('No se pudo crear la compra.');
    }

    final linePayload = input.items
        .map(
          (line) => {
            'purchase_id': purchaseId,
            'branch_id': branchId,
            'product_id': line.product.id,
            'description': line.product.name,
            'product_name_snapshot': line.product.name,
            'sku_snapshot': line.product.sku,
            'barcode_snapshot': line.product.barcode,
            'unit_name': line.product.unit,
            'quantity': line.quantity,
            'received_quantity': 0,
            'unit_cost': line.unitCost,
            'discount_amount': 0,
            'tax_rate': line.taxRate,
            'line_subtotal': line.lineSubtotal,
            'line_tax': line.lineTax,
            'line_total': line.lineTotal,
            'notes': _nullIfEmpty(line.notes),
          },
        )
        .toList(growable: false);

    await _client.from('purchase_items').insert(linePayload);

    for (final line in input.items) {
      await _client
          .from('products')
          .update({'cost': line.unitCost})
          .eq('id', line.product.id)
          .eq('branch_id', branchId);
    }
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

String _buildPurchaseNumber() {
  final now = DateTime.now();
  final y = now.year.toString();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  final ss = now.second.toString().padLeft(2, '0');
  final ms = now.millisecond.toString().padLeft(3, '0');
  return 'COMP-$y$m$d-$hh$mm$ss$ms';
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
