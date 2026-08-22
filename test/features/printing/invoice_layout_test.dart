import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/printing/data/printing.dart';
import 'package:flutter_app/shared/widgets/print_receipt_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cubre el encabezado nuevo de la factura A4 (logo a un lado, empresa
/// centrada, número de documento y NCF junto al cliente), los montos sin
/// símbolo de moneda y la fila del producto en un solo renglón.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final logo = File('assets/shopplus_logo.png').readAsBytesSync();

  PrintDocumentData buildDocument({bool logoOnLeft = true}) {
    return PrintDocumentData(
      logoOnLeft: logoOnLeft,
      documentType: PrintDocumentType.fiscalInvoice,
      documentNumber: 'FA-000005',
      issuedAt: DateTime(2026, 8, 19),
      receiptTypeLabel: 'Consumidor Final',
      ncf: 'B0200000003',
      paymentTermsLabel: 'CONTADO',
      observation: 'Garantía de 1 año en bomba, filtro y calentador.',
      branch: PrintBranchIdentity(
        logoBytes: logo,
        name: 'Maranatha De Todo Para Piscinas SRL',
        address: 'CARRETERA MELLA KM 8/2, LUCERNA, CALLE CENTRAL #58',
        email: 'Maranathadetodoparapiscina@gmail.com',
        phone: '829-876-5564',
        taxId: '132941519',
      ),
      customer: const PrintParty(
        name: 'jacuzzi continental',
        phone: '8295059592',
      ),
      items: const [
        PrintDocumentItem(
          description: 'Bomba Iberia de jacuzzi 2 hp 110v',
          quantity: 2,
          unitPrice: 7500,
          lineSubtotal: 12711.86,
          lineTax: 2288.14,
          lineTotal: 15000,
        ),
        // Nombre desmedido: debe caer al piso de tamaño de letra sin romper
        // la tabla ni recortar el texto.
        PrintDocumentItem(
          description:
              'Calentador eléctrico de titanio para jacuzzi y spa 11kw 220v '
              'con termostato digital incorporado',
          quantity: 1,
          unitPrice: 42000,
          lineSubtotal: 35593.22,
          lineTax: 6406.78,
          lineTotal: 42000,
        ),
      ],
      totals: const PrintTotals(subtotal: 27966.10, tax: 5033.90, total: 33000),
    );
  }

  group('PDF', () {
    test('A4 se genera con el logo a la izquierda y a la derecha', () async {
      for (final left in [true, false]) {
        final bytes =
            await const PdfReceiptBuilder().buildBytes(buildDocument(logoOnLeft: left));
        expect(bytes.length, greaterThan(1000));
      }
    });

    test('el ticket térmico se genera', () async {
      final bytes =
          await const PdfReceiptBuilder().buildThermalBytes(buildDocument());
      expect(bytes.length, greaterThan(500));
    });
  });

  group('vista previa en pantalla', () {
    testWidgets('renderiza el A4 sin overflow', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final document = buildDocument();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrintReceiptDialog(
              printData: PreparedPrintJobData(
                document: document,
                paperSize: PrintPaperSize.a4,
                job: PrintJobDraft(
                  branchId: 'branch-1',
                  documentType: document.documentType,
                  paperSize: PrintPaperSize.a4,
                  payload: const {},
                ),
                dispatchPayload: const {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Los montos van sin el símbolo de moneda.
      expect(find.text('33,000.00'), findsOneWidget);
      expect(find.textContaining(r'RD$'), findsNothing);
      // Número de documento y NCF salieron del encabezado, siguen impresos.
      expect(find.text('FA-000005'), findsOneWidget);
      expect(find.text('NCF: B0200000003'), findsOneWidget);
    });
  });
}
