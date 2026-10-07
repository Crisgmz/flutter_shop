import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/clients/data/clients_repository.dart';
import 'package:flutter_app/features/clients/presentation/client_form_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Abre el cuadro de "Nuevo cliente" y guarda lo que devuelva al cerrarse.
Future<List<ClientInput?>> _open(WidgetTester tester) async {
  final results = <ClientInput?>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        // El brillo de Material 3 usa un shader que `flutter test` no carga.
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    results.add(await ClientFormDialog.show(context)),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(find.text('Nuevo cliente'), findsOneWidget);
  return results;
}

Finder get _nameField =>
    find.widgetWithText(TextFormField, 'Nombre completo / Razón comercial');

void main() {
  setUp(() {
    // El formulario es largo: pantalla de escritorio para que quepa.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1400, 1000);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
  });

  testWidgets('un clic afuera ya no lo cierra', (tester) async {
    await _open(tester);
    await tester.enterText(_nameField, 'yoel cel');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo cliente'), findsOneWidget);
    expect(find.text('yoel cel'), findsOneWidget);
  });

  testWidgets('la X sin cambios cierra de una vez', (tester) async {
    final results = await _open(tester);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo cliente'), findsNothing);
    expect(results, [null]);
  });

  testWidgets('con algo escrito, la X pregunta antes de descartar',
      (tester) async {
    final results = await _open(tester);
    await tester.enterText(_nameField, 'yoel cel');

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar el cliente nuevo?'), findsOneWidget);

    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo cliente'), findsOneWidget);
    expect(find.text('yoel cel'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo cliente'), findsNothing);
    expect(results, [null]);
  });

  testWidgets('Esc tampoco lo cierra', (tester) async {
    await _open(tester);
    await tester.enterText(_nameField, 'yoel cel');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Nuevo cliente'), findsOneWidget);
    expect(find.text('yoel cel'), findsOneWidget);
  });

  testWidgets('Guardar devuelve el cliente sin preguntar', (tester) async {
    final results = await _open(tester);
    await tester.enterText(_nameField, 'yoel cel');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo cliente'), findsNothing);
    expect(results.single?.fullName, 'yoel cel');
  });
}
