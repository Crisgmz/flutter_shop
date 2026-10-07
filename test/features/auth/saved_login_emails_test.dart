import 'package:flutter/material.dart';
import 'package:flutter_app/features/auth/data/saved_login_emails.dart';
import 'package:flutter_app/features/auth/presentation/login_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _clearSaved() {
  for (final email in readSavedLoginEmails()) {
    forgetLoginEmail(email);
  }
}

Future<void> _pumpLogin(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        // El brillo de Material 3 usa un shader que `flutter test` no carga.
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const LoginPage(),
      ),
    ),
  );
}

Finder get _emailField => find.widgetWithText(TextFormField, 'Correo');

void main() {
  setUp(_clearSaved);

  test('guarda solo el correo, sin repetir y el más reciente primero', () {
    rememberLoginEmail('prueba@gmail.com');
    rememberLoginEmail('  Ajr@Gmail.com ');
    rememberLoginEmail('prueba@gmail.com');
    expect(readSavedLoginEmails(), ['prueba@gmail.com', 'ajr@gmail.com']);

    forgetLoginEmail('AJR@gmail.com');
    expect(readSavedLoginEmails(), ['prueba@gmail.com']);
  });

  test('recuerda como máximo 10 correos', () {
    for (var i = 0; i < 12; i++) {
      rememberLoginEmail('cajero$i@tienda.com');
    }
    final saved = readSavedLoginEmails();
    expect(saved, hasLength(10));
    expect(saved.first, 'cajero11@tienda.com');
    expect(saved, isNot(contains('cajero0@tienda.com')));
  });

  testWidgets('sin correos guardados no sale ninguna lista', (tester) async {
    await _pumpLogin(tester);
    await tester.tap(_emailField);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.account_circle_outlined), findsNothing);
    expect(find.byTooltip('Correos guardados'), findsNothing);
  });

  testWidgets('al hacer clic salen los correos; la X borra y elegir llena',
      (tester) async {
    rememberLoginEmail('prueba@gmail.com');
    rememberLoginEmail('dygte@gmail.com');
    rememberLoginEmail('ajr@gmail.com');
    await _pumpLogin(tester);

    await tester.tap(_emailField);
    await tester.pumpAndSettle();
    for (final email in ['ajr@gmail.com', 'dygte@gmail.com', 'prueba@gmail.com']) {
      expect(find.text(email), findsOneWidget);
    }

    // La X quita ese correo para siempre y la lista sigue abierta.
    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.text('dygte@gmail.com'),
        matching: find.byType(Row),
      ),
      matching: find.byIcon(Icons.close),
    ));
    await tester.pumpAndSettle();
    expect(find.text('dygte@gmail.com'), findsNothing);
    expect(find.text('ajr@gmail.com'), findsOneWidget);
    expect(readSavedLoginEmails(), ['ajr@gmail.com', 'prueba@gmail.com']);

    // Elegir uno lo pone en el campo, cierra la lista y pasa a la clave.
    await tester.tap(find.text('prueba@gmail.com'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextFormField>(_emailField);
    expect(field.controller!.text, 'prueba@gmail.com');
    expect(find.byIcon(Icons.account_circle_outlined), findsNothing);
    final passwordField = tester.widget<EditableText>(find.descendant(
      of: find.widgetWithText(TextFormField, 'Clave'),
      matching: find.byType(EditableText),
    ));
    expect(passwordField.focusNode.hasFocus, isTrue);
  });

  testWidgets('escribir filtra la lista', (tester) async {
    rememberLoginEmail('prueba@gmail.com');
    rememberLoginEmail('ajr@gmail.com');
    await _pumpLogin(tester);

    await tester.tap(_emailField);
    await tester.enterText(_emailField, 'aj');
    await tester.pumpAndSettle();
    // El campo también muestra lo escrito; el correo completo solo en la lista.
    expect(find.text('ajr@gmail.com'), findsOneWidget);
    expect(find.text('prueba@gmail.com'), findsNothing);

    await tester.enterText(_emailField, 'nadie');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.account_circle_outlined), findsNothing);
  });
}
