import 'package:flutter_app/features/inventory/data/inventory_repository.dart';
import 'package:flutter_app/features/inventory/data/product_history_pdf_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// El ejemplo del pedido: samsung A26 con 2 en stock, se vendieron 4 y el
/// conteo físico lo subió a 10 con la nota "estaban encodito".
List<ProductMovementEntry> _history() => [
      ProductMovementEntry(
        when: DateTime(2026, 10, 2, 15, 38),
        kind: ProductMovementKind.adjustmentIn,
        quantity: 8,
        amount: 0,
        movementType: 'adjustment_in',
        reason: 'Conteo físico',
        notes: 'estaban encodito',
        recordedBy: 'Cristian Gómez',
      ),
      ProductMovementEntry(
        when: DateTime(2026, 10, 2, 11, 49),
        kind: ProductMovementKind.sale,
        quantity: -4,
        amount: 2520,
        reference: 'FA-000110',
        party: 'Genérico',
        documentId: 'sale-1',
        document: ProductMovementDocument.sale,
      ),
      ProductMovementEntry(
        when: DateTime(2026, 10, 1, 20, 31),
        kind: ProductMovementKind.sale,
        quantity: -1,
        amount: 630,
        reference: 'FA-000108',
        party: 'Genérico',
        documentId: 'sale-2',
        document: ProductMovementDocument.sale,
      ),
    ];

void main() {
  test('la columna Stock se reconstruye desde el stock actual', () {
    final lines = productMovementLines(_history(), 10);
    expect(lines.map((l) => l.stockAfter), [10, 2, 6]);
    expect(lines.first.stockBefore, 2);
    expect(lines.last.stockBefore, 7);
  });

  test('el ajuste muestra motivo, comentario y usuario', () {
    final adjustment = _history().first;
    expect(adjustment.isManual, isTrue);
    expect(adjustment.typeLabel, 'Ajuste de entrada');
    expect(adjustment.remarks, 'Conteo físico · estaban encodito');
    expect(adjustment.recordedBy, 'Cristian Gómez');
    expect(_history()[1].isManual, isFalse);
  });

  test('genera el PDF del historial y el comprobante del ajuste', () async {
    final lines = productMovementLines(_history(), 10);
    const builder = ProductHistoryPdfBuilder();

    final history = await builder.buildHistory(
      productName: 'samsung A26',
      sku: 'a26pa',
      lines: lines,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 2),
      branchName: 'Sucursal principal',
    );
    expect(String.fromCharCodes(history.take(4)), '%PDF');

    final ticket = await builder.buildMovementTicket(
      productName: 'samsung A26',
      sku: 'a26pa',
      line: lines.first,
      branchName: 'Sucursal principal',
    );
    expect(String.fromCharCodes(ticket.take(4)), '%PDF');
  });
}
