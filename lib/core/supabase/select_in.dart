import 'package:supabase_flutter/supabase_flutter.dart';

/// Ids por petición en los filtros `in.(...)`. Cada UUID ocupa unos 45
/// caracteres en la URL: con cientos de ids la petición pasa el límite del
/// servidor y el navegador responde "Failed to fetch".
const _chunkSize = 80;

/// Filas de [table] cuyo [column] está en [values], en grupos de 80 ids
/// paginados de 1000 en 1000 y pedidos de 6 en 6.
///
/// Sirve para traer datos relacionados (la venta y los pagos de una lista de
/// comprobantes) sin unir tablas en una sola consulta: con la RLS de por
/// medio, Postgres puede resolver esa unión recorriendo todo el historial de
/// la sucursal y la consulta muere por tiempo (57014). Por id, cada grupo
/// usa su índice.
Future<List<Map<String, dynamic>>> selectIn(
  SupabaseClient client, {
  required String table,
  required String columns,
  required String column,
  required Iterable<String> values,
}) async {
  final ids = values.where((v) => v.isNotEmpty).toSet().toList(growable: false);
  if (ids.isEmpty) return const [];

  Future<List<Map<String, dynamic>>> fetchChunk(List<String> chunk) async {
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await client
          .from(table)
          .select(columns)
          .inFilter(column, chunk)
          .order('id')
          .range(offset, offset + pageSize - 1);
      rows.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
      if (page.length < pageSize) break;
      offset += page.length;
    }
    return rows;
  }

  final chunks = [
    for (var i = 0; i < ids.length; i += _chunkSize)
      ids.sublist(
        i,
        i + _chunkSize > ids.length ? ids.length : i + _chunkSize,
      ),
  ];
  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < chunks.length; i += 6) {
    final batch = await Future.wait(chunks.skip(i).take(6).map(fetchChunk));
    for (final rows in batch) {
      result.addAll(rows);
    }
  }
  return result;
}
