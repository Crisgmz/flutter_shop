-- ============================================================================
-- Migración 71 — Vista unificada de historial: ventas + devoluciones
-- ============================================================================
-- Hoy el historial de ventas solo lee `sales`, así que una devolución es
-- invisible: el total del día no baja y la ganancia sigue inflada.
--
-- `public.sales_history_entries` une ambas tablas en un solo stream con
-- columnas idénticas. Las filas de devolución salen con los montos NEGADOS
-- (subtotal, tax_amount, total_amount, paid_amount), de modo que sumar la
-- columna ya da el neto: Total y Ganancia aparecen en negativo sin ninguna
-- lógica extra en Dart.
--
-- Seguridad: `security_invoker = true` hace que la vista se evalúe con los
-- permisos de QUIEN consulta, no del dueño de la vista. Por lo tanto hereda
-- las policies RLS de `sales` y de `returns` — ambas filtran por
-- public.has_branch_access(branch_id). La vista NO abre datos de otra
-- sucursal ni de otra empresa; no hace falta repetir el filtro aquí.
--
-- Ejecutar después de:
--   supabase/sql-next/20260814_69_returns_cash_and_imeis.sql
--   (requiere returns.cash_session_id y returns.refund_method)
--
-- Idempotente.
-- ============================================================================

begin;

drop view if exists public.sales_history_entries;

create or replace view public.sales_history_entries
with (security_invoker = true)
as
select
  'sale'::text                        as entry_kind,
  s.id                                as id,
  s.branch_id                         as branch_id,
  s.sale_number::text                 as doc_number,
  s.sale_date                         as doc_date,
  s.status::text                      as status,
  s.receipt_type::text                as receipt_type,
  s.ncf::text                         as ncf,
  s.subtotal::numeric(14,2)           as subtotal,
  s.tax_amount::numeric(14,2)         as tax_amount,
  s.total_amount::numeric(14,2)       as total_amount,
  s.paid_amount::numeric(14,2)        as paid_amount,
  s.balance_due::numeric(14,2)        as balance_due,
  s.due_date::date                    as due_date,
  s.client_id                         as client_id,
  s.cashier_id                        as cashier_id,
  s.cash_session_id                   as cash_session_id,
  s.notes::text                       as notes,
  null::text                          as refund_method
from public.sales s

union all

select
  'return'::text                      as entry_kind,
  r.id                                as id,
  r.branch_id                         as branch_id,
  r.return_number::text               as doc_number,
  r.return_date                       as doc_date,
  'returned'::text                    as status,
  null::text                          as receipt_type,
  null::text                          as ncf,
  (-r.subtotal)::numeric(14,2)        as subtotal,
  (-r.tax_amount)::numeric(14,2)      as tax_amount,
  (-r.total_amount)::numeric(14,2)    as total_amount,
  (-r.total_amount)::numeric(14,2)    as paid_amount,
  0::numeric(14,2)                    as balance_due,
  null::date                          as due_date,
  r.client_id                         as client_id,
  r.cashier_id                        as cashier_id,
  r.cash_session_id                   as cash_session_id,
  r.notes::text                       as notes,
  r.refund_method::text               as refund_method
from public.returns r;

comment on view public.sales_history_entries is
  'Historial unificado ventas + devoluciones. Las devoluciones traen los montos negados. RLS heredada vía security_invoker.';

grant select on public.sales_history_entries to authenticated;

commit;

notify pgrst, 'reload schema';
