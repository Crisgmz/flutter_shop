import 'package:flutter/material.dart';
import 'package:flutter_app/features/inventory/data/inventory_repository.dart';
import 'package:flutter_app/features/inventory/presentation/product_form_dialog.dart';
import 'package:flutter_app/features/settings/data/app_settings.dart';
import 'package:flutter_app/features/settings/presentation/app_settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettings extends AppSettingsController {
  _FakeSettings(this.raw);
  final Map<String, dynamic> raw;
  @override
  Future<AppSettings> build() async => AppSettings(raw);
}

final _product = InventoryProduct(
  id: 'p1',
  name: 'pantalla zte L8',
  sku: 'l8pa',
  barcode: null,
  categoryId: null,
  categoryName: null,
  unit: 'unidad',
  cost: 400,
  price: 525,
  taxRate: 0,
  stock: 4,
  minStock: 0,
  isActive: true,
  imeis: const ['351234567890'],
);

Future<List<InventoryProductInput?>> _open(
  WidgetTester tester,
  Map<String, dynamic> settings,
) async {
  final view = tester.view;
  view.physicalSize = const Size(1400, 2400);
  view.devicePixelRatio = 1;
  addTearDown(view.reset);
  // La fuente de `flutter test` hace cada letra un cuadrado y desborda el
  // menú de ITBIS (código de antes); con fuente real cabe.
  final onError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    onError?.call(details);
  };
  addTearDown(() => FlutterError.onError = onError);
  final results = <InventoryProductInput?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWith(() => _FakeSettings(settings)),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                await showDialog<InventoryProductInput>(
                  context: context,
                  builder: (_) => ProductFormDialog(
                    categories: const [],
                    initial: _product,
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return results;
}

TextField _field(WidgetTester tester, String label) => tester.widget<TextField>(
      find.ancestor(of: find.text(label), matching: find.byType(TextField)).first,
    );

void main() {
  testWidgets('de fábrica Stock e IMEI vienen bloqueados', (tester) async {
    final results = await _open(tester, const {});
    expect(_field(tester, 'Stock').enabled, isFalse);
    expect(find.textContaining('Bloqueado: se cambia con Compras'), findsOneWidget);
    expect(find.textContaining('Bloqueado: los IMEI entran por Compras'),
        findsOneWidget);
    // El IMEI que ya tiene se ve, pero no se puede quitar.
    expect(find.text('351234567890'), findsOneWidget);
    expect(
      tester.widget<Chip>(find.byType(Chip)).onDeleted,
      isNull,
    );

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final input = results.single!;
    expect(input.applyStock, isFalse);
    expect(input.applyImeis, isFalse);
  });

  testWidgets('desbloqueado, solo manda el stock si se cambió',
      (tester) async {
    final results = await _open(tester, const {
      'inv_allow_product_stock_edit': true,
      'inv_allow_product_imei_edit': true,
    });
    expect(_field(tester, 'Stock').enabled, isTrue);

    final stockField = find.ancestor(
      of: find.text('Stock'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(stockField, '10');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final input = results.single!;
    expect(input.applyStock, isTrue);
    expect(input.stock, 10);
    // Los IMEIs no se tocaron: no se reescriben.
    expect(input.applyImeis, isFalse);
  });

  testWidgets('desbloqueado pero sin tocar el stock no lo pisa',
      (tester) async {
    final results = await _open(tester, const {
      'inv_allow_product_stock_edit': true,
    });
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(results.single!.applyStock, isFalse);
  });
}
