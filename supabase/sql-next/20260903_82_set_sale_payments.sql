-- RPC: set_sale_payments
--
-- Reemplaza el juego COMPLETO de pagos de una venta y recalcula su estado.
-- Es el "editor de pagos avanzado" que la migración 31
-- (update_sale_payment_method) dejaba pendiente.
--
-- Por qué existe:
--   `update_sale_payment_method` solo cambiaba `payments.payment_method`. Al
--   editar una venta cobrada en efectivo y pasarla a crédito, la venta quedaba
--   con status = 'completed', paid_amount = total y balance_due = 0 — o sea,
--   seguía diciendo "Pagada" y NO aparecía en Cuentas por cobrar (que filtra
--   balance_due > 0). El dinero no estaba en caja y la deuda no se cobraba.
--
-- Qué hace:
--   1. Borra los pagos actuales de la venta.
--   2. Inserta una fila por cada línea {method, amount} recibida.
--      Las líneas con method = 'credit' NO generan pago: representan la parte
--      que queda debiendo (permite "5,000 en efectivo y el resto a crédito").
--   3. Recalcula paid_amount / balance_due / status / due_date de la venta.
--   4. Recalcula clients.balance_due del cliente sumando sus ventas con saldo.
--
-- Seguridad: SECURITY DEFINER + has_branch_access + solo admin/supervisor
-- (mismo criterio que la 31).

begin;

create or replace function public.set_sale_payments(
  p_sale_id uuid,
  p_payments jsonb,
  p_credit_due_days integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale            record;
  v_now             timestamptz := timezone('utc', now());
  v_user_id         uuid := auth.uid();
  v_pay             record;
  v_paid_amount     numeric(14,2) := 0;
  v_balance_due     numeric(14,2) := 0;
  v_status          public.sale_status;
  v_due_date        date;
  v_due_days        integer;
  v_default_days    integer;
  v_inserted        integer := 0;
  v_cash_session_id uuid;
begin
  if p_sale_id is null then
    raise exception 'p_sale_id es requerido.'
      using errcode = '22023';
  end if;

  if not public.is_admin()
     and public.current_user_role() <> 'supervisor'::public.app_role then
    raise exception 'Solo admin o supervisor pueden cambiar la forma de cobro.'
      using errcode = '42501';
  end if;

  select id, branch_id, status, total_amount, client_id, sale_number,
         sale_date, due_date, cash_session_id, notes
    into v_sale
    from public.sales
   where id = p_sale_id;

  if v_sale.id is null then
    raise exception 'Venta no encontrada.'
      using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_sale.branch_id) then
    raise exception 'Sin acceso a esta venta.'
      using errcode = '42501';
  end if;

  if v_sale.status = 'voided'::public.sale_status then
    raise exception 'No se puede modificar una venta anulada.'
      using errcode = '22023';
  end if;

  -- ── 1) Normalizar las líneas recibidas ───────────────────────────────────
  -- Solo cuentan las líneas con monto > 0. 'credit' no es un pago: es la parte
  -- que queda debiendo, así que se descarta acá y aparece sola en el balance.
  create temp table tmp_sale_payments (
    method public.payment_method,
    amount numeric(14,2)
  ) on commit drop;

  if p_payments is not null
     and jsonb_typeof(p_payments) = 'array'
     and jsonb_array_length(p_payments) > 0 then
    for v_pay in
      select
        coalesce(nullif(trim(e->>'method'), ''), 'cash') as method,
        round(coalesce((e->>'amount')::numeric, 0), 2)   as amount
      from jsonb_array_elements(p_payments) as e
    loop
      if v_pay.amount <= 0 or v_pay.method = 'credit' then
        continue;
      end if;
      begin
        insert into tmp_sale_payments (method, amount)
        values (v_pay.method::public.payment_method, v_pay.amount);
      exception
        when invalid_text_representation then
          raise exception 'Método de pago no soportado: %', v_pay.method
            using errcode = '22023';
      end;
    end loop;
  end if;

  select coalesce(sum(amount), 0)::numeric(14,2)
    into v_paid_amount
    from tmp_sale_payments;

  if v_paid_amount > round(v_sale.total_amount, 2) then
    raise exception 'Los pagos (%) no pueden exceder el total de la venta (%).',
      v_paid_amount, round(v_sale.total_amount, 2)
      using errcode = '22023';
  end if;

  v_balance_due := round(v_sale.total_amount - v_paid_amount, 2);
  if v_balance_due < 0 then
    v_balance_due := 0;
  end if;

  v_status := case
    when v_balance_due > 0 then 'credit'::public.sale_status
    else 'completed'::public.sale_status
  end;

  -- Una venta a crédito sin cliente no se le puede cobrar a nadie: el saldo
  -- quedaría flotando en Cuentas por cobrar bajo "Cliente General".
  if v_balance_due > 0 and v_sale.client_id is null then
    raise exception 'Una venta con saldo pendiente necesita un cliente asignado.'
      using errcode = '22023';
  end if;

  -- ── 2) Fecha de vencimiento ──────────────────────────────────────────────
  if v_balance_due > 0 then
    if p_credit_due_days is not null or v_sale.due_date is null then
      select credit_default_days into v_default_days
        from public.app_settings
       where id = 1;

      v_default_days := coalesce(v_default_days, 30);
      v_due_days := coalesce(p_credit_due_days, v_default_days);

      if v_due_days <= 0 or v_due_days > 365 then
        v_due_days := v_default_days;
      end if;

      v_due_date := (v_sale.sale_date at time zone 'UTC')::date
                    + (v_due_days || ' days')::interval;
    else
      v_due_date := v_sale.due_date;
    end if;
  else
    -- Ya no debe nada: la fecha de vencimiento deja de tener sentido.
    v_due_date := null;
  end if;

  -- ── 3) Reemplazar los pagos ──────────────────────────────────────────────
  -- Los pagos nuevos van a la misma sesión de caja de la venta, para que el
  -- cuadre de ESA caja refleje el cambio (y no la del que corrige, que puede
  -- estar en otra caja o en otro día).
  v_cash_session_id := v_sale.cash_session_id;

  delete from public.payments
   where sale_id = p_sale_id
     and branch_id = v_sale.branch_id;

  insert into public.payments (
    branch_id, sale_id, client_id, cash_session_id, payment_method,
    amount, paid_at, reference, notes, created_by, updated_by
  )
  select
    v_sale.branch_id, p_sale_id, v_sale.client_id, v_cash_session_id,
    method, amount, v_now, v_sale.sale_number, v_sale.notes,
    v_user_id, v_user_id
  from tmp_sale_payments;

  get diagnostics v_inserted = row_count;

  -- ── 4) Actualizar la venta ───────────────────────────────────────────────
  update public.sales
     set paid_amount = v_paid_amount,
         balance_due = v_balance_due,
         status      = v_status,
         due_date    = v_due_date,
         updated_at  = v_now,
         updated_by  = v_user_id
   where id = p_sale_id
     and branch_id = v_sale.branch_id;

  -- ── 5) Recalcular el saldo del cliente ───────────────────────────────────
  -- Se recalcula desde cero (suma de sus ventas con saldo) en vez de aplicar
  -- deltas: es la única forma de que quede consistente sin importar cuántas
  -- veces se corrija la misma venta.
  if v_sale.client_id is not null then
    update public.clients c
       set balance_due = coalesce((
             select round(sum(s.balance_due)::numeric, 2)
               from public.sales s
              where s.branch_id = v_sale.branch_id
                and s.client_id = v_sale.client_id
                and s.balance_due > 0
                and s.status <> 'voided'::public.sale_status
           ), 0)
     where c.id = v_sale.client_id
       and c.branch_id = v_sale.branch_id;
  end if;

  return jsonb_build_object(
    'sale_id',      p_sale_id,
    'status',       v_status,
    'paid_amount',  v_paid_amount,
    'balance_due',  v_balance_due,
    'due_date',     v_due_date,
    'payments',     v_inserted
  );
end;
$$;

grant execute on function public.set_sale_payments(uuid, jsonb, integer)
  to authenticated;

notify pgrst, 'reload schema';

commit;
