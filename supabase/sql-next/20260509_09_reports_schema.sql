-- 20260509_09_reports_schema.sql
-- Shop+ RD - PRD 07: Módulo de Reportes Unificado (esqueleto compatible)
--
-- Ejecutar después de:
--   supabase/sql/01_schema.sql
--   supabase/sql/03_reports_views.sql
--   supabase/sql/04_branch_context.sql
--   supabase/sql-next/20260421_structural_backoffice_foundation.sql
--   supabase/sql-next/20260509_08_app_settings.sql
--
-- Diseño:
--   - Aditivo: ninguna tabla existente se modifica destructivamente.
--   - inventory_movements: movimientos manuales NO cubiertos por
--     triggers actuales (waste/breakage/expired/kitchen_return/ajustes/traslados).
--   - fiscal_z_closures: cierres Z inmutables (UPDATE bloqueado por trigger).
--   - fiscal_dgii_reports: archivos 606/607/IT-1 generados, con conteo
--     de inconsistencias.
--   - custom_reports: definición persistida del query builder visual.
--   - report_generation_log: bitácora ligera de uso (complementa report_exports).
--   - 6 materialized views base; refresh por función RPC + concurrente.

begin;

create extension if not exists pgcrypto;

-- =====================================================
-- 1) Enums auxiliares
-- =====================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'inventory_movement_type') then
    create type public.inventory_movement_type as enum (
      'waste',
      'breakage',
      'expired',
      'kitchen_return',
      'adjustment_in',
      'adjustment_out',
      'transfer_in',
      'transfer_out',
      'opening',
      'recount'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'fiscal_dgii_report_type') then
    create type public.fiscal_dgii_report_type as enum ('606', '607', 'IT1');
  end if;

  if not exists (select 1 from pg_type where typname = 'report_generation_mode') then
    create type public.report_generation_mode as enum ('graphic', 'summary', 'export');
  end if;
end $$;

-- =====================================================
-- 2) inventory_movements: mermas, ajustes, traslados
-- =====================================================

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null,
  movement_type public.inventory_movement_type not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  reason text,
  reference_type text,
  reference_id uuid,
  occurred_at timestamptz not null default timezone('utc', now()),
  recorded_by uuid references auth.users(id),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint inventory_movements_product_branch_fk
    foreign key (product_id, branch_id)
    references public.products(id, branch_id)
    on delete restrict
);

comment on table public.inventory_movements is
  'Movimientos manuales de inventario (mermas, ajustes, traslados). NO duplica los triggers automáticos de purchase_items/sale_items.';

create index if not exists inventory_movements_branch_date_idx
  on public.inventory_movements (branch_id, occurred_at desc);

create index if not exists inventory_movements_product_idx
  on public.inventory_movements (branch_id, product_id, occurred_at desc);

create index if not exists inventory_movements_type_idx
  on public.inventory_movements (branch_id, movement_type, occurred_at desc);

-- Trigger que actualiza products.stock según el tipo
create or replace function public.apply_inventory_movement_stock()
returns trigger
language plpgsql
as $$
declare
  v_signed_qty numeric(14,3);
begin
  if tg_op = 'INSERT' then
    v_signed_qty := case new.movement_type
      when 'adjustment_in'  then  new.quantity
      when 'transfer_in'    then  new.quantity
      when 'opening'        then  new.quantity
      when 'recount'        then  new.quantity
      when 'waste'          then -new.quantity
      when 'breakage'       then -new.quantity
      when 'expired'        then -new.quantity
      when 'kitchen_return' then -new.quantity
      when 'adjustment_out' then -new.quantity
      when 'transfer_out'   then -new.quantity
    end;

    update public.products
      set stock = stock + v_signed_qty
    where id = new.product_id
      and branch_id = new.branch_id;

    return new;
  end if;

  if tg_op = 'DELETE' then
    -- Revertir efecto al borrar
    v_signed_qty := case old.movement_type
      when 'adjustment_in'  then -old.quantity
      when 'transfer_in'    then -old.quantity
      when 'opening'        then -old.quantity
      when 'recount'        then -old.quantity
      when 'waste'          then  old.quantity
      when 'breakage'       then  old.quantity
      when 'expired'        then  old.quantity
      when 'kitchen_return' then  old.quantity
      when 'adjustment_out' then  old.quantity
      when 'transfer_out'   then  old.quantity
    end;

    update public.products
      set stock = stock + v_signed_qty
    where id = old.product_id
      and branch_id = old.branch_id;

    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_inventory_movements_stock on public.inventory_movements;
create trigger trg_inventory_movements_stock
after insert or delete on public.inventory_movements
for each row execute function public.apply_inventory_movement_stock();

drop trigger if exists trg_inventory_movements_updated_at on public.inventory_movements;
create trigger trg_inventory_movements_updated_at
before update on public.inventory_movements
for each row execute function public.set_updated_at();

drop trigger if exists trg_inventory_movements_audit on public.inventory_movements;
create trigger trg_inventory_movements_audit
before insert or update on public.inventory_movements
for each row execute function public.set_audit_fields();

-- =====================================================
-- 3) fiscal_z_closures: cierres Z fiscales inmutables
-- =====================================================

create table if not exists public.fiscal_z_closures (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  cash_session_id uuid not null,
  closure_number integer not null,
  emitted_at timestamptz not null default timezone('utc', now()),
  emitted_by uuid references auth.users(id),
  payload jsonb not null,
  pdf_url text,
  is_complementary boolean not null default false,
  parent_closure_id uuid references public.fiscal_z_closures(id),
  created_at timestamptz not null default timezone('utc', now()),
  unique (branch_id, closure_number),
  constraint fiscal_z_closures_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete restrict
);

comment on table public.fiscal_z_closures is
  'Cierres Z fiscales sellados; inmutables post-emisión. Para corregir se emite un complementario.';

create index if not exists fiscal_z_closures_session_idx
  on public.fiscal_z_closures (cash_session_id);

create index if not exists fiscal_z_closures_branch_emitted_idx
  on public.fiscal_z_closures (branch_id, emitted_at desc);

-- Bloquear UPDATE: cierres Z son inmutables.
create or replace function public.block_fiscal_z_closure_update()
returns trigger
language plpgsql
as $$
begin
  raise exception 'fiscal_z_closures es inmutable. Para corregir, emita un cierre complementario.'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists trg_fiscal_z_closures_block_update on public.fiscal_z_closures;
create trigger trg_fiscal_z_closures_block_update
before update on public.fiscal_z_closures
for each row execute function public.block_fiscal_z_closure_update();

-- =====================================================
-- 4) fiscal_dgii_reports: archivos 606/607/IT-1 generados
-- =====================================================

create table if not exists public.fiscal_dgii_reports (
  id uuid primary key default gen_random_uuid(),
  report_type public.fiscal_dgii_report_type not null,
  period_year integer not null check (period_year between 2020 and 2100),
  period_month integer not null check (period_month between 1 and 12),
  generated_at timestamptz not null default timezone('utc', now()),
  generated_by uuid references auth.users(id),
  records_count integer not null default 0,
  inconsistencies_count integer not null default 0,
  inconsistencies jsonb not null default '[]'::jsonb,
  txt_file_url text,
  pdf_file_url text,
  storage_path text,
  status text not null default 'generated',
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (report_type, period_year, period_month)
);

comment on table public.fiscal_dgii_reports is
  'Reportes mensuales DGII (606/607/IT-1) ya generados, con inconsistencias detectadas.';

create index if not exists fiscal_dgii_reports_period_idx
  on public.fiscal_dgii_reports (report_type, period_year desc, period_month desc);

-- =====================================================
-- 5) custom_reports: definiciones del query builder
-- =====================================================

create table if not exists public.custom_reports (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  config jsonb not null,
  is_shared boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid references auth.users(id),
  unique (created_by, name)
);

comment on table public.custom_reports is
  'Reportes personalizados creados por el usuario vía query builder. config: definición JSON validada server-side contra whitelist de tablas/columnas.';

create index if not exists custom_reports_owner_idx
  on public.custom_reports (created_by, is_active);

create index if not exists custom_reports_shared_idx
  on public.custom_reports (is_shared)
  where is_shared = true and is_active = true;

drop trigger if exists trg_custom_reports_updated_at on public.custom_reports;
create trigger trg_custom_reports_updated_at
before update on public.custom_reports
for each row execute function public.set_updated_at();

-- =====================================================
-- 6) report_generation_log: bitácora ligera de uso
-- =====================================================

create table if not exists public.report_generation_log (
  id bigserial primary key,
  branch_id uuid references public.branches(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  report_category text not null,
  report_mode public.report_generation_mode not null,
  filters jsonb not null default '{}'::jsonb,
  duration_ms integer,
  rows_returned integer,
  generated_at timestamptz not null default timezone('utc', now())
);

comment on table public.report_generation_log is
  'Bitácora de generación de reportes (telemetría). Complementa report_exports que es la cola operativa.';

create index if not exists report_generation_log_branch_date_idx
  on public.report_generation_log (branch_id, generated_at desc);

create index if not exists report_generation_log_category_idx
  on public.report_generation_log (report_category, generated_at desc);

-- =====================================================
-- 7) RLS para tablas nuevas
-- =====================================================

alter table public.inventory_movements enable row level security;
alter table public.fiscal_z_closures enable row level security;
alter table public.fiscal_dgii_reports enable row level security;
alter table public.custom_reports enable row level security;
alter table public.report_generation_log enable row level security;

-- inventory_movements: lee con acceso a sucursal; escribe con can_manage_branch_data
drop policy if exists inventory_movements_select on public.inventory_movements;
create policy inventory_movements_select
on public.inventory_movements
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists inventory_movements_insert on public.inventory_movements;
create policy inventory_movements_insert
on public.inventory_movements
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists inventory_movements_update on public.inventory_movements;
create policy inventory_movements_update
on public.inventory_movements
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists inventory_movements_delete on public.inventory_movements;
create policy inventory_movements_delete
on public.inventory_movements
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- fiscal_z_closures: lee con acceso a sucursal; INSERT solo vía función seal_fiscal_z_closure
drop policy if exists fiscal_z_closures_select on public.fiscal_z_closures;
create policy fiscal_z_closures_select
on public.fiscal_z_closures
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists fiscal_z_closures_insert on public.fiscal_z_closures;
create policy fiscal_z_closures_insert
on public.fiscal_z_closures
for insert
to authenticated
with check (
  public.has_branch_access(branch_id)
  and (public.is_admin() or public.current_user_role() in ('supervisor'::public.app_role, 'cashier'::public.app_role, 'accountant'::public.app_role))
);

-- DELETE prohibido: cierres Z son inmutables incluso para admin.
drop policy if exists fiscal_z_closures_delete on public.fiscal_z_closures;
create policy fiscal_z_closures_delete
on public.fiscal_z_closures
for delete
to authenticated
using (false);

-- fiscal_dgii_reports: solo admin / accountant ven y generan
drop policy if exists fiscal_dgii_reports_select on public.fiscal_dgii_reports;
create policy fiscal_dgii_reports_select
on public.fiscal_dgii_reports
for select
to authenticated
using (
  public.is_admin()
  or public.current_user_role() = 'accountant'::public.app_role
);

drop policy if exists fiscal_dgii_reports_insert on public.fiscal_dgii_reports;
create policy fiscal_dgii_reports_insert
on public.fiscal_dgii_reports
for insert
to authenticated
with check (
  public.is_admin()
  or public.current_user_role() = 'accountant'::public.app_role
);

drop policy if exists fiscal_dgii_reports_update on public.fiscal_dgii_reports;
create policy fiscal_dgii_reports_update
on public.fiscal_dgii_reports
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists fiscal_dgii_reports_delete on public.fiscal_dgii_reports;
create policy fiscal_dgii_reports_delete
on public.fiscal_dgii_reports
for delete
to authenticated
using (public.is_admin());

-- custom_reports: dueño ve sus propios + los compartidos; solo dueño edita
drop policy if exists custom_reports_select on public.custom_reports;
create policy custom_reports_select
on public.custom_reports
for select
to authenticated
using (
  created_by = auth.uid()
  or is_shared = true
  or public.is_admin()
);

drop policy if exists custom_reports_insert on public.custom_reports;
create policy custom_reports_insert
on public.custom_reports
for insert
to authenticated
with check (created_by = auth.uid());

drop policy if exists custom_reports_update on public.custom_reports;
create policy custom_reports_update
on public.custom_reports
for update
to authenticated
using (created_by = auth.uid() or public.is_admin())
with check (created_by = auth.uid() or public.is_admin());

drop policy if exists custom_reports_delete on public.custom_reports;
create policy custom_reports_delete
on public.custom_reports
for delete
to authenticated
using (created_by = auth.uid() or public.is_admin());

-- report_generation_log: cada usuario inserta el suyo; admin lee todos, otros solo los suyos
drop policy if exists report_generation_log_select on public.report_generation_log;
create policy report_generation_log_select
on public.report_generation_log
for select
to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists report_generation_log_insert on public.report_generation_log;
create policy report_generation_log_insert
on public.report_generation_log
for insert
to authenticated
with check (user_id is null or user_id = auth.uid());

-- =====================================================
-- 8) Materialized views base
-- =====================================================

-- 8.1) Ventas diarias por sucursal / cajero / receipt_type
drop materialized view if exists public.mv_sales_daily;
create materialized view public.mv_sales_daily as
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
group by 1, 2, 3, 4;

create unique index if not exists mv_sales_daily_pk
  on public.mv_sales_daily (branch_id, sale_day, seller_user_id, receipt_type);

create index if not exists mv_sales_daily_branch_day_idx
  on public.mv_sales_daily (branch_id, sale_day desc);

-- 8.2) Ventas por artículo
drop materialized view if exists public.mv_sales_by_item;
create materialized view public.mv_sales_by_item as
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
left join public.products p on p.id = si.product_id and p.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
group by 1, 2, 3, 4;

create unique index if not exists mv_sales_by_item_pk
  on public.mv_sales_by_item (branch_id, sale_day, product_id);

create index if not exists mv_sales_by_item_product_idx
  on public.mv_sales_by_item (branch_id, product_id, sale_day desc);

-- 8.3) Ventas por categoría
drop materialized view if exists public.mv_sales_by_category;
create materialized view public.mv_sales_by_category as
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
group by 1, 2, 3, 4;

create unique index if not exists mv_sales_by_category_pk
  on public.mv_sales_by_category (branch_id, sale_day, coalesce(category_id, '00000000-0000-0000-0000-000000000000'::uuid));

create index if not exists mv_sales_by_category_branch_day_idx
  on public.mv_sales_by_category (branch_id, sale_day desc);

-- 8.4) Compras diarias
drop materialized view if exists public.mv_purchases_daily;
create materialized view public.mv_purchases_daily as
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
group by 1, 2, 3;

create unique index if not exists mv_purchases_daily_pk
  on public.mv_purchases_daily (branch_id, purchase_date, supplier_id);

create index if not exists mv_purchases_daily_branch_date_idx
  on public.mv_purchases_daily (branch_id, purchase_date desc);

-- 8.5) Movimientos de inventario diarios
drop materialized view if exists public.mv_inventory_movements_daily;
create materialized view public.mv_inventory_movements_daily as
select
  im.branch_id,
  date(im.occurred_at at time zone 'America/Santo_Domingo') as movement_day,
  im.movement_type,
  im.product_id,
  coalesce(sum(im.quantity), 0)::numeric(14,3) as total_quantity,
  coalesce(sum(im.quantity * im.unit_cost), 0)::numeric(14,2) as total_cost,
  count(*)::bigint as movements_count
from public.inventory_movements im
group by 1, 2, 3, 4;

create unique index if not exists mv_inventory_movements_daily_pk
  on public.mv_inventory_movements_daily (branch_id, movement_day, movement_type, product_id);

-- 8.6) Resumen por sesión de caja
drop materialized view if exists public.mv_cash_session_summary;
create materialized view public.mv_cash_session_summary as
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
  on s.cash_session_id = cs.id
  and s.branch_id = cs.branch_id
left join public.payments pay
  on pay.cash_session_id = cs.id
  and pay.branch_id = cs.branch_id
group by cs.id, cs.branch_id, cs.opened_by, cs.closed_by, cs.status,
         cs.opened_at, cs.closed_at, cs.opening_amount, cs.expected_amount,
         cs.closing_amount, cs.difference_amount;

create unique index if not exists mv_cash_session_summary_pk
  on public.mv_cash_session_summary (cash_session_id);

create index if not exists mv_cash_session_summary_branch_idx
  on public.mv_cash_session_summary (branch_id, opened_at desc);

-- =====================================================
-- 9) Vistas wrapper con RLS por sucursal sobre las MVs
-- =====================================================
-- Las materialized views no soportan RLS directamente; envolvemos
-- en vistas security_invoker que aplican has_branch_access().

create or replace view public.sales_daily_view
with (security_invoker = true)
as
select * from public.mv_sales_daily
where public.has_branch_access(branch_id);

create or replace view public.sales_by_item_view
with (security_invoker = true)
as
select * from public.mv_sales_by_item
where public.has_branch_access(branch_id);

create or replace view public.sales_by_category_view
with (security_invoker = true)
as
select * from public.mv_sales_by_category
where public.has_branch_access(branch_id);

create or replace view public.purchases_daily_view
with (security_invoker = true)
as
select * from public.mv_purchases_daily
where public.has_branch_access(branch_id);

create or replace view public.inventory_movements_daily_view
with (security_invoker = true)
as
select * from public.mv_inventory_movements_daily
where public.has_branch_access(branch_id);

create or replace view public.cash_session_summary_view
with (security_invoker = true)
as
select * from public.mv_cash_session_summary
where public.has_branch_access(branch_id);

-- =====================================================
-- 10) Función RPC: refrescar reportes
-- =====================================================

create or replace function public.refresh_business_reports()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view public.mv_sales_daily;
  refresh materialized view public.mv_sales_by_item;
  refresh materialized view public.mv_sales_by_category;
  refresh materialized view public.mv_purchases_daily;
  refresh materialized view public.mv_inventory_movements_daily;
  refresh materialized view public.mv_cash_session_summary;
end;
$$;

grant execute on function public.refresh_business_reports() to authenticated;

-- Versión concurrente para uso programado (requiere índice unique en cada MV).
create or replace function public.refresh_business_reports_concurrently()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.mv_sales_daily;
  refresh materialized view concurrently public.mv_sales_by_item;
  refresh materialized view concurrently public.mv_sales_by_category;
  refresh materialized view concurrently public.mv_purchases_daily;
  refresh materialized view concurrently public.mv_inventory_movements_daily;
  refresh materialized view concurrently public.mv_cash_session_summary;
end;
$$;

grant execute on function public.refresh_business_reports_concurrently() to authenticated;

-- =====================================================
-- 11) Función: build_z_closure_payload (snapshot interno)
-- =====================================================

create or replace function public.build_z_closure_payload(
  p_branch_id uuid,
  p_cash_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session record;
  v_sales jsonb;
  v_payments jsonb;
  v_taxes jsonb;
  v_voids jsonb;
begin
  select cs.* into v_session
  from public.cash_sessions cs
  where cs.id = p_cash_session_id
    and cs.branch_id = p_branch_id;

  if not found then
    raise exception 'Cash session not found for branch';
  end if;

  -- Ventas por receipt_type
  select coalesce(jsonb_agg(jsonb_build_object(
    'receipt_type', t.receipt_type,
    'count', t.cnt,
    'subtotal', t.subtotal,
    'tax', t.tax,
    'service_charge', t.service_charge,
    'total', t.total
  )), '[]'::jsonb)
  into v_sales
  from (
    select
      s.receipt_type,
      count(*) as cnt,
      coalesce(sum(s.subtotal), 0)::numeric(14,2) as subtotal,
      coalesce(sum(s.tax_amount), 0)::numeric(14,2) as tax,
      coalesce(sum(s.service_charge_amount), 0)::numeric(14,2) as service_charge,
      coalesce(sum(s.total_amount), 0)::numeric(14,2) as total
    from public.sales s
    where s.cash_session_id = p_cash_session_id
      and s.branch_id = p_branch_id
      and s.status = 'completed'::public.sale_status
    group by s.receipt_type
  ) t;

  -- Pagos por método
  select coalesce(jsonb_object_agg(payment_method::text, total), '{}'::jsonb)
  into v_payments
  from (
    select
      p.payment_method,
      coalesce(sum(p.amount), 0)::numeric(14,2) as total
    from public.payments p
    where p.cash_session_id = p_cash_session_id
      and p.branch_id = p_branch_id
    group by p.payment_method
  ) t;

  -- Desglose ITBIS
  select jsonb_build_object(
    'taxable_amount', coalesce(sum(s.taxable_amount), 0)::numeric(14,2),
    'exempt_amount',  coalesce(sum(s.exempt_amount), 0)::numeric(14,2),
    'tax_amount',     coalesce(sum(s.tax_amount), 0)::numeric(14,2),
    'service_charge', coalesce(sum(s.service_charge_amount), 0)::numeric(14,2)
  )
  into v_taxes
  from public.sales s
  where s.cash_session_id = p_cash_session_id
    and s.branch_id = p_branch_id
    and s.status = 'completed'::public.sale_status;

  -- Anulaciones
  select jsonb_build_object(
    'count', count(*)::bigint,
    'amount', coalesce(sum(s.total_amount), 0)::numeric(14,2)
  )
  into v_voids
  from public.sales s
  where s.cash_session_id = p_cash_session_id
    and s.branch_id = p_branch_id
    and s.status = 'voided'::public.sale_status;

  return jsonb_build_object(
    'session', jsonb_build_object(
      'id', v_session.id,
      'opened_at', v_session.opened_at,
      'closed_at', v_session.closed_at,
      'opened_by', v_session.opened_by,
      'closed_by', v_session.closed_by,
      'opening_amount', v_session.opening_amount,
      'expected_amount', v_session.expected_amount,
      'closing_amount', v_session.closing_amount,
      'difference_amount', v_session.difference_amount
    ),
    'sales_by_receipt_type', v_sales,
    'payments_by_method', v_payments,
    'tax_breakdown', v_taxes,
    'voids', v_voids,
    'generated_at', timezone('utc', now())
  );
end;
$$;

grant execute on function public.build_z_closure_payload(uuid, uuid) to authenticated;

-- =====================================================
-- 12) Función: seal_fiscal_z_closure
-- =====================================================

create or replace function public.seal_fiscal_z_closure(
  p_branch_id uuid,
  p_cash_session_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_closure_id uuid;
  v_payload jsonb;
  v_next_number integer;
begin
  -- Verificar acceso a la sucursal
  if not public.has_branch_access(p_branch_id) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  -- La sesión debe existir y estar cerrada
  if not exists (
    select 1 from public.cash_sessions
    where id = p_cash_session_id
      and branch_id = p_branch_id
      and closed_at is not null
  ) then
    raise exception 'La sesión de caja no existe o aún no está cerrada';
  end if;

  -- No permitir doble cierre Z primario para la misma sesión
  if exists (
    select 1 from public.fiscal_z_closures
    where cash_session_id = p_cash_session_id
      and is_complementary = false
  ) then
    raise exception 'Ya existe un cierre Z para esta sesión. Para corregir, emita un complementario.';
  end if;

  -- Calcular siguiente número correlativo por sucursal
  select coalesce(max(closure_number), 0) + 1
    into v_next_number
    from public.fiscal_z_closures
   where branch_id = p_branch_id;

  -- Construir snapshot
  v_payload := public.build_z_closure_payload(p_branch_id, p_cash_session_id);

  insert into public.fiscal_z_closures (
    branch_id, cash_session_id, closure_number, emitted_by, payload
  )
  values (
    p_branch_id, p_cash_session_id, v_next_number, auth.uid(), v_payload
  )
  returning id into v_closure_id;

  return v_closure_id;
end;
$$;

grant execute on function public.seal_fiscal_z_closure(uuid, uuid) to authenticated;

-- =====================================================
-- 13) Permisos canónicos adicionales (para PRD 7)
-- =====================================================

insert into public.permissions (code, name, module, action_type, description, sort_order)
values
  ('reports.fiscal', 'Generar Reportes Fiscales DGII', 'reports', 'fiscal', 'Generar 606, 607, IT-1, Cierre Z fiscal', 72),
  ('reports.custom', 'Crear Reportes Personalizados', 'reports', 'custom', 'Crear reportes vía query builder', 73),
  ('inventory.waste', 'Registrar Mermas', 'inventory', 'waste', 'Registrar movimientos de merma/quiebre/vencido', 45),
  ('inventory.transfer', 'Trasladar Inventario', 'inventory', 'transfer', 'Registrar traslados entre sucursales', 46)
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

-- Asignaciones por rol
insert into public.role_permissions (role_key, permission_id, allowed)
select role_key, p.id, true
from public.permissions p
join (
  values
    ('admin', 'reports.fiscal'),
    ('admin', 'reports.custom'),
    ('admin', 'inventory.waste'),
    ('admin', 'inventory.transfer'),
    ('accountant', 'reports.fiscal'),
    ('accountant', 'reports.custom'),
    ('supervisor', 'reports.custom'),
    ('supervisor', 'inventory.waste'),
    ('supervisor', 'inventory.transfer')
) as grant_map(role_key, permission_code)
  on p.code = grant_map.permission_code
on conflict (role_key, permission_id) do nothing;

-- =====================================================
-- 14) Refresh inicial de las MVs
-- =====================================================

select public.refresh_business_reports();

-- =====================================================
-- 15) Grants finales
-- =====================================================

grant select, insert, update, delete on public.inventory_movements to authenticated;
grant select, insert on public.fiscal_z_closures to authenticated;
grant select, insert, update, delete on public.fiscal_dgii_reports to authenticated;
grant select, insert, update, delete on public.custom_reports to authenticated;
grant select, insert on public.report_generation_log to authenticated;

grant select on public.mv_sales_daily to authenticated;
grant select on public.mv_sales_by_item to authenticated;
grant select on public.mv_sales_by_category to authenticated;
grant select on public.mv_purchases_daily to authenticated;
grant select on public.mv_inventory_movements_daily to authenticated;
grant select on public.mv_cash_session_summary to authenticated;

grant select on public.sales_daily_view to authenticated;
grant select on public.sales_by_item_view to authenticated;
grant select on public.sales_by_category_view to authenticated;
grant select on public.purchases_daily_view to authenticated;
grant select on public.inventory_movements_daily_view to authenticated;
grant select on public.cash_session_summary_view to authenticated;

commit;
