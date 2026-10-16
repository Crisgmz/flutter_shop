-- ============================================================================
-- 20261016_100_indices_cobros.sql  —  LÉEME + VERIFICACIÓN
--
-- Cobros daba "canceling statement due to statement timeout (57014)" en las
-- tres secciones (BEBEDIZO, 16 oct 2026). Ninguna de sus consultas tenía un
-- índice que la cubriera y, con la RLS de por medio, cada una recorría todo
-- el historial:
--
--   1) Pagos recibidos: los 30 más recientes de la sucursal
--      (payments where branch_id = X order by paid_at desc limit 30).
--      `payments` solo tenía índices por sale_id y client_id → leía y
--      ordenaba TODOS los pagos.
--   2) Cuentas por cobrar: ventas de la sucursal con balance_due > 0.
--      El índice parcial idx_sales_credit_due_date exige status = 'credit'
--      y la consulta pide credit/pending/completed → no aplicaba; recorría
--      todas las ventas de la sucursal.
--   3) Saldos por cliente (customer_balances_view): une clientes con sus
--      ventas por client_id, y `sales` no tenía índice por client_id.
--
-- Solo crea índices: no cambia funciones, vistas ni datos. La base es
-- compartida con shop-plus y no le afecta (solo la acelera). Los órdenes
-- coinciden con lo que ya manda la app (`desc nulls last` es lo que pide
-- postgrest-dart con ascending: false): no hace falta publicar otra versión.
--
-- CÓMO CORRERLA — los índices van en TRES ARCHIVOS APARTE, uno por sentencia:
--
--   20261016_100a_indice_pagos_recientes.sql
--   20261016_100b_indice_saldo_pendiente.sql
--   20261016_100c_indice_ventas_por_cliente.sql
--
-- Para cada uno: SQL Editor vacío → pegar el archivo COMPLETO → Run.
-- `create index concurrently` no bloquea las ventas mientras se construye,
-- pero Postgres lo rechaza si va junto con otras sentencias ("cannot run
-- inside a transaction block"); por eso no pueden ir en un mismo archivo.
--
-- Después, correr ESTE archivo completo: es solo la verificación de abajo.
-- ============================================================================

-- Deben salir las 3 filas con valido = true. Si alguna falta, no se ha
-- corrido su archivo. Si sale false, quedó a medias: correr
-- `drop index concurrently if exists <nombre>;` (sola) y repetir su archivo.
select c.relname as indice, i.indisvalid as valido
  from pg_index i
  join pg_class c on c.oid = i.indexrelid
 where c.relname in ('payments_branch_paid_at_idx',
                     'sales_open_balance_idx',
                     'sales_client_idx');

-- ── Plan B: si un archivo 100a/b/c, pegado SOLO, igual da "cannot run inside
-- a transaction block", el editor está envolviendo todo en una transacción.
-- Entonces correr esto (descomentado, sin `concurrently`) cuando NO se esté
-- vendiendo: mientras se construye cada índice, las ventas y cobros quedan
-- en espera unos segundos y en el POS podrían dar error de tiempo.
--
-- create index if not exists payments_branch_paid_at_idx
--   on public.payments (branch_id, paid_at desc nulls last);
-- create index if not exists sales_open_balance_idx
--   on public.sales (branch_id, due_date) where balance_due > 0;
-- create index if not exists sales_client_idx
--   on public.sales (client_id);
