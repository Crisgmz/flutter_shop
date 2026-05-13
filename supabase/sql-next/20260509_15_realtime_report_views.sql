-- 20260509_15_realtime_report_views.sql
-- Shop+ RD - PRD 07 fix crítico: las vistas operativas envolvían
-- materialized views que sólo se refrescan via `refresh_business_reports()`.
-- Eso causaba que ventas/compras del día no aparecieran en /reportes
-- hasta que alguien refrescara las MVs manualmente.
--
-- Esta migración reescribe las vistas para que lean directamente de las
-- tablas transaccionales (real-time). Las MVs en sí se mantienen para uso
-- futuro en analítica de gran escala, pero las vistas operativas no las
-- consumen.
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_14_dgii_reports.sql

begin;

-- =====================================================
-- 1) sales_daily_view → real-time desde `sales`
-- =====================================================

create or replace view public.sales_daily_view
with (security_invoker = true)
as
select
  s.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  coalesce(s.seller_id, s.cashier_id) as seller_user_id,
  s.receipt_type,
  count(*)::bigint as sales_count,
  coalesce(sum(s.subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(s.tax_amount), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(s.service_charge_amount), 0)::numeric(14,2) as service_charge_total,
  coalesce(sum(s.discount_amount), 0)::numeric(14,2) as discount_total,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as net_total
from public.sales s
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(s.branch_id)
group by 1, 2, 3, 4;

-- =====================================================
-- 2) sales_by_item_view → real-time
-- =====================================================

create or replace view public.sales_by_item_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  si.product_id,
  coalesce(p.name, si.description) as product_name,
  coalesce(sum(si.quantity), 0)::numeric(14,3) as units_sold,
  coalesce(sum(si.line_subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(si.line_tax), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(si.line_total), 0)::numeric(14,2) as net_total,
  count(distinct si.sale_id)::bigint as sales_count
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
left join public.products p
  on p.id = si.product_id and p.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(si.branch_id)
group by 1, 2, 3, 4;

-- =====================================================
-- 3) sales_by_category_view → real-time
-- =====================================================

create or replace view public.sales_by_category_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  coalesce(si.category_id, p.category_id) as category_id,
  coalesce(si.category_name_snapshot, pc.name, 'Sin categoría') as category_name,
  coalesce(sum(si.quantity), 0)::numeric(14,3) as units_sold,
  coalesce(sum(si.line_subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(si.line_tax), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(si.line_total), 0)::numeric(14,2) as net_total
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
left join public.products p on p.id = si.product_id and p.branch_id = si.branch_id
left join public.product_categories pc
  on pc.id = coalesce(si.category_id, p.category_id)
  and pc.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(si.branch_id)
group by 1, 2, 3, 4;

-- =====================================================
-- 4) purchases_daily_view → real-time
-- =====================================================

create or replace view public.purchases_daily_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.purchase_date,
  p.supplier_id,
  count(*)::bigint as purchases_count,
  coalesce(sum(p.subtotal), 0)::numeric(14,2) as subtotal_total,
  coalesce(sum(p.discount_amount), 0)::numeric(14,2) as discount_total,
  coalesce(sum(p.tax_amount), 0)::numeric(14,2) as tax_total,
  coalesce(sum(p.total_amount), 0)::numeric(14,2) as grand_total
from public.purchases p
where p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
  and public.has_branch_access(p.branch_id)
group by 1, 2, 3;

-- =====================================================
-- 5) inventory_movements_daily_view → real-time
-- =====================================================

create or replace view public.inventory_movements_daily_view
with (security_invoker = true)
as
select
  im.branch_id,
  date(im.occurred_at at time zone 'America/Santo_Domingo') as movement_day,
  im.movement_type,
  im.product_id,
  coalesce(sum(im.quantity), 0)::numeric(14,3) as total_quantity,
  coalesce(sum(im.quantity * im.unit_cost), 0)::numeric(14,2) as total_cost,
  count(*)::bigint as movements_count
from public.inventory_movements im
where public.has_branch_access(im.branch_id)
group by 1, 2, 3, 4;

-- =====================================================
-- 6) cash_session_summary_view → real-time
-- =====================================================

create or replace view public.cash_session_summary_view
with (security_invoker = true)
as
select
  cs.id as cash_session_id,
  cs.branch_id,
  cs.opened_by,
  cs.closed_by,
  cs.status,
  cs.opened_at,
  cs.closed_at,
  cs.opening_amount,
  cs.expected_amount,
  cs.closing_amount,
  cs.difference_amount,
  count(distinct s.id) filter (where s.status = 'completed'::public.sale_status)::bigint as sales_completed,
  count(distinct s.id) filter (where s.status = 'voided'::public.sale_status)::bigint as sales_voided,
  coalesce(sum(s.total_amount) filter (where s.status = 'completed'::public.sale_status), 0)::numeric(14,2) as sales_total,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'cash'::public.payment_method), 0)::numeric(14,2) as cash_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'card'::public.payment_method), 0)::numeric(14,2) as card_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'transfer'::public.payment_method), 0)::numeric(14,2) as transfer_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'mobile'::public.payment_method), 0)::numeric(14,2) as mobile_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'credit'::public.payment_method), 0)::numeric(14,2) as credit_collected
from public.cash_sessions cs
left join public.sales s
  on s.cash_session_id = cs.id and s.branch_id = cs.branch_id
left join public.payments pay
  on pay.cash_session_id = cs.id and pay.branch_id = cs.branch_id
where public.has_branch_access(cs.branch_id)
group by cs.id, cs.branch_id, cs.opened_by, cs.closed_by, cs.status,
         cs.opened_at, cs.closed_at, cs.opening_amount, cs.expected_amount,
         cs.closing_amount, cs.difference_amount;

commit;
