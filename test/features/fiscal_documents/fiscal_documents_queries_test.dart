import 'dart:convert';

import 'package:flutter_app/features/fiscal_documents/data/fiscal_documents_repository.dart';
import 'package:flutter_app/features/fiscal_documents/data/fiscal_labels.dart';
// http llega con supabase_flutter; solo se usa para simular PostgREST.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cliente de Supabase contra un PostgREST simulado que anota cada petición.
(SupabaseClient, List<Uri>) _fakeClient(
  Object? Function(Uri uri) respond,
) {
  final requests = <Uri>[];
  final http.Client mock = MockClient((request) async {
    requests.add(request.url);
    return http.Response(
      jsonEncode(respond(request.url)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  });
  return (
    SupabaseClient('https://db.test', 'anon', httpClient: mock),
    requests,
  );
}

void main() {
  test(
      'comprobantes: sin unir ventas ni pagos en la consulta; '
      'se buscan aparte por id y arman el método de pago', () async {
    final (client, requests) = _fakeClient((uri) {
      final path = uri.path;
      if (path.endsWith('/rpc/current_branch_id')) return 'b1';
      if (path.endsWith('/fiscal_documents')) {
        return [
          {
            'id': 'd1',
            'branch_id': 'b1',
            'sale_id': 's1',
            'receipt_type': 'consumer_final',
            'ncf': 'B0200000001',
            'fiscal_status': 'pending',
            'issued_at': '2026-10-15T14:00:00Z',
            'total_amount': 1180,
            'tax_amount': 180,
          },
          {
            'id': 'd2',
            'branch_id': 'b1',
            'sale_id': 's2',
            'receipt_type': 'consumer_final',
            'ncf': 'B0200000002',
            'fiscal_status': 'pending',
            'issued_at': '2026-10-15T15:00:00Z',
            'total_amount': 500,
            'tax_amount': 0,
          },
        ];
      }
      if (path.endsWith('/sales')) {
        return [
          {
            'id': 's1',
            'sale_number': 'V-1',
            'sale_date': '2026-10-15T14:00:00Z',
            'status': 'completed',
          },
          {
            'id': 's2',
            'sale_number': 'V-2',
            'sale_date': '2026-10-15T15:00:00Z',
            'status': 'voided',
          },
        ];
      }
      if (path.endsWith('/payments')) {
        return [
          {
            'sale_id': 's1',
            'payment_method': 'cash',
            'amount': 1000,
            'paid_at': '2026-10-15T14:00:00Z',
            'reference': 'V-1',
          },
          {
            'sale_id': 's1',
            'payment_method': 'card',
            'amount': 180,
            'paid_at': '2026-10-15T14:00:00Z',
            'reference': 'V-1',
          },
        ];
      }
      return const [];
    });

    final docs = await FiscalDocumentsRepository(client).fetchDocuments();

    final docsQuery =
        requests.firstWhere((u) => u.path.endsWith('/fiscal_documents'));
    expect(docsQuery.queryParameters['select'], isNot(contains('sales(')));
    expect(docsQuery.queryParameters['select'], isNot(contains('payments(')));
    // Los 100 más recientes, en el orden del índice (branch_id, issued_at
    // desc), que en Postgres es NULLS FIRST.
    expect(docsQuery.queryParameters['order'], 'issued_at.desc.nullsfirst');
    expect(docsQuery.queryParameters['limit'], '100');

    final salesQuery = requests.firstWhere((u) => u.path.endsWith('/sales'));
    expect(salesQuery.queryParameters['id'], 'in.("s1","s2")');
    final paymentsQuery =
        requests.firstWhere((u) => u.path.endsWith('/payments'));
    expect(paymentsQuery.queryParameters['sale_id'], 'in.("s1","s2")');

    expect(fiscalPaymentLabel(docs[0]), 'Efectivo + Tarjeta');
    expect(docs[0].paymentBreakdown, {'cash': 1000, 'card': 180});
    expect(docs[1].isCancelled, isTrue);
  });

  test('ids en grupos de 80 para no pasar el largo de la URL', () async {
    final (client, requests) = _fakeClient((_) => const []);
    await fetchPaymentsBySale(client, [for (var i = 0; i < 170; i++) 's$i']);
    expect(requests, hasLength(3));
    final sizes = [
      for (final u in requests)
        u.queryParameters['sale_id']!.split(',').length,
    ];
    expect(sizes, [80, 80, 10]);
  });
}
