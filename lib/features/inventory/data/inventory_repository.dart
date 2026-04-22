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

    final unitValue = input.unit.trim().isEmpty ? 'unidad' : input.unit.trim();
    final payload = <String, dynamic>{
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

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
