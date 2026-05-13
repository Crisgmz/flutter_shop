-- 20260509_13_reports_round2_views.sql
-- Shop+ RD - PRD 07 Round 2: views + RPCs para los 12 reportes operativos
-- de empleados, productos, financieros y clientes.
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_09_reports_schema.sql  (MVs base ya creadas)
--   supabase/sql-next/20260509_11_returns.sql         (tabla returns)
--   supabase/sql-next/20260509_12_closeout_returns_fix.sql
--
-- Diseño:
--   - Todas las vistas usan `security_invoker = true` para que RLS por
--     sucursal se aplique según el usuario que consulta.
--   - Vista o RPC según el caso. Vistas para agregaciones simples,
--     RPCs para casos con parámetros (rango de fecha, settings).
--   - Cobertura:
--       Empleados, Comisión, Inventario, Precios, Mermas (ya cubierto en m9),
--       P&L, Crédito, Gastos, Compras, Proveedores, Clientes, Descuentos.

begin;

-- =====================================================
-- 1) Empleados — productividad por usuario / mesero
-- =====================================================

create or replace view public.report_employees_view
with (security_invoker = true)
as
select
  s.branch_id,
  coalesce(s.seller_id, s.cashier_id) as employee_id,
  coalesce(p.full_name, 'Sin asignar')::text as employee_name,
  count(*)::bigint as sales_count,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as sales_total,
  case when count(*) > 0
       then (coalesce(sum(s.total_amount), 0) / count(*))::numeric(14,2)
       else 0 end as avg_ticket,
  coalesce(sum((
    select sum(si.quantity)
      from public.sale_items si
     where si.sale_id = s.id and si.branch_id = s.branch_id
  )), 0)::numeric(14,3) as items_sold,
  max(s.sale_date) as last_sale_at,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day
from public.sales s
left join public.profiles p
  on p.id = coalesce(s.seller_id, s.cashier_id)
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(s.branch_id)
group by s.branch_id, coalesce(s.seller_id, s.cashier_id), p.full_name,
         date(s.sale_date at time zone 'America/Santo_Domingo');

grant select on public.report_employees_view to authenticated;

-- =====================================================
-- 2) Comisión — RPC que respeta app_settings.emp_commission_*
-- =====================================================

create or replace function public.report_commission(
  p_from date default null,
  p_to date default null,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_from date;
  v_to date;
  v_rate numeric(5,2);
  v_method text;
  v_rows jsonb;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_from := coalesce(p_from, date_trunc('month', current_date)::date);
  v_to := coalesce(p_to, current_date);

  if v_branch_id is null then
    return jsonb_build_object('partial', true, 'rows', '[]'::jsonb);
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  -- Lee tasa y método desde app_settings (singleton id=1).
  select coalesce(emp_commission_rate, 0)::numeric(5,2),
         coalesce(emp_commission_method, 'sale_price')::text
    into v_rate, v_method
    from public.app_settings where id = 1;

  v_rate := coalesce(v_rate, 0);
  v_method := coalesce(v_method, 'sale_price');

  with day_sales as (
    select s.*
      from public.sales s
     where s.branch_id = v_branch_id
       and s.status = 'completed'::public.sale_status
       and s.sale_date >= (v_from::timestamp at time zone 'America/Santo_Domingo')
       and s.sale_date <  ((v_to + 1)::timestamp at time zone 'America/Santo_Domingo')
  ),
  base as (
    select
      coalesce(s.seller_id, s.cashier_id) as employee_id,
      coalesce(p.full_name, 'Sin asignar') as employee_name,
      count(*) as sales_count,
      sum(s.total_amount) as sales_total,
      sum(s.subtotal) as base_price,
      sum(
        s.subtotal - coalesce((
          select sum(si.quantity * coalesce(prod.cost, 0))
            from public.sale_items si
            left join public.products prod
              on prod.id = si.product_id and prod.branch_id = si.branch_id
           where si.sale_id = s.id and si.branch_id = s.branch_id
        ), 0)
      ) as profit_base
    from day_sales s
    left join public.profiles p
      on p.id = coalesce(s.seller_id, s.cashier_id)
    group by 1, 2
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'employee_id', employee_id,
    'employee_name', employee_name,
    'sales_count', sales_count,
    'sales_total', sales_total,
    'base_amount', case v_method
                     when 'sale_price' then base_price
                     when 'profit_margin' then profit_base
                     when 'total_sales' then sales_total
                     else base_price end,
    'commission_rate', v_rate,
    'commission_amount', round(
      (case v_method
         when 'sale_price' then base_price
         when 'profit_margin' then profit_base
         when 'total_sales' then sales_total
         else base_price end) * v_rate / 100.0, 2)
  ) order by sales_total desc), '[]'::jsonb)
  into v_rows
  from base;

  return jsonb_build_object(
    'from', v_from,
    'to', v_to,
    'rate', v_rate,
    'method', v_method,
    'rows', v_rows
  );
end;
$$;

grant execute on function public.report_commission(date, date, uuid) to authenticated;

-- =====================================================
-- 3) Inventario — snapshot actual con valor y low-stock flag
-- =====================================================

create or replace view public.report_inventory_status_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.id as product_id,
  p.name,
  p.sku,
  p.barcode,
  p.category_id,
  pc.name as category_name,
  p.stock,
  p.min_stock,
  p.cost,
  p.price,
  (p.stock * p.cost)::numeric(14,2) as inventory_value,
  case when p.stock <= p.min_stock and p.min_stock > 0 then true else false end
    as is_low_stock,
  case when p.stock <= 0 then true else false end as is_out_of_stock,
  p.is_active,
  p.updated_at
from public.products p
left join public.product_categories pc
  on pc.id = p.category_id and pc.branch_id = p.branch_id
where p.is_active = true
  and public.has_branch_access(p.branch_id);

grant select on public.report_inventory_status_view to authenticated;

-- =====================================================
-- 4) Precios — precio actual + margen (no hay historial todavía)
-- =====================================================

create or replace view public.report_current_prices_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.id as product_id,
  p.name,
  p.sku,
  p.barcode,
  pc.name as category_name,
  p.cost,
  p.price,
  case when p.cost > 0
       then round(((p.price - p.cost) / p.cost) * 100, 2)
       else null end as margin_pct,
  p.price_tier_1,
  p.price_tier_2,
  p.price_tier_3,
  p.updated_at
from public.products p
left join public.product_categories pc
  on pc.id = p.category_id and pc.branch_id = p.branch_id
where p.is_active = true
  and public.has_branch_access(p.branch_id);

grant select on public.report_current_prices_view to authenticated;

-- =====================================================
-- 5) Pérdidas y Ganancias — RPC con rango
-- =====================================================

create or replace function public.report_pl(
  p_from date default null,
  p_to date default null,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_from date;
  v_to date;
  v_start timestamptz;
  v_end timestamptz;
  v_revenue numeric(14,2);
  v_cogs numeric(14,2);
  v_returns numeric(14,2);
  v_expenses numeric(14,2);
  v_tax_received numeric(14,2);
  v_tax_paid numeric(14,2);
  v_purchases numeric(14,2);
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_from := coalesce(p_from, date_trunc('month', current_date)::date);
  v_to := coalesce(p_to, current_date);

  if v_branch_id is null then
    return jsonb_build_object('partial', true);
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  v_start := (v_from::timestamp at time zone 'America/Santo_Domingo');
  v_end := ((v_to + 1)::timestamp at time zone 'America/Santo_Domingo');

  -- Revenue: ventas completadas en el rango
  select coalesce(sum(total_amount), 0),
         coalesce(sum(tax_amount), 0)
    into v_revenue, v_tax_received
    from public.sales
   where branch_id = v_branch_id
     and status = 'completed'::public.sale_status
     and sale_date >= v_start
     and sale_date <  v_end;

  -- COGS: sum(quantity * cost) en sale_items de ventas en el rango
  select coalesce(sum(si.quantity * coalesce(p.cost, 0)), 0)
    into v_cogs
    from public.sale_items si
    join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
    left join public.products p
      on p.id = si.product_id and p.branch_id = si.branch_id
   where s.branch_id = v_branch_id
     and s.status = 'completed'::public.sale_status
     and s.sale_date >= v_start
     and s.sale_date <  v_end;

  -- Devoluciones
  select coalesce(sum(total_amount), 0)
    into v_returns
    from public.returns
   where branch_id = v_branch_id
     and return_date >= v_start
     and return_date <  v_end;

  -- Gastos
  select coalesce(sum(amount), 0)
    into v_expenses
    from public.expenses
   where branch_id = v_branch_id
     and expense_date >= v_from
     and expense_date <= v_to;

  -- Compras + ITBIS pagado
  select coalesce(sum(total_amount), 0),
         coalesce(sum(tax_amount), 0)
    into v_purchases, v_tax_paid
    from public.purchases
   where branch_id = v_branch_id
     and status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
     and purchase_date >= v_from
     and purchase_date <= v_to;

  return jsonb_build_object(
    'from', v_from,
    'to', v_to,
    'revenue', v_revenue,
    'cogs', v_cogs,
    'returns', v_returns,
    'gross_profit', v_revenue - v_cogs - v_returns,
    'expenses', v_expenses,
    'net_profit', (v_revenue - v_cogs - v_returns) - v_expenses,
    'tax_received', v_tax_received,
    'tax_paid', v_tax_paid,
    'tax_balance', v_tax_received - v_tax_paid,
    'purchases_total', v_purchases
  );
end;
$$;

grant execute on function public.report_pl(date, date, uuid) to authenticated;

-- =====================================================
-- 6) Crédito — antigüedad de saldos por cliente
-- =====================================================

create or replace view public.report_credit_aging_view
with (security_invoker = true)
as
with oldest_unpaid as (
  select
    s.branch_id,
    s.client_id,
    min(s.sale_date) as oldest_at
  from public.sales s
  where s.balance_due > 0
    and s.status in ('credit'::public.sale_status, 'completed'::public.sale_status)
    and s.client_id is not null
  group by s.branch_id, s.client_id
)
select
  c.branch_id,
  c.id as client_id,
  c.full_name as client_name,
  c.balance_due,
  c.credit_limit,
  ou.oldest_at,
  case
    when ou.oldest_at is null then null
    else greatest(0, (current_date - ou.oldest_at::date))::integer
  end as days_overdue,
  case
    when ou.oldest_at is null then '—'
    when (current_date - ou.oldest_at::date) <= 30 then '0-30'
    when (current_date - ou.oldest_at::date) <= 60 then '31-60'
    when (current_date - ou.oldest_at::date) <= 90 then '61-90'
    else '+90'
  end as aging_bucket
from public.clients c
left join oldest_unpaid ou
  on ou.client_id = c.id and ou.branch_id = c.branch_id
where c.balance_due > 0
  and c.is_active = true
  and public.has_branch_access(c.branch_id);

grant select on public.report_credit_aging_view to authenticated;

-- =====================================================
-- 7) Gastos — agrupados por categoría (vista para reporte)
-- =====================================================

create or replace view public.report_expenses_view
with (security_invoker = true)
as
select
  e.branch_id,
  e.expense_date,
  coalesce(e.category, 'Sin categoría') as category,
  count(*)::bigint as count,
  sum(e.amount)::numeric(14,2) as total
from public.expenses e
where public.has_branch_access(e.branch_id)
group by e.branch_id, e.expense_date, e.category;

grant select on public.report_expenses_view to authenticated;

-- =====================================================
-- 8) Compras — agregadas por día y proveedor
-- =====================================================

create or replace view public.report_purchases_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.purchase_date,
  p.supplier_id,
  s.legal_name as supplier_name,
  count(*)::bigint as purchases_count,
  sum(p.subtotal)::numeric(14,2) as subtotal_total,
  sum(p.tax_amount)::numeric(14,2) as tax_total,
  sum(p.total_amount)::numeric(14,2) as grand_total
from public.purchases p
join public.suppliers s on s.id = p.supplier_id and s.branch_id = p.branch_id
where p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
  and public.has_branch_access(p.branch_id)
group by p.branch_id, p.purchase_date, p.supplier_id, s.legal_name;

grant select on public.report_purchases_view to authenticated;

-- =====================================================
-- 9) Proveedores — top proveedores y deuda actual
-- =====================================================

create or replace view public.report_suppliers_view
with (security_invoker = true)
as
with totals as (
  select
    p.branch_id,
    p.supplier_id,
    count(*)::bigint as purchases_count,
    sum(p.total_amount)::numeric(14,2) as purchases_total,
    max(p.purchase_date) as last_purchase_at,
    sum(
      case when coalesce(p.payment_status, 'pending') <> 'paid'
           then p.total_amount else 0 end
    )::numeric(14,2) as outstanding_amount
  from public.purchases p
  where p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
  group by p.branch_id, p.supplier_id
)
select
  s.branch_id,
  s.id as supplier_id,
  s.legal_name as supplier_name,
  s.trade_name,
  s.rnc,
  coalesce(t.purchases_count, 0) as purchases_count,
  coalesce(t.purchases_total, 0)::numeric(14,2) as purchases_total,
  coalesce(t.outstanding_amount, 0)::numeric(14,2) as outstanding_amount,
  t.last_purchase_at
from public.suppliers s
left join totals t on t.supplier_id = s.id and t.branch_id = s.branch_id
where s.is_active = true
  and public.has_branch_access(s.branch_id);

grant select on public.report_suppliers_view to authenticated;

-- =====================================================
-- 10) Clientes — top clientes, frecuencia, ticket promedio
-- =====================================================

create or replace view public.report_clients_view
with (security_invoker = true)
as
with sale_agg as (
  select
    s.branch_id,
    s.client_id,
    count(*) filter (where s.status = 'completed'::public.sale_status)::bigint
      as sales_count,
    coalesce(sum(s.total_amount) filter (where s.status = 'completed'::public.sale_status), 0)::numeric(14,2)
      as sales_total,
    max(s.sale_date) filter (where s.status = 'completed'::public.sale_status)
      as last_sale_at
  from public.sales s
  where s.client_id is not null
  group by s.branch_id, s.client_id
)
select
  c.branch_id,
  c.id as client_id,
  c.full_name as client_name,
  c.phone,
  c.email,
  c.credit_limit,
  c.balance_due,
  coalesce(sa.sales_count, 0) as sales_count,
  coalesce(sa.sales_total, 0)::numeric(14,2) as sales_total,
  case when coalesce(sa.sales_count, 0) > 0
       then (coalesce(sa.sales_total, 0) / sa.sales_count)::numeric(14,2)
       else 0 end as avg_ticket,
  sa.last_sale_at
from public.clients c
left join sale_agg sa
  on sa.client_id = c.id and sa.branch_id = c.branch_id
where c.is_active = true
  and public.has_branch_access(c.branch_id);

grant select on public.report_clients_view to authenticated;

-- =====================================================
-- 11) Descuentos — ventas con descuento aplicado
-- =====================================================

create or replace view public.report_discounts_view
with (security_invoker = true)
as
select
  s.branch_id,
  s.id as sale_id,
  s.sale_number,
  s.sale_date,
  s.client_id,
  c.full_name as client_name,
  s.cashier_id,
  p.full_name as cashier_name,
  s.discount_amount,
  s.subtotal,
  s.total_amount,
  case when s.subtotal > 0
       then round((s.discount_amount / s.subtotal) * 100, 2)
       else 0 end as discount_pct
from public.sales s
left join public.clients c
  on c.id = s.client_id and c.branch_id = s.branch_id
left join public.profiles p on p.id = s.cashier_id
where s.discount_amount > 0
  and s.status = 'completed'::public.sale_status
  and public.has_branch_access(s.branch_id);

grant select on public.report_discounts_view to authenticated;

commit;
