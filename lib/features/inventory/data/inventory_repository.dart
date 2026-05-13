import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryCategory {
  InventoryCategory({
    required this.id,
    required this.name,
    this.colorHex,
    this.iconName,
    this.sortOrder = 0,
    this.parentId,
  });

  final String id;
  final String name;
  final String? colorHex;
  final String? iconName;
  final int sortOrder;
  final String? parentId;

  factory InventoryCategory.fromMap(Map<String, dynamic> map) {
    return InventoryCategory(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      colorHex: map['color_hex']?.toString(),
      iconName: map['icon_name']?.toString(),
      sortOrder: (map['sort_order'] as int?) ?? 0,
      parentId: map['parent_id']?.toString(),
    );
  }
}

class InventoryProduct {
  InventoryProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.categoryId,
    required this.categoryName,
    required this.unit,
    required this.cost,
    required this.price,
    required this.taxRate,
    required this.stock,
    required this.minStock,
    required this.isActive,
    this.internalCode,
    this.brand,
    this.model,
    this.imageUrl,
    this.notes,
    this.isService = false,
    this.isTaxExempt = false,
    this.trackInventory = true,
    this.sizeLabel,
    this.variantName,
    this.purchaseUnit,
    this.reorderLevel = 0,
    this.maxStock = 0,
    this.allowNegativeStock = false,
    this.priceTier1,
    this.priceTier2,
    this.priceTier3,
  });

  final String id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? categoryName;
  final String unit;
  final double cost;
  final double price;
  final double taxRate;
  final double stock;
  final double minStock;
  final bool isActive;

  final String? internalCode;
  final String? brand;
  final String? model;
  final String? imageUrl;
  final String? notes;
  final bool isService;
  final bool isTaxExempt;
  final bool trackInventory;
  final String? sizeLabel;
  final String? variantName;
  final String? purchaseUnit;
  final double reorderLevel;
  final double maxStock;
  final bool allowNegativeStock;
  final double? priceTier1;
  final double? priceTier2;
  final double? priceTier3;

  bool get isLowStock => !isService && trackInventory && stock <= minStock;

  factory InventoryProduct.fromMap(
    Map<String, dynamic> map,
    Map<String, String> categoryNames,
  ) {
    final categoryId = map['category_id']?.toString();

    return InventoryProduct(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      categoryId: categoryId,
      categoryName: categoryId == null ? null : categoryNames[categoryId],
      unit: (map['sale_unit'] ?? map['unit'] ?? 'unidad').toString(),
      cost: _toDouble(map['cost']),
      price: _toDouble(map['price']),
      taxRate: _toDouble(map['tax_rate']),
      stock: _toDouble(map['stock']),
      minStock: _toDouble(map['min_stock']),
      isActive: map['is_active'] == true,
      internalCode: map['internal_code']?.toString(),
      brand: map['brand']?.toString(),
      model: map['model']?.toString(),
      imageUrl: map['image_url']?.toString(),
      notes: map['notes']?.toString(),
      isService: map['is_service'] == true,
      isTaxExempt: map['is_tax_exempt'] == true,
      trackInventory: map['track_inventory'] != false,
      sizeLabel: map['size_label']?.toString(),
      variantName: map['variant_name']?.toString(),
      purchaseUnit: map['purchase_unit']?.toString(),
      reorderLevel: _toDouble(map['reorder_level']),
      maxStock: _toDouble(map['max_stock']),
      allowNegativeStock: map['allow_negative_stock'] == true,
      priceTier1: map['price_tier_1'] == null ? null : _toDouble(map['price_tier_1']),
      priceTier2: map['price_tier_2'] == null ? null : _toDouble(map['price_tier_2']),
      priceTier3: map['price_tier_3'] == null ? null : _toDouble(map['price_tier_3']),
    );
  }
}

class InventoryProductInput {
  InventoryProductInput({
    required this.name,
    required this.price,
    required this.cost,
    required this.stock,
    required this.minStock,
    required this.taxRate,
    required this.unit,
    required this.isActive,
    this.id,
    this.sku,
    this.barcode,
    this.categoryId,
    this.internalCode,
    this.brand,
    this.model,
    this.imageUrl,
    this.notes,
    this.isService = false,
    this.isTaxExempt = false,
    this.trackInventory = true,
    this.sizeLabel,
    this.variantName,
    this.purchaseUnit,
    this.reorderLevel = 0,
    this.maxStock = 0,
    this.allowNegativeStock = false,
    this.priceTier1,
    this.priceTier2,
    this.priceTier3,
  });

  final String? id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String unit;
  final double cost;
  final double price;
  final double taxRate;
  final double stock;
  final double minStock;
  final bool isActive;
  final String? internalCode;
  final String? brand;
  final String? model;
  final String? imageUrl;
  final String? notes;
  final bool isService;
  final bool isTaxExempt;
  final bool trackInventory;
  final String? sizeLabel;
  final String? variantName;
  final String? purchaseUnit;
  final double reorderLevel;
  final double maxStock;
  final bool allowNegativeStock;
  final double? priceTier1;
  final double? priceTier2;
  final double? priceTier3;
}

class InventoryBulkUpsertError {
  InventoryBulkUpsertError({
    required this.inputIndex,
    required this.productName,
    required this.message,
  });

  final int inputIndex;
  final String productName;
  final String message;
}

class InventoryBulkUpsertResult {
  InventoryBulkUpsertResult({
    required this.inserted,
    required this.updated,
    required this.errors,
  });

  final int inserted;
  final int updated;
  final List<InventoryBulkUpsertError> errors;

  int get total => inserted + updated;
  bool get hasErrors => errors.isNotEmpty;
}

class InventoryRepository {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  Future<List<InventoryCategory>> fetchCategories() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('product_categories')
        .select('id, name, color_hex, icon_name, sort_order, parent_id')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('sort_order')
        .order('name');

    return rows
        .map(
          (item) =>
              InventoryCategory.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<InventoryProduct>> fetchProducts() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final categories = await fetchCategories();
    final categoryNames = <String, String>{
      for (final category in categories) category.id: category.name,
    };

    final rows = await _client
        .from('products')
        .select(
          'id, name, sku, barcode, category_id, unit, sale_unit, cost, price, '
          'tax_rate, stock, min_stock, is_active, '
          'internal_code, brand, model, image_url, notes, '
          'is_service, is_tax_exempt, track_inventory, '
          'size_label, variant_name, purchase_unit, '
          'reorder_level, max_stock, allow_negative_stock, '
          'price_tier_1, price_tier_2, price_tier_3',
        )
        .eq('branch_id', branchId)
        .order('name');

    return rows
        .map(
          (item) => InventoryProduct.fromMap(
            Map<String, dynamic>.from(item as Map),
            categoryNames,
          ),
        )
        .toList(growable: false);
  }

  Future<void> saveProduct(InventoryProductInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final payload = _buildProductPayload(input);

    if (input.id == null) {
      payload['branch_id'] = branchId;
      await _client.from('products').insert(payload);
      return;
    }

    await _client
        .from('products')
        .update(payload)
        .eq('id', input.id!)
        .eq('branch_id', branchId);
  }

  Future<InventoryBulkUpsertResult> bulkUpsertProducts(
    List<InventoryProductInput> inputs,
  ) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final skus = <String>{};
    for (final input in inputs) {
      final sku = input.sku?.trim();
      if (sku != null && sku.isNotEmpty) skus.add(sku);
    }

    final existingBySku = <String, String>{};
    if (skus.isNotEmpty) {
      final rows = await _client
          .from('products')
          .select('id, sku')
          .eq('branch_id', branchId)
          .inFilter('sku', skus.toList(growable: false));
      for (final row in rows) {
        final sku = row['sku']?.toString();
        final id = row['id']?.toString();
        if (sku != null && id != null) existingBySku[sku] = id;
      }
    }

    var inserted = 0;
    var updated = 0;
    final errors = <InventoryBulkUpsertError>[];

    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      try {
        final sku = input.sku?.trim();
        final existingId = (sku != null && sku.isNotEmpty)
            ? existingBySku[sku]
            : null;
        final payload = _buildProductPayload(input);
        if (existingId == null) {
          payload['branch_id'] = branchId;
          await _client.from('products').insert(payload);
          inserted++;
        } else {
          await _client
              .from('products')
              .update(payload)
              .eq('id', existingId)
              .eq('branch_id', branchId);
          updated++;
        }
      } catch (error) {
        errors.add(
          InventoryBulkUpsertError(
            inputIndex: i,
            productName: input.name,
            message: error.toString(),
          ),
        );
      }
    }

    return InventoryBulkUpsertResult(
      inserted: inserted,
      updated: updated,
      errors: errors,
    );
  }

  Map<String, dynamic> _buildProductPayload(InventoryProductInput input) {
    final unitValue = input.unit.trim().isEmpty ? 'unidad' : input.unit.trim();
    return <String, dynamic>{
      'name': input.name.trim(),
      'sku': _nullIfEmpty(input.sku),
      'barcode': _nullIfEmpty(input.barcode),
      'category_id': _nullIfEmpty(input.categoryId),
      'unit': unitValue,
      'sale_unit': unitValue,
      'purchase_unit': _nullIfEmpty(input.purchaseUnit) ?? unitValue,
      'cost': input.cost,
      'price': input.price,
      'tax_rate': input.taxRate,
      'stock': input.stock,
      'min_stock': input.minStock,
      'reorder_level': input.reorderLevel,
      'max_stock': input.maxStock,
      'allow_negative_stock': input.allowNegativeStock,
      'is_active': input.isActive,
      'internal_code': _nullIfEmpty(input.internalCode),
      'brand': _nullIfEmpty(input.brand),
      'model': _nullIfEmpty(input.model),
      'size_label': _nullIfEmpty(input.sizeLabel),
      'variant_name': _nullIfEmpty(input.variantName),
      'image_url': _nullIfEmpty(input.imageUrl),
      'notes': _nullIfEmpty(input.notes),
      'is_service': input.isService,
      'is_tax_exempt': input.isTaxExempt,
      'track_inventory': input.trackInventory,
      'price_tier_1': input.priceTier1 ?? input.price,
      'price_tier_2': input.priceTier2,
      'price_tier_3': input.priceTier3,
    };
  }

  Future<void> setProductActive({
    required String productId,
    required bool isActive,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('products')
        .update({'is_active': isActive})
        .eq('id', productId)
        .eq('branch_id', branchId);
  }

  /// Historial unificado de movimientos de un producto:
  ///   - Ventas (sale_items) → salida
  ///   - Compras (purchase_items) → entrada
  ///   - Movimientos manuales (inventory_movements) → según tipo
  ///   - Devoluciones (return_items) → entrada
  Future<List<ProductMovementEntry>> fetchProductHistory(
    String productId, {
    int limit = 200,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final entries = <ProductMovementEntry>[];

    // Ventas
    final saleItems = await _client
        .from('sale_items')
        .select(
          'quantity, line_total, created_at, sale_id, '
          'sales(sale_number, sale_date, status)',
        )
        .eq('branch_id', branchId)
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .limit(limit);

    for (final raw in saleItems) {
      final row = Map<String, dynamic>.from(raw as Map);
      final sale = row['sales'];
      final saleStatus =
          sale is Map ? (sale['status'] ?? '').toString() : '';
      // Excluir voided del flujo de venta normal.
      if (saleStatus == 'voided') continue;
      entries.add(ProductMovementEntry(
        when: DateTime.tryParse(
              sale is Map
                  ? (sale['sale_date'] ?? row['created_at']).toString()
                  : row['created_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
        kind: ProductMovementKind.sale,
        quantity: -_toDouble(row['quantity']),
        amount: _toDouble(row['line_total']),
        reference:
            sale is Map ? sale['sale_number']?.toString() : null,
      ));
    }

    // Compras
    final purchaseItems = await _client
        .from('purchase_items')
        .select(
          'quantity, line_total, created_at, purchase_id, '
          'purchases(purchase_number, purchase_date, status)',
        )
        .eq('branch_id', branchId)
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .limit(limit);

    for (final raw in purchaseItems) {
      final row = Map<String, dynamic>.from(raw as Map);
      final purchase = row['purchases'];
      final pStatus = purchase is Map
          ? (purchase['status'] ?? '').toString()
          : '';
      if (pStatus == 'cancelled') continue;
      entries.add(ProductMovementEntry(
        when: DateTime.tryParse(
              purchase is Map
                  ? (purchase['purchase_date'] ?? row['created_at'])
                      .toString()
                  : row['created_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
        kind: ProductMovementKind.purchase,
        quantity: _toDouble(row['quantity']),
        amount: _toDouble(row['line_total']),
        reference: purchase is Map
            ? purchase['purchase_number']?.toString()
            : null,
      ));
    }

    // Movimientos manuales (mermas/ajustes/traslados)
    final movements = await _client
        .from('inventory_movements')
        .select(
          'quantity, unit_cost, occurred_at, movement_type, reason, notes',
        )
        .eq('branch_id', branchId)
        .eq('product_id', productId)
        .order('occurred_at', ascending: false)
        .limit(limit);

    for (final raw in movements) {
      final row = Map<String, dynamic>.from(raw as Map);
      final type = (row['movement_type'] ?? '').toString();
      final qty = _toDouble(row['quantity']);
      final cost = _toDouble(row['unit_cost']);
      final isPositive = const {
        'adjustment_in',
        'transfer_in',
        'opening',
        'recount',
      }.contains(type);
      entries.add(ProductMovementEntry(
        when: DateTime.tryParse(row['occurred_at']?.toString() ?? '') ??
            DateTime.now(),
        kind: _movementKindFromType(type),
        quantity: isPositive ? qty : -qty,
        amount: qty * cost,
        reference: type,
        notes: row['reason']?.toString() ?? row['notes']?.toString(),
      ));
    }

    // Devoluciones
    final returnItems = await _client
        .from('return_items')
        .select(
          'quantity, line_total, created_at, return_id, '
          'returns(return_number, return_date)',
        )
        .eq('branch_id', branchId)
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .limit(limit);

    for (final raw in returnItems) {
      final row = Map<String, dynamic>.from(raw as Map);
      final ret = row['returns'];
      entries.add(ProductMovementEntry(
        when: DateTime.tryParse(
              ret is Map
                  ? (ret['return_date'] ?? row['created_at']).toString()
                  : row['created_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
        kind: ProductMovementKind.returnIn,
        quantity: _toDouble(row['quantity']),
        amount: _toDouble(row['line_total']),
        reference:
            ret is Map ? ret['return_number']?.toString() : null,
      ));
    }

    entries.sort((a, b) => b.when.compareTo(a.when));
    return entries;
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

enum ProductMovementKind {
  sale,
  purchase,
  returnIn,
  waste,
  adjustmentIn,
  adjustmentOut,
  transferIn,
  transferOut,
  other;

  String get label {
    switch (this) {
      case ProductMovementKind.sale:
        return 'Venta';
      case ProductMovementKind.purchase:
        return 'Compra';
      case ProductMovementKind.returnIn:
        return 'Devolución';
      case ProductMovementKind.waste:
        return 'Merma';
      case ProductMovementKind.adjustmentIn:
        return 'Ajuste +';
      case ProductMovementKind.adjustmentOut:
        return 'Ajuste -';
      case ProductMovementKind.transferIn:
        return 'Traslado entrada';
      case ProductMovementKind.transferOut:
        return 'Traslado salida';
      case ProductMovementKind.other:
        return 'Otro';
    }
  }
}

ProductMovementKind _movementKindFromType(String type) {
  switch (type) {
    case 'waste':
    case 'breakage':
    case 'expired':
    case 'kitchen_return':
      return ProductMovementKind.waste;
    case 'adjustment_in':
    case 'opening':
    case 'recount':
      return ProductMovementKind.adjustmentIn;
    case 'adjustment_out':
      return ProductMovementKind.adjustmentOut;
    case 'transfer_in':
      return ProductMovementKind.transferIn;
    case 'transfer_out':
      return ProductMovementKind.transferOut;
    default:
      return ProductMovementKind.other;
  }
}

class ProductMovementEntry {
  ProductMovementEntry({
    required this.when,
    required this.kind,
    required this.quantity,
    required this.amount,
    this.reference,
    this.notes,
  });

  final DateTime when;
  final ProductMovementKind kind;

  /// Cantidad con signo: positivo = entrada, negativo = salida.
  final double quantity;
  final double amount;
  final String? reference;
  final String? notes;

  bool get isIncoming => quantity > 0;
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
