-- 20260509_12_closeout_returns_fix.sql
-- Shop+ RD - PRD Dashboard 06 (cierre F4 fix):
--   el bloque "Devoluciones" del RPC `dashboard_v2_closeout` leía
--   `sales WHERE status='voided'` como proxy porque la tabla `returns`
--   aún no existía. Tras 20260509_11_returns.sql, la tabla está
--   poblada por el flujo Venta/Devolución del POS — apuntamos el RPC a
--   esa tabla y marcamos `returns_table_available: true`.
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_11_returns.sql

begin;

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

  -- 4.1 VENTAS (idéntico a v1)
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

  -- 4.2 CRÉDITO (idéntico a v1)
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

  -- 4.3 DEVOLUCIONES — ahora lee de `returns` (FIX vs proxy original).
  with day_returns as (
    select r.*
      from public.returns r
     where r.branch_id = v_branch_id
       and r.return_date >= v_start
       and r.return_date <  v_end
  ),
  day_return_items as (
    select ri.product_id, ri.description, ri.quantity, ri.line_total
      from public.return_items ri
      join day_returns r on r.id = ri.return_id and r.branch_id = ri.branch_id
  )
  select jsonb_build_object(
    'returns_total', coalesce(sum(r.total_amount), 0)::numeric(14,2),
    'breakdown_by_item', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'description', description,
                                   'quantity', quantity,
                                   'amount', line_total
                                 )), '[]'::jsonb)
                          from day_return_items),
    'transactions_count', count(*),
    'items_returned', coalesce((select sum(quantity) from day_return_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(r.tax_amount), 0)::numeric(14,2),
    'returns_table_available', true
  ) into v_returns_block
  from day_returns r;

  -- 4.4 COMPRAS (idéntico a v1)
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

  -- 4.5 GASTOS (idéntico a v1)
  select jsonb_build_object(
    'expenses_total', coalesce(sum(amount), 0)::numeric(14,2),
    'transactions_count', count(*)
  ) into v_expenses_block
  from public.expenses
  where branch_id = v_branch_id
    and expense_date = v_date;

  -- 4.6 CASH MONITORING (idéntico a v1)
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
