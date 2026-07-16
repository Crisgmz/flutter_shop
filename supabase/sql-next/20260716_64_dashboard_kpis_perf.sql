-- ============================================================================
-- Migración 64 — Perf: dashboard_kpis_by_branch acotada al mes corriente
-- ============================================================================
-- Bug: la vista (redefinida en la migración 54) armaba `sales_scope` SIN
-- filtro de fecha: para "hoy" y "mes" escaneaba TODO el historial de sales
-- decidiendo con CASE fila a fila, y la RLS (security_invoker) ejecutaba
-- has_branch_access() por cada fila escaneada. Con el historial creciendo,
-- la consulta superaba a ratos el statement_timeout (~8s) del rol API y el
-- panel fallaba con "canceling statement due to statement timeout" (57014).
--
-- Fix: todos los KPI de esta vista solo necesitan el mes corriente (hoy es
-- un subconjunto del mes). Se filtra sales por [inicio_mes, inicio_mes+1) —
-- así el índice existente sales_date_idx (branch_id, sale_date) convierte el
-- escaneo completo en un range scan del mes. Mismas columnas, mismo output.
--
-- Ejecutar en el SQL Editor, DESPUÉS de la migración 54.
-- ============================================================================

begin;

create or replace view public.dashboard_kpis_by_branch
with (security_invoker = true)
as
with month_bounds as (
  select
    date_trunc('month', timezone('utc', now())) as month_start,
    date_trunc('month', timezone('utc', now())) + interval '1 month' as next_month_start
),
-- Solo ventas del mes corriente: es lo único que estos KPI agregan.
sales_scope as (
  select s.*
  from public.sales s
  cross join month_bounds mb
  where s.sale_date >= mb.month_start
    and s.sale_date < mb.next_month_start
    and s.status not in (
      'voided'::public.sale_status, 'pending'::public.sale_status
    )
),
active_products as (
  select p.branch_id, count(*)::bigint as products_active
  from public.products p
  where p.is_active
  group by p.branch_id
),
active_clients as (
  select c.branch_id, count(*)::bigint as clients_active
  from public.clients c
  where c.is_active
  group by c.branch_id
),
ncf_usage as (
  select
    ns.branch_id,
    coalesce(sum(ns.current_number), 0)::bigint as ncf_consumed,
    coalesce(sum(greatest(coalesce(ns.max_number, ns.current_number), ns.current_number) - ns.current_number), 0)::bigint as ncf_available
  from public.ncf_sequences ns
  where ns.is_active
  group by ns.branch_id
)
select
  b.id as branch_id,
  b.code as branch_code,
  b.name as branch_name,
  coalesce(sum(case when s.sale_date::date = timezone('utc', now())::date then s.total_amount else 0 end), 0)::numeric(14,2) as sales_today_amount,
  coalesce(sum(case when s.sale_date::date = timezone('utc', now())::date then 1 else 0 end), 0)::bigint as sales_today_count,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as sales_month_amount,
  coalesce(count(s.id), 0)::bigint as sales_month_count,
  coalesce(ap.products_active, 0)::bigint as products_active,
  coalesce(ac.clients_active, 0)::bigint as clients_active,
  coalesce(sum(case when s.ncf is not null then 1 else 0 end), 0)::bigint as ecf_issued_month,
  coalesce(nu.ncf_consumed, 0)::bigint as ncf_consumed,
  coalesce(nu.ncf_available, 0)::bigint as ncf_available
from public.branches b
left join sales_scope s on s.branch_id = b.id
left join active_products ap on ap.branch_id = b.id
left join active_clients ac on ac.branch_id = b.id
left join ncf_usage nu on nu.branch_id = b.id
where public.has_branch_access(b.id)
group by b.id, b.code, b.name, ap.products_active, ac.clients_active, nu.ncf_consumed, nu.ncf_available;

commit;

notify pgrst, 'reload schema';
