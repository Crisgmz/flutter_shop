-- 20260509_10_dashboard_v2.sql
-- Shop+ RD - PRD Dashboard 06 (sub-fase 2): backend para nuevo Panel.
--
-- Ejecutar después de:
--   supabase/sql/01_schema.sql
--   supabase/sql/03_reports_views.sql
--   supabase/sql/04_branch_context.sql
--   supabase/sql-next/20260421_structural_backoffice_foundation.sql
--   supabase/sql-next/20260509_09_reports_schema.sql
--
-- Aporta 3 RPCs SECURITY DEFINER, todas branch-scoped:
--   - dashboard_v2_kpis(branch_id)         → 4 contadores (F1)
--   - dashboard_v2_sales_chart(branch_id, range) → serie temporal (F3)
--   - dashboard_v2_closeout(branch_id, date)     → 6 bloques (F4)
--
-- Fuentes:
--   sales, sale_items, purchases, purchase_items, expenses, payments,
--   products, clients, cash_sessions, fiscal_documents (PRD 6).
--
-- Notas:
--   - "Total Kits" hoy = 0: no existe modelo de kits en este esquema; el
--     PRD §12.1 lo deja como TBD. Cuando aparezca, esta RPC devuelve count.
--   - "Devoluciones" hoy se aproxima con sales.status = 'voided' porque la
--     tabla `returns` (PRD F5) aún no existe; cuando llegue, ajustar.

begin;

-- =====================================================
-- 1) RPC: KPIs F1
-- =====================================================

create or replace function public.dashboard_v2_kpis(
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_total_ventas bigint;
  v_total_inventario bigint;
  v_total_clientes bigint;
  v_total_kits bigint;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  if v_branch_id is null then
    return jsonb_build_object(
      'partial', true,
      'total_ventas', 0,
      'total_inventario', 0,
      'total_clientes', 0,
      'total_kits', 0
    );
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  select count(*)
    into v_total_ventas
    from public.sales s
   where s.branch_id = v_branch_id
     and s.status <> 'voided'::public.sale_status;

  select count(*)
    into v_total_inventario
    from public.products p
   where p.branch_id = v_branch_id
     and p.is_active = true
     and p.stock > 0;

  select count(*)
    into v_total_clientes
    from public.clients c
   where c.branch_id = v_branch_id
     and c.is_active = true
     and lower(coalesce(c.full_name, '')) <> 'consumidor final';

  -- Kits: TBD (PRD §12.1). No hay modelo de kits aún.
  v_total_kits := 0;

  return jsonb_build_object(
    'branch_id', v_branch_id,
    'total_ventas', coalesce(v_total_ventas, 0),
    'total_inventario', coalesce(v_total_inventario, 0),
    'total_clientes', coalesce(v_total_clientes, 0),
    'total_kits', v_total_kits,
    'partial', false
  );
end;
$$;

grant execute on function public.dashboard_v2_kpis(uuid) to authenticated;

-- =====================================================
-- 2) RPC: serie temporal F3 (mes / semana)
-- =====================================================

create or replace function public.dashboard_v2_sales_chart(
  p_branch_id uuid default null,
  p_range text default 'month'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_start date;
  v_end date;
  v_today date;
  v_result jsonb;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  if v_branch_id is null then
    return '[]'::jsonb;
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  v_today := (timezone('America/Santo_Domingo', now()))::date;

  if lower(coalesce(p_range, 'month')) = 'week' then
    v_start := v_today - interval '6 days';
    v_end := v_today;
  else
    v_start := date_trunc('month', v_today)::date;
    v_end := v_today;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'date', d::date,
           'transactions', coalesce(s.cnt, 0),
           'total', coalesce(s.total, 0)
         ) order by d), '[]'::jsonb)
    into v_result
    from generate_series(v_start, v_end, interval '1 day') as d
    left join (
      select date(sale_date at time zone 'America/Santo_Domingo') as day,
             count(*) as cnt,
             coalesce(sum(total_amount), 0)::numeric(14,2) as total
        from public.sales
       where branch_id = v_branch_id
         and status = 'completed'::public.sale_status
         and sale_date >= (v_start::timestamp at time zone 'America/Santo_Domingo')
         and sale_date <  ((v_end + 1)::timestamp at time zone 'America/Santo_Domingo')
       group by 1
    ) s on s.day = d::date;

  return v_result;
end;
$$;

grant execute on function public.dashboard_v2_sales_chart(uuid, text) to authenticated;

-- =====================================================
-- 3) RPC: cierre del día F4 (6 bloques)
-- =====================================================

create or replace function public.dashboard_v2_closeout(
  p_branch_id uuid default null,
  p_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_date date;
  v_start timestamptz;
  v_end timestamptz;

  v_sales_block jsonb;
  v_credit_block jsonb;
  v_returns_block jsonb;
  v_purchases_block jsonb;
  v_expenses_block jsonb;
  v_cash_block jsonb;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_date := coalesce(p_date, (timezone('America/Santo_Domingo', now()))::date);

  if v_branch_id is null then
    return jsonb_build_object('partial', true);
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  v_start := (v_date::timestamp at time zone 'America/Santo_Domingo');
  v_end   := ((v_date + 1)::timestamp at time zone 'America/Santo_Domingo');

  -- 4.1 VENTAS
  with day_sales as (
    select s.*
      from public.sales s
     where s.branch_id = v_branch_id
       and s.status = 'completed'::public.sale_status
       and s.sale_date >= v_start
       and s.sale_date <  v_end
  ),
  day_items as (
    select si.*
      from public.sale_items si
      join day_sales s on s.id = si.sale_id and s.branch_id = si.branch_id
  ),
  cash_payments as (
    select coalesce(sum(p.amount), 0)::numeric(14,2) as cash_total
      from public.payments p
      join day_sales s on s.id = p.sale_id and s.branch_id = p.branch_id
     where p.payment_method = 'cash'::public.payment_method
  ),
  by_category as (
    select coalesce(pc.name, 'Sin categoría') as category_name,
           coalesce(sum(di.line_total), 0)::numeric(14,2) as total
      from day_items di
      left join public.products p
        on p.id = di.product_id
       and p.branch_id = di.branch_id
      left join public.product_categories pc
        on pc.id = coalesce(di.category_id, p.category_id)
       and pc.branch_id = di.branch_id
     group by 1
  ),
  inv_totals as (
    select coalesce(sum(p.stock), 0)::numeric(14,3) as qty_on_hand,
           coalesce(sum(p.stock * p.cost), 0)::numeric(14,2) as inv_value
      from public.products p
     where p.branch_id = v_branch_id
       and p.is_active = true
  )
  select jsonb_build_object(
    'sales_total_no_tax', coalesce(sum(s.taxable_amount + s.exempt_amount), 0)::numeric(14,2),
    'sales_total_with_tax', coalesce(sum(s.total_amount), 0)::numeric(14,2),
    'profit', coalesce(sum(s.total_amount), 0)::numeric(14,2)
              - coalesce(sum((select sum(si.quantity * coalesce(p.cost, 0))
                              from public.sale_items si
                              left join public.products p
                                on p.id = si.product_id and p.branch_id = si.branch_id
                              where si.sale_id = s.id and si.branch_id = s.branch_id)), 0)::numeric(14,2),
    'inventory_qty_on_hand', (select qty_on_hand from inv_totals),
    'inventory_value', (select inv_value from inv_totals),
    'breakdown_by_category', (select coalesce(jsonb_agg(jsonb_build_object(
                                       'name', category_name,
                                       'amount', total
                                     ) order by total desc), '[]'::jsonb)
                              from by_category),
    'transactions_count', count(*),
    'avg_ticket', case when count(*) > 0
                       then coalesce(sum(s.total_amount), 0) / count(*)
                       else 0 end,
    'items_sold', coalesce((select sum(quantity) from day_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(s.tax_amount), 0)::numeric(14,2),
    'no_tax_amount', coalesce(sum(s.taxable_amount + s.exempt_amount), 0)::numeric(14,2),
    'cash_amount', coalesce((select cash_total from cash_payments), 0)
  ) into v_sales_block
  from day_sales s;

  -- 4.2 CRÉDITO
  with day_payments as (
    select p.*
      from public.payments p
     where p.branch_id = v_branch_id
       and p.paid_at >= v_start
       and p.paid_at <  v_end
  )
  select jsonb_build_object(
    'debits',  coalesce((select sum(amount) from day_payments where payment_method = 'credit'::public.payment_method), 0)::numeric(14,2),
    'credits', coalesce((select sum(amount) from day_payments where payment_method <> 'credit'::public.payment_method
                                                              and client_id is not null), 0)::numeric(14,2),
    'store_account_balance_total', coalesce((select sum(c.balance_due) from public.clients c
                                              where c.branch_id = v_branch_id and c.is_active = true), 0)::numeric(14,2)
  ) into v_credit_block;

  -- 4.3 DEVOLUCIONES (proxy: sales voided del día)
  -- Cuando exista la tabla `returns` (PRD F5) ajustar este bloque.
  with voided_sales as (
    select s.*
      from public.sales s
     where s.branch_id = v_branch_id
       and s.status = 'voided'::public.sale_status
       and s.updated_at >= v_start
       and s.updated_at <  v_end
  ),
  voided_items as (
    select si.product_id, si.description, si.quantity, si.line_total
      from public.sale_items si
      join voided_sales s on s.id = si.sale_id and s.branch_id = si.branch_id
  )
  select jsonb_build_object(
    'returns_total', coalesce(sum(s.total_amount), 0)::numeric(14,2),
    'breakdown_by_item', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'description', description,
                                   'quantity', quantity,
                                   'amount', line_total
                                 )), '[]'::jsonb)
                          from voided_items),
    'transactions_count', count(*),
    'items_returned', coalesce((select sum(quantity) from voided_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(s.tax_amount), 0)::numeric(14,2),
    'returns_table_available', false
  ) into v_returns_block
  from voided_sales s;

  -- 4.4 COMPRAS (recepciones)
  with day_purchases as (
    select p.*
      from public.purchases p
     where p.branch_id = v_branch_id
       and p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
       and p.purchase_date = v_date
  ),
  day_purchase_items as (
    select pi.*
      from public.purchase_items pi
      join day_purchases p on p.id = pi.purchase_id and p.branch_id = pi.branch_id
  )
  select jsonb_build_object(
    'receivings_total_no_tax', coalesce(sum(p.subtotal), 0)::numeric(14,2),
    'receivings_total_with_tax', coalesce(sum(p.total_amount), 0)::numeric(14,2),
    'transactions_count', count(*),
    'avg_ticket', case when count(*) > 0
                       then coalesce(sum(p.total_amount), 0) / count(*)
                       else 0 end,
    'items_received', coalesce((select sum(quantity) from day_purchase_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(p.tax_amount), 0)::numeric(14,2),
    'no_tax_amount', coalesce(sum(p.subtotal), 0)::numeric(14,2)
  ) into v_purchases_block
  from day_purchases p;

  -- 4.5 GASTOS
  select jsonb_build_object(
    'expenses_total', coalesce(sum(amount), 0)::numeric(14,2),
    'transactions_count', count(*)
  ) into v_expenses_block
  from public.expenses
  where branch_id = v_branch_id
    and expense_date = v_date;

  -- 4.6 CASH MONITORING (sesión de caja del día)
  select jsonb_build_object(
    'enabled', cs.id is not null,
    'session_id', cs.id,
    'opened_at', cs.opened_at,
    'closed_at', cs.closed_at,
    'opening_amount', coalesce(cs.opening_amount, 0)::numeric(14,2),
    'expected_amount', coalesce(cs.expected_amount, 0)::numeric(14,2),
    'closing_amount', cs.closing_amount,
    'difference_amount', cs.difference_amount,
    'status', cs.status
  ) into v_cash_block
  from public.cash_sessions cs
  where cs.branch_id = v_branch_id
    and cs.opened_at >= v_start - interval '1 day'
    and cs.opened_at <  v_end
  order by cs.opened_at desc
  limit 1;

  if v_cash_block is null then
    v_cash_block := jsonb_build_object('enabled', false);
  end if;

  return jsonb_build_object(
    'branch_id', v_branch_id,
    'date', v_date,
    'sales', v_sales_block,
    'credit', v_credit_block,
    'returns', v_returns_block,
    'purchases', v_purchases_block,
    'expenses', v_expenses_block,
    'cash_monitoring', v_cash_block,
    'partial', false
  );
end;
$$;

grant execute on function public.dashboard_v2_closeout(uuid, date) to authenticated;

commit;
