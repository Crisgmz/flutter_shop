/// Reconocimiento de productos existentes al importar el archivo de
/// inventario.
///
/// Antes la importación solo miraba el SKU: todo producto sin SKU se creaba
/// de nuevo en cada re-importación y el inventario terminaba duplicado. Acá
/// vive la regla completa para poder probarla sin base de datos.
library;

/// Producto de la sucursal tal como lo necesita la importación para
/// reconocer filas. `stock` es mutable: se actualiza al aplicar un ajuste
/// para que una fila repetida no ajuste dos veces sobre el valor viejo.
class ImportedProductRef {
  ImportedProductRef({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.stock,
  });

  final String id;
  final String name;
  final String? sku;
  final String? barcode;
  double stock;
}

/// Resultado de buscar una fila del archivo entre los productos existentes.
/// `product` null = producto nuevo. `ambiguous` > 1 = el nombre coincide con
/// varios productos y no hay otra llave para decidir.
class ImportMatch {
  const ImportMatch(this.product, {this.ambiguous = 0});

  final ImportedProductRef? product;
  final int ambiguous;
}

/// Índice de los productos de la sucursal por cada llave con la que una fila
/// del archivo puede reconocerlos: id → SKU → código de barras → nombre.
class InventoryImportIndex {
  final _byId = <String, ImportedProductRef>{};
  final _bySku = <String, ImportedProductRef>{};
  final _byBarcode = <String, ImportedProductRef>{};
  final _byName = <String, List<ImportedProductRef>>{};

  static String _key(String? raw) => (raw ?? '').trim().toLowerCase();

  static String _nameKey(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  void add(ImportedProductRef product) {
    _byId[product.id] = product;
    final sku = _key(product.sku);
    if (sku.isNotEmpty) _bySku[sku] = product;
    final barcode = _key(product.barcode);
    if (barcode.isNotEmpty) _byBarcode[barcode] = product;
    (_byName[_nameKey(product.name)] ??= []).add(product);
  }

  ImportMatch resolve({
    required String name,
    String? id,
    String? sku,
    String? barcode,
  }) {
    final cleanId = id?.trim();
    if (cleanId != null && cleanId.isNotEmpty) {
      final byId = _byId[cleanId];
      // Un id que no es de esta sucursal (archivo de otra sucursal o producto
      // borrado) no descarta la fila: se sigue buscando por las demás llaves.
      if (byId != null) return ImportMatch(byId);
    }

    final skuKey = _key(sku);
    final bySku = _bySku[skuKey];
    if (skuKey.isNotEmpty && bySku != null) return ImportMatch(bySku);

    final barcodeKey = _key(barcode);
    final byBarcode = _byBarcode[barcodeKey];
    if (barcodeKey.isNotEmpty && byBarcode != null) {
      return ImportMatch(byBarcode);
    }

    // Último recurso: el nombre. Solo cuentan los productos cuyas llaves no
    // contradicen la fila — si la fila trae un SKU y el producto tiene OTRO
    // SKU, son productos distintos que se llaman igual.
    final candidates = (_byName[_nameKey(name)] ?? const [])
        .where(
          (p) =>
              (skuKey.isEmpty || _key(p.sku).isEmpty) &&
              (barcodeKey.isEmpty || _key(p.barcode).isEmpty),
        )
        .toList(growable: false);
    if (candidates.length == 1) return ImportMatch(candidates.single);
    if (candidates.length > 1) {
      return ImportMatch(null, ambiguous: candidates.length);
    }
    return const ImportMatch(null);
  }
}
