import 'package:flutter_app/features/printing/data/pdf_receipt_builder.dart';
import 'package:flutter_app/features/printing/data/printing_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

/// Alturas de página (en puntos) del PDF generado, leídas de los /MediaBox.
List<double> _pageHeights(List<int> bytes) {
  final raw = String.fromCharCodes(bytes.where((b) => b < 128));
  return RegExp(r'/MediaBox\s*\[\s*0\s+0\s+[\d.]+\s+([\d.]+)\s*\]')
      .allMatches(raw)
      .map((m) => double.parse(m.group(1)!))
      .toList(growable: false);
}

PrintDocumentData _sale(int lines) => PrintDocumentData(
      documentType: PrintDocumentType.saleReceipt,
      documentNumber: 'FA-000316',
      issuedAt: DateTime(2026, 9, 3),
      branch: const PrintBranchIdentity(
        name: 'BEBEDIZO DRINK S.R.L.',
        address: 'AV. HERMANAS MIRABAL N 1, VILLA MELLA',
        phone: '809-797-8635',
        taxId: '131974602',
      ),
      items: [
        for (var i = 0; i < lines; i++)
          PrintDocumentItem(
            description: 'BRUGAL DOBLE RESERVA 350ML lote $i',
            quantity: 24,
            unitPrice: 435,
            lineSubtotal: 10440,
            lineTax: 0,
            lineTotal: 10440,
          ),
      ],
      totals: PrintTotals(
        subtotal: 10440.0 * lines,
        tax: 0,
        total: 10440.0 * lines,
        paid: 10440.0 * lines,
      ),
    );

void main() {
  const a4Height = 297 * PdfPageFormat.mm;

  group('ticket térmico', () {
    test('una venta corta sale en una sola página ajustada al contenido',
        () async {
      final bytes = await const PdfReceiptBuilder().buildThermalBytes(_sale(3));
      final heights = _pageHeights(bytes);

      expect(heights, hasLength(1));
      // Ajustada al contenido: ni de 297mm fijos ni recortada.
      expect(heights.single, lessThan(a4Height));
      expect(heights.single, greaterThan(0));
    });

    test('una factura larga sale de una sola tirada, no en hojas', () async {
      // El rollo térmico es papel continuo: la factura tiene que salir entera
      // de un tirón. Partirla en hojas de 297mm imprimía la misma venta en dos
      // pedazos separados.
      final bytes = await const PdfReceiptBuilder().buildThermalBytes(_sale(14));
      final heights = _pageHeights(bytes);

      expect(heights, hasLength(1));
      expect(heights.single, greaterThan(a4Height));
    });

    test('el ticket crece en alto, no en páginas, al sumar líneas', () async {
      const builder = PdfReceiptBuilder();
      final medium = _pageHeights(await builder.buildThermalBytes(_sale(14)));
      final long = _pageHeights(await builder.buildThermalBytes(_sale(40)));

      expect(medium, hasLength(1));
      expect(long, hasLength(1));
      expect(long.single, greaterThan(medium.single));
    });
  });
}
