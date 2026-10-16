import 'dart:convert';

import 'package:flutter_app/features/sales/data/sales_history_repository.dart';
// http llega con supabase_flutter; solo se usa para simular PostgREST.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _saleRow = {
  'entry_kind': 'sale',
  'id': 's1',
  'branch_id': 'b1',
  'doc_number': 'FA-014294',
  'doc_date': '2026-10-15T14:00:00Z',
  'status': 'completed',
  'total_amount': 590,
};

/// Repositorio contra un PostgREST simulado. [historyRows] decide qué
/// devuelve `sales_history_entries` según el filtro `or` de la petición.
(SalesHistoryRepository, List<Uri>) _repo(
  List<Object> Function(String? orFilter) historyRows,
) {
  final requests = <Uri>[];
  final http.Client mock = MockClient((request) async {
    requests.add(request.url);
    final path = request.url.path;
    final Object body = path.endsWith('/rpc/current_branch_id')
        ? 'b1'
        : path.endsWith('/sales_history_entries')
            ? historyRows(request.url.queryParameters['or'])
            : const [];
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  });
  return (
    SalesHistoryRepository(
      SupabaseClient('https://db.test', 'anon', httpClient: mock),
    ),
    requests,
  );
}

List<String?> _historyOrs(List<Uri> requests) => [
      for (final u in requests)
        if (u.path.endsWith('/sales_history_entries'))
          u.queryParameters['or'],
    ];

bool _searchedImei(List<Uri> requests) =>
    requests.any((u) => u.path.endsWith('/sale_items') &&
        u.queryParameters.containsKey('imeis'));

void main() {
  test('número de factura: búsqueda exacta por índice, sin IMEI', () async {
    final (repo, requests) = _repo((_) => [_saleRow]);

    final page = await repo.fetchPage(
      pageIndex: 0,
      filter: const SalesHistoryFilter(search: 'fa-014294'),
    );

    expect(page.rows, hasLength(1));
    expect(_historyOrs(requests), [
      '(doc_number.eq.FA-014294,ncf.eq.FA-014294)',
    ]);
    expect(_searchedImei(requests), isFalse);
  });

  test('NCF completo también va exacto', () async {
    final (repo, requests) = _repo((_) => [_saleRow]);
    await repo.fetchPage(
      pageIndex: 0,
      filter: const SalesHistoryFilter(search: 'b0200001271'),
    );
    expect(_historyOrs(requests), [
      '(doc_number.eq.B0200001271,ncf.eq.B0200001271)',
    ]);
    expect(_searchedImei(requests), isFalse);
  });

  test('si el exacto no aparece, cae a la búsqueda parcial', () async {
    final (repo, requests) = _repo(
      (or) => or!.contains('.eq.') ? const [] : [_saleRow],
    );
    final page = await repo.fetchPage(
      pageIndex: 0,
      filter: const SalesHistoryFilter(search: 'FA-0142'),
    );
    expect(page.rows, hasLength(1));
    expect(_historyOrs(requests), [
      '(doc_number.eq.FA-0142,ncf.eq.FA-0142)',
      '(doc_number.ilike.%FA-0142%,ncf.ilike.%FA-0142%)',
    ]);
    expect(_searchedImei(requests), isFalse);
  });

  test('un IMEI sí se busca en las líneas de venta', () async {
    final (repo, requests) = _repo((_) => const []);
    await repo.fetchPage(
      pageIndex: 0,
      filter: const SalesHistoryFilter(search: '356938035643809'),
    );
    expect(_searchedImei(requests), isTrue);
  });

  test('un número corto no se busca como IMEI', () async {
    final (repo, requests) = _repo((_) => const []);
    await repo.fetchPage(
      pageIndex: 0,
      filter: const SalesHistoryFilter(search: '014294'),
    );
    expect(_historyOrs(requests), [
      '(doc_number.ilike.%014294%,ncf.ilike.%014294%)',
    ]);
    expect(_searchedImei(requests), isFalse);
  });
}
