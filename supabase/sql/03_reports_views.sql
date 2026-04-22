-- Shop+ RD
-- Vistas de reportes para dashboard / panel
-- Ejecutar despues de 01_schema.sql y 02_seed.sql

begin;

-- =========================
-- Helpers
-- =========================
create or replace function public.current_branch_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select ub.branch_id
  from public.users_branches ub
  where ub.user_id = auth.uid()
    and ub.is_active
  order by ub.is_default desc, ub.created_at asc
  limit 1;
$$;

grant execute on function public.current_branch_id() to authenticated;

-- =========================
-- Dashboard KPIs
-- =========================
create or replace view public.dashboard_kpis_by_branch
with (security_invoker = true)
as
with sales_scope as (
  select s.*
  from public.sales s
  where s.status <> 'voided'::public.sale_status
),
month_bounds as (
  select
    date_trunc('month', timezone('utc', now())) as month_start,
    date_trunc('month', timezone('utc', now())) + interval '1 month' as next_month_start
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
  coalesce(sum(case when s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then s.total_amount else 0 end), 0)::numeric(14,2) as sales_month_amount,
  coalesce(sum(case when s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then 1 else 0 end), 0)::bigint as sales_month_count,
  coalesce(ap.products_active, 0)::bigint as products_active,
  coalesce(ac.clients_active, 0)::bigint as clients_active,
  coalesce(sum(case when s.ncf is not null and s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then 1 else 0 end), 0)::bigint as ecf_issued_month,
  coalesce(nu.ncf_consumed, 0)::bigint as ncf_consumed,
  coalesce(nu.ncf_available, 0)::bigint as ncf_available
from public.branches b
cross join month_bounds mb
left join sales_scope s on s.branch_id = b.id
left join active_products ap on ap.branch_id = b.id
left join active_clients ac on ac.branch_id = b.id
left join ncf_usage nu on nu.branch_id = b.id
where public.has_branch_access(b.id)
group by b.id, b.code, b.name, ap.products_active, ac.clients_active, nu.ncf_consumed, nu.ncf_available;

-- =========================
-- Ventas por mes (ultimos 12 meses)
-- =========================
create or replace view public.sales_monthly_summary
with (security_invoker = true)
as
with months as (
  select generate_series(
    date_trunc('month', timezone('utc', now())) - interval '11 months',
    date_trunc('month', timezone('utc', now())),
    interval '1 month'
  ) as month_start
),
branches_scope as (
  select b.id, b.code, b.name
  from public.branches b
  where public.has_branch_access(b.id)
)
select
  bs.id as branch_id,
  bs.code as branch_code,
  bs.name as branch_name,
  m.month_start::date as period_start,
  to_char(m.month_start, 'YYYY-MM') as period_key,
  to_char(m.month_start, 'Mon YYYY') as period_label,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_amount,
  coalesce(count(s.id), 0)::bigint as transaction_count
from branches_scope bs
cross join months m
left join public.sales s
  on s.branch_id = bs.id
 and s.status <> 'voided'::public.sale_status
 and s.sale_date >= m.month_start
 and s.sale_date < m.month_start + interval '1 month'
group by bs.id, bs.code, bs.name, m.month_start
order by bs.name, m.month_start;

-- =========================
-- Ventas por semana (ultimas 12 semanas)
-- =========================
create or replace view public.sales_weekly_summary
with (security_invoker = true)
as
with weeks as (
  select generate_series(
    date_trunc('week', timezone('utc', now())) - interval '11 weeks',
    date_trunc('week', timezone('utc', now())),
    interval '1 week'
  ) as week_start
),
branches_scope as (
  select b.id, b.code, b.name
  from public.branches b
  where public.has_branch_access(b.id)
)
select
  bs.id as branch_id,
  bs.code as branch_code,
  bs.name as branch_name,
  w.week_start::date as period_start,
  to_char(w.week_start, 'IYYY-"W"IW') as period_key,
  to_char(w.week_start, 'DD Mon') || ' - ' || to_char(w.week_start + interval '6 days', 'DD Mon') as period_label,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_amount,
  coalesce(count(s.id), 0)::bigint as transaction_count
from branches_scope bs
cross join weeks w
left join public.sales s
  on s.branch_id = bs.id
 and s.status <> 'voided'::public.sale_status
 and s.sale_date >= w.week_start
 and s.sale_date < w.week_start + interval '1 week'
group by bs.id, bs.code, bs.name, w.week_start
order by bs.name, w.week_start;

-- =========================
-- Ultimas ventas
-- =========================
create or replace view public.latest_sales_view
with (security_invoker = true)
as
select
  s.id,
  s.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  s.sale_number,
  s.sale_date,
  s.receipt_type,
  s.ncf,
  s.dgii_status,
  s.status,
  s.total_amount,
  s.paid_amount,
  s.balance_due,
  coalesce(c.full_name, 'Cliente General') as client_name,
  p.full_name as cashier_name
from public.sales s
join public.branches b on b.id = s.branch_id
left join public.clients c on c.id = s.client_id and c.branch_id = s.branch_id
left join public.profiles p on p.id = s.cashier_id
where public.has_branch_access(s.branch_id)
  and s.status <> 'voided'::public.sale_status
order by s.sale_date desc;

-- =========================
-- Cuentas por cobrar (resumen)
-- =========================
create or replace view public.accounts_receivable_summary
with (security_invoker = true)
as
select
  s.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  count(*) filter (where s.balance_due > 0)::bigint as invoices_open,
  coalesce(sum(s.balance_due) filter (where s.balance_due > 0), 0)::numeric(14,2) as total_balance_due,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_invoiced,
  coalesce(sum(p.amount), 0)::numeric(14,2) as total_collected
from public.sales s
join public.branches b on b.id = s.branch_id
left join public.payments p on p.sale_id = s.id and p.branch_id = s.branch_id
where public.has_branch_access(s.branch_id)
  and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status, 'pending'::public.sale_status)
group by s.branch_id, b.code, b.name;

-- =========================
-- Inventario bajo stock
-- =========================
create or replace view public.inventory_low_stock_view
with (security_invoker = true)
as
select
  p.id,
  p.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  p.sku,
  p.barcode,
  p.name,
  p.stock,
  p.min_stock,
  p.price,
  p.is_active,
  (p.stock <= p.min_stock) as is_low_stock
from public.products p
join public.branches b on b.id = p.branch_id
where public.has_branch_access(p.branch_id)
  and p.is_active
  and p.stock <= p.min_stock
order by p.stock asc, p.name asc;

-- =========================
-- NCF consumidos/disponibles
-- =========================
create or replace view public.ncf_usage_summary
with (security_invoker = true)
as
select
  ns.id,
  ns.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  ns.receipt_type,
  ns.prefix,
  ns.current_number,
  ns.max_number,
  greatest(coalesce(ns.max_number, ns.current_number), ns.current_number) - ns.current_number as available,
  ns.expires_on,
  ns.is_active
from public.ncf_sequences ns
join public.branches b on b.id = ns.branch_id
where public.has_branch_access(ns.branch_id)
order by b.name, ns.receipt_type, ns.prefix;

-- =========================
-- Grants
-- =========================
grant select on public.dashboard_kpis_by_branch to authenticated;
grant select on public.sales_monthly_summary to authenticated;
grant select on public.sales_weekly_summary to authenticated;
grant select on public.latest_sales_view to authenticated;
grant select on public.accounts_receivable_summary to authenticated;
grant select on public.inventory_low_stock_view to authenticated;
grant select on public.ncf_usage_summary to authenticated;

commit;
