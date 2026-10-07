import 'package:flutter_app/features/printing/data/account_statement.dart';
import 'package:flutter_app/features/printing/data/account_statement_pdf_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los dos créditos de la captura del 2 oct 2026: yax movil (vencido) y
/// YANEISY (vence el 19 oct).
AccountStatement _statement({List<StatementDocument>? documents}) =>
    AccountStatement(
      kind: AccountStatementKind.receivable,
      issuer: const StatementIssuer(name: 'prueba', taxId: '130000000'),
      party: const StatementParty(
        name: 'yax movil',
        document: 'RNC: 131234567',
        phone: '809-555-0101',
      ),
      documents: documents ??
          [
            StatementDocument(
              id: 's1',
              date: DateTime(2026, 8, 14),
              number: 'FA-000004',
              partyName: 'yax movil',
              dueDate: DateTime(2026, 9, 14),
              total: 2360,
              paid: 1500,
              balance: 860,
            ),
            StatementDocument(
              id: 's2',
              date: DateTime(2026, 8, 20),
              number: 'FA-000018',
              reference: 'B0200000292',
              partyName: 'yax movil',
              dueDate: DateTime(2026, 10, 19),
              total: 42000,
              paid: 0,
              balance: 42000,
            ),
          ],
      payments: [
        StatementPayment(
          date: DateTime(2026, 8, 30),
          documentNumber: 'FA-000004',
          method: 'Efectivo',
          amount: 1500,
        ),
      ],
      generatedAt: DateTime(2026, 10, 2, 15, 57),
    );

void main() {
  test('totales, vencido y antigüedad del saldo', () {
    final s = _statement();
    expect(s.totalAmount, 44360);
    expect(s.totalPaid, 1500);
    expect(s.totalBalance, 42860);
    // FA-000004 venció el 14 sept: 18 días al 2 oct.
    expect(s.documents.first.daysOverdue(s.generatedAt), 18);
    expect(s.overdueBalance, 860);
    expect(s.agingBuckets, [42000, 860, 0, 0, 0]);
  });

  test('sin fecha de vencimiento cuenta desde la fecha de la factura', () {
    final d = StatementDocument(
      id: 'x',
      date: DateTime(2026, 6, 1),
      number: 'FA-1',
      partyName: 'c',
      total: 100,
      paid: 0,
      balance: 100,
    );
    expect(d.daysOverdue(DateTime(2026, 10, 2)), 123);
    expect(_statement(documents: [d]).agingBuckets, [0, 0, 0, 0, 100]);
  });

  test('el filtro por fechas cuenta días completos', () {
    final from = DateTime(2026, 9, 1);
    final to = DateTime(2026, 9, 30);
    expect(isWithinStatementDays(DateTime(2026, 9, 30, 23, 59), from, to),
        isTrue);
    expect(isWithinStatementDays(DateTime(2026, 10, 1), from, to), isFalse);
    expect(isWithinStatementDays(DateTime(2026, 8, 31, 23, 59), from, to),
        isFalse);
    expect(isWithinStatementDays(DateTime(2020, 1, 1), null, null), isTrue);
  });

  test('genera el estado de cuenta y el reporte de la lista', () async {
    const builder = AccountStatementPdfBuilder();
    final s = _statement();
    final statement = await builder.buildStatement(s);
    expect(String.fromCharCodes(statement.take(4)), '%PDF');

    final empty = await builder.buildStatement(_statement(documents: []));
    expect(String.fromCharCodes(empty.take(4)), '%PDF');

    final report = await builder.buildPendingReport(
      kind: AccountStatementKind.payable,
      documents: s.documents,
      branchName: 'prueba',
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 31),
      filterLabel: 'Vencidas',
    );
    expect(String.fromCharCodes(report.take(4)), '%PDF');
  });
}
