-- ============================================================================
-- 20261028_103_indice_historial_ventas.sql  —  LÉEME + VERIFICACIÓN
--
-- Historial de ventas daba "PostgrestException ... code: 502" al abrir la
-- pantalla y al buscar facturas (BEBEDIZO, 24-25 oct 2026).
--
-- La pantalla pide las 25 entradas más recientes de la vista
-- `sales_history_entries` (ventas UNION ALL devoluciones):
--
--   where branch_id = X order by doc_date desc nulls last limit 26
--
-- postgrest-dart manda `desc nulls last` con ascending: false. Los índices
-- existentes son `(branch_id, sale_date desc)` y `(branch_id, return_date
-- desc)`, y en Postgres `desc` = `desc NULLS FIRST`: no coinciden, el planner
-- no los usa para ordenar y, con la RLS de por medio, lee y ordena TODAS las
-- ventas y devoluciones de la sucursal en cada carga. Con el historial
-- acumulado la consulta supera el tiempo del servidor y la conexión cae.
-- (Es el mismo caso que la migración 100 resolvió en Cobros.)
--
-- Con índices `desc nulls last` el planner une las dos tablas ya ordenadas
-- (Merge Append) y se detiene en la fila 26: lee 26 filas, no todo.
-- sale_date / return_date son NOT NULL, así que el orden no cambia.
--
-- Solo crea índices: no cambia funciones, vistas ni datos. No hace falta
-- publicar otra versión de la app.
--
-- CÓMO CORRERLA — igual que la 100, un archivo por sentencia:
--
--   20261028_103a_indice_ventas_fecha.sql
--   20261028_103b_indice_devoluciones_fecha.sql
--
-- Para cada uno: SQL Editor vacío → pegar el archivo COMPLETO → Run.
-- `create index concurrently` no bloquea las ventas mientras se construye,
-- pero no puede ir junto con otras sentencias.
--
-- Después, correr ESTE archivo completo: es solo la verificación de abajo.
-- ============================================================================

-- 1) Deben salir las 2 filas con valido = true. Si sale false, quedó a medias:
--    correr `drop index concurrently if exists <nombre>;` (sola) y repetir.
select c.relname as indice, i.indisvalid as valido
  from pg_index i
  join pg_class c on c.oid = i.indexrelid
 where c.relname in ('sales_branch_date_nulls_last_idx',
                     'returns_branch_date_nulls_last_idx');

-- 2) Plan de la consulta del historial para la sucursal con más ventas.
--    Debe aparecer "Merge Append" con dos "Index Scan" sobre los índices
--    nuevos, y un tiempo (Execution Time) de pocos milisegundos.
explain (analyze, buffers)
select id
  from public.sales_history_entries
 where branch_id = (select branch_id
                      from public.sales
                     group by branch_id
                     order by count(*) desc
                     limit 1)
 order by doc_date desc nulls last
 limit 26;

-- ── Plan B: si un archivo 103a/b, pegado SOLO, igual da "cannot run inside a
-- transaction block", correr esto (descomentado, sin `concurrently`) cuando NO
-- se esté vendiendo: mientras se construye cada índice las ventas esperan.
--
-- create index if not exists sales_branch_date_nulls_last_idx
--   on public.sales (branch_id, sale_date desc nulls last);
-- create index if not exists returns_branch_date_nulls_last_idx
--   on public.returns (branch_id, return_date desc nulls last);
