import 'package:flutter/material.dart';
import 'package:flutter_app/features/clients/data/clients_repository.dart';
import 'package:flutter_app/features/clients/presentation/clients_page.dart';
import 'package:flutter_app/features/clients/presentation/clients_providers.dart';
import 'package:flutter_app/shared/widgets/role_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio falso: solo lo que usa el historial.
class _FakeRepo implements ClientsRepository {
  @override
  Future<List<ClientSaleRow>> fetchSalesForClient(String clientId,
          {int limit = 1000}) async =>
      [
        ClientSaleRow(
          id: 's1',
          number: 'FA-000117',
          date: DateTime(2026, 10, 2, 16, 3),
          total: 3719.40,
          paid: 0,
          balance: 3719.40,
          status: 'credit',
          dueDate: DateTime(2026, 11, 1),
        ),
        ClientSaleRow(
          id: 's2',
          number: 'FA-000041',
          date: DateTime(2026, 8, 31, 13, 5),
          total: 550,
          paid: 550,
          balance: 0,
          status: 'completed',
        ),
        ClientSaleRow(
          id: 's3',
          number: 'FA-000032',
          date: DateTime(2026, 8, 24, 12, 28),
          total: 2720,
          paid: 0,
          balance: 0,
          status: 'voided',
        ),
      ];

  @override
  Future<List<ClientPaymentRow>> fetchPaymentsForClient(String clientId,
          {int limit = 1000}) async =>
      [
        ClientPaymentRow(
          id: 'p1',
          amount: 550,
          paymentMethod: 'cash',
          paidAt: DateTime(2026, 8, 31, 13, 5),
          saleId: 's2',
          saleNumber: 'FA-000041',
        ),
        ClientPaymentRow(
          id: 'p2',
          amount: 300,
          paymentMethod: 'transfer',
          paidAt: DateTime(2026, 9, 19, 14, 3),
        ),
      ];

  @override
  Future<List<ClientReturnRow>> fetchReturnsForClient(String clientId,
          {int limit = 1000}) async =>
      [
        ClientReturnRow(
          id: 'r1',
          number: 'NC-00004',
          date: DateTime(2026, 9, 17, 15, 29),
          total: 1000,
          refundMethod: 'credit_note',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _client = ClientEntity(
  id: 'c1',
  fullName: 'yoel cel',
  entityType: 'person',
  legalName: null,
  email: null,
  phone: null,
  address: null,
  documentType: null,
  documentNumber: null,
  creditLimit: 0,
  balanceDue: 3719.40,
  isActive: true,
);

Future<void> _open(WidgetTester tester) async {
  final view = tester.view;
  view.physicalSize = const Size(1400, 1000);
  view.devicePixelRatio = 1;
  addTearDown(view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clientsRepositoryProvider.overrideWithValue(_FakeRepo()),
        clientCreditBalancesProvider.overrideWith((ref) async => {'c1': 1000}),
        roleAccessProvider.overrideWithValue(
          const RoleAccess(roleCode: 'admin'),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showClientHistoryDialog(context, _client),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('junta ventas, pagos y devoluciones con sus etiquetas',
      (tester) async {
    await _open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Historial del cliente'), findsOneWidget);
    expect(find.text('6 movimientos'), findsOneWidget);
    expect(find.text('Crédito'), findsOneWidget);
    expect(find.text('Contado'), findsOneWidget);
    expect(find.text('Anulada'), findsOneWidget);
    expect(find.text('Devolución'), findsOneWidget);
    expect(find.text('Nota de crédito'), findsOneWidget);
    expect(find.text('Transferencia'), findsOneWidget);
    expect(find.text('Pendiente: RD\$ 3,719.40'), findsOneWidget);
    // Comprado no cuenta la anulada; deuda y saldo a favor del cliente.
    expect(find.text('Comprado: RD\$ 4,269.40'), findsOneWidget);
    expect(find.text('Pagado: RD\$ 850.00'), findsOneWidget);
    expect(find.text('A favor: RD\$ 1,000.00'), findsOneWidget);
    // Ojito en ventas, devolución y el pago con factura; no en el abono suelto.
    expect(find.byTooltip('Ver factura'), findsNWidgets(5));
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Desde – hasta'), findsOneWidget);
  });
}
