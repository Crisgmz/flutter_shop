import 'package:flutter_app/features/inventory/data/inventory_import_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

ImportedProductRef _p(
  String id,
  String name, {
  String? sku,
  String? barcode,
  double stock = 0,
}) =>
    ImportedProductRef(
      id: id,
      name: name,
      sku: sku,
      barcode: barcode,
      stock: stock,
    );

void main() {
  group('reconocer productos al re-importar', () {
    test('un producto sin SKU se reconoce por su id y no se crea otra vez',
        () {
      // El caso reportado: se exporta, se ajustan valores y se sube. Sin SKU
      // el producto antes se creaba de nuevo en cada importación.
      final index = InventoryImportIndex()..add(_p('a1', 'Pantalla A26'));

      final match = index.resolve(id: 'a1', name: 'Pantalla A26');

      expect(match.product?.id, 'a1');
    });

    test('el id manda aunque el archivo le haya cambiado el nombre', () {
      final index = InventoryImportIndex()..add(_p('a1', 'Pantalla A26'));

      final match = index.resolve(id: 'a1', name: 'Pantalla Samsung A26');

      expect(match.product?.id, 'a1');
    });

    test('un id de otra sucursal no descarta la fila: sigue por SKU', () {
      final index = InventoryImportIndex()
        ..add(_p('a1', 'Cable USB', sku: 'USB-1'));

      final match = index.resolve(id: 'otro', sku: 'usb-1 ', name: 'Cable');

      expect(match.product?.id, 'a1');
    });

    test('sin id se reconoce por código de barras', () {
      final index = InventoryImportIndex()
        ..add(_p('a1', 'Coca Cola', barcode: '7501055330034'));

      final match = index.resolve(barcode: '7501055330034', name: 'Coca');

      expect(match.product?.id, 'a1');
    });

    test('archivo viejo sin id: se reconoce por nombre si es único', () {
      final index = InventoryImportIndex()
        ..add(_p('a1', 'Pantalla  Redmi 13C'))
        ..add(_p('a2', 'Pantalla Redmi 14C'));

      final match = index.resolve(name: 'pantalla redmi 13c');

      expect(match.product?.id, 'a1');
    });

    test('nombre repetido sin otra llave: no adivina ni duplica', () {
      // Es el estado en que quedaron los negocios con el bug: el mismo
      // producto dos veces. Elegir uno al azar dejaría el otro desfasado.
      final index = InventoryImportIndex()
        ..add(_p('a1', 'Vortex CB68'))
        ..add(_p('a2', 'Vortex CB68'));

      final match = index.resolve(name: 'Vortex CB68');

      expect(match.product, isNull);
      expect(match.ambiguous, 2);
    });

    test('mismo nombre con otro SKU es otro producto: se crea', () {
      final index = InventoryImportIndex()
        ..add(_p('a1', 'Forro iPhone', sku: 'F-11'));

      final match = index.resolve(sku: 'F-12', name: 'Forro iPhone');

      expect(match.product, isNull);
      expect(match.ambiguous, 0);
    });

    test('un producto recién creado en la importación se reconoce después',
        () {
      final index = InventoryImportIndex();
      expect(index.resolve(name: 'Nuevo').product, isNull);

      index.add(_p('n1', 'Nuevo'));

      expect(index.resolve(name: 'Nuevo').product?.id, 'n1');
    });
  });
}
