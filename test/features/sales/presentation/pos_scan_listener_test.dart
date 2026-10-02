import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/sales/presentation/pos_scan_listener.dart';
import 'package:flutter_test/flutter_test.dart';

/// Teclea [text] como lo hace una pistola: tecla por tecla, sin pausas.
Future<void> _type(WidgetTester tester, String text) async {
  for (final ch in text.split('')) {
    final key = LogicalKeyboardKey(ch.toLowerCase().codeUnitAt(0));
    await tester.sendKeyDownEvent(key, character: ch);
    await tester.sendKeyUpEvent(key);
  }
}

void main() {
  late List<String> scans;
  late List<String> typed;

  setUp(() {
    scans = [];
    typed = [];
  });

  Widget pos({Widget? body}) {
    return MaterialApp(
      // InkSparkle (el toque de Material 3) carga un shader que el entorno de
      // pruebas no puede leer; con InkSplash los botones no lo necesitan.
      theme: ThemeData(splashFactory: InkSplash.splashFactory),
      home: Scaffold(
        body: PosScanListener(
          onScan: scans.add,
          onTyped: typed.add,
          child: body ?? const Center(child: Text('POS')),
        ),
      ),
    );
  }

  testWidgets('sin foco en una caja de texto, el escaneo llega con Enter',
      (tester) async {
    await tester.pumpWidget(pos());

    await _type(tester, '7501234567890');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scans, ['7501234567890']);
    expect(typed, isEmpty);
  });

  testWidgets('las pistolas que cierran con Tab también cuentan',
      (tester) async {
    await tester.pumpWidget(pos());

    await _type(tester, 'SKU-77');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scans, ['SKU-77']);
  });

  testWidgets('escribir a mano y hacer una pausa pasa el texto al buscador',
      (tester) async {
    await tester.pumpWidget(pos());

    await _type(tester, 'coca');
    await tester.pump(const Duration(milliseconds: 200));

    expect(typed, ['coca']);
    expect(scans, isEmpty);
  });

  testWidgets('con una caja de texto enfocada no captura nada',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(pos(body: TextField(focusNode: focus)));
    focus.requestFocus();
    await tester.pump();

    await _type(tester, '123');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scans, isEmpty);
    expect(typed, isEmpty);
  });

  testWidgets('con algo del POS enfocado (no una caja de texto) sí captura',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      pos(body: Focus(focusNode: focus, child: const Text('Agregar'))),
    );
    focus.requestFocus();
    await tester.pump();

    await _type(tester, '555');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scans, ['555']);
  });

  testWidgets('con un diálogo abierto encima no captura', (tester) async {
    await tester.pumpWidget(pos());
    final context = tester.element(find.text('POS'));
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        content: TextButton(
          autofocus: true,
          onPressed: () {},
          child: const Text('Cobrar'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _type(tester, '999');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scans, isEmpty);
    expect(typed, isEmpty);
  });

  testWidgets('con otra página encima no captura', (tester) async {
    await tester.pumpWidget(pos());
    final context = tester.element(find.text('POS'));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Historial')),
      ),
    );
    await tester.pumpAndSettle();

    await _type(tester, '999');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scans, isEmpty);
    expect(typed, isEmpty);
  });

  testWidgets('los atajos con Ctrl no se capturan', (tester) async {
    await tester.pumpWidget(pos());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await _type(tester, 'r');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scans, isEmpty);
    expect(typed, isEmpty);
  });

  testWidgets('un Enter sin nada escrito no hace nada', (tester) async {
    await tester.pumpWidget(pos());

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scans, isEmpty);
  });
}
