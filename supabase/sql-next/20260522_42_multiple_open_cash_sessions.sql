-- Permitir que un usuario tenga varias sesiones de caja abiertas al mismo
-- tiempo (una por cada caja registrada en la sucursal). Cambiar entre
-- ellas ya no requiere cerrar la actual primero.
--
-- Cambios:
--   1. Se elimina el UNIQUE INDEX que solo permitía una sesión abierta
--      por (branch_id, opened_by). En su lugar se crea uno por
--      (branch_id, opened_by, cash_register_id) para que no se pueda
--      abrir dos veces la MISMA caja.
--
--   2. open_cash_session_for_register ya no rechaza si el usuario tiene
--      otra sesión abierta. Solo rechaza si ya tiene una sesión abierta
--      en LA MISMA caja (no tiene sentido duplicar).
--
--   3. checkout_sale_transactional acepta un nuevo parámetro opcional
--      p_cash_session_id. Si viene, lo usa (validando que sea del
--      usuario actual y esté abierta). Si no viene, fallback al
--      comportamiento legacy (sesión más reciente del usuario).
--
-- Idempotente.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Constraint: una sesión abierta por (branch, user, caja)
-- ─────────────────────────────────────────────────────────────────────────

drop index if exists public.cash_sessions_open_by_user_unique;

create unique index if not exists cash_sessions_open_by_register_unique
  on public.cash_sessions (branch_id, opened_by, cash_register_id)
  where status = 'open';

-- ─────────────────────────────────────────────────────────────────────────
-- 2) open_cash_session_for_register: ya no rechaza por otra sesión abierta
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.open_cash_session_for_register(
  p_cash_register_id uuid,
  p_opening_amount numeric,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid;
  v_session_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida.' using errcode = '28000';
  end if;
  if p_cash_register_id is null then
    raise exception 'p_cash_register_id es requerido.' using errcode = '22023';
  end if;
  if p_opening_amount is null or p_opening_amount < 0 then
    raise exception 'Monto de apertura inválido.' using errcode = '22023';
  end if;

  select branch_id into v_branch_id
  from public.cash_registers
  where id = p_cash_register_id and is_active;

  if v_branch_id is null then
    raise exception 'Caja no encontrada o inactiva.' using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esta sucursal.' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.cash_register_users
    where cash_register_id = p_cash_register_id
      and user_id = v_user_id
      and is_active
  ) then
    raise exception 'No tienes acceso a esta caja.' using errcode = '42501';
  end if;

  -- Validación nueva: solo rechazar si YA hay sesión abierta en ESTA caja.
  -- Otras cajas pueden estar abiertas en paralelo.
  if exists (
    select 1 from public.cash_sessions
    where branch_id = v_branch_id
      and opened_by = v_user_id
      and cash_register_id = p_cash_register_id
      and status = 'open'
  ) then
    raise exception 'Ya tienes una sesión abierta en esta caja. Entra a esa sesión en lugar de abrir otra.'
      using errcode = '23505';
  end if;

  insert into public.cash_sessions (
    branch_id, opened_by, status, opened_at,
    opening_amount, expected_amount, notes, cash_register_id
  ) values (
    v_branch_id, v_user_id, 'open', timezone('utc', now()),
    round(p_opening_amount::numeric, 2), round(p_opening_amount::numeric, 2),
    nullif(trim(coalesce(p_notes, '')), ''), p_cash_register_id
  )
  returning id into v_session_id;

  return v_session_id;
end;
$$;

grant execute on function public.open_cash_session_for_register(uuid, numeric, text)
  to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) checkout_sale_transactional: aceptar p_cash_session_id explícito
-- ─────────────────────────────────────────────────────────────────────────
-- Si el cliente pasa p_cash_session_id, esa es la sesión usada para
-- registrar la venta y el pago (validando que sea del usuario actual y
-- esté abierta). Si pasa NULL, fallback al comportamiento legacy: usar
-- la sesión más reciente del usuario en la sucursal.

create or replace function public.checkout_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_as_credit boolean default false,
  p_payment_method text default null,
  p_client_id uuid default null,
  p_notes text default null,
  p_credit_due_days integer default null,
  p_cash_session_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_receipt_type public.receipt_type;
  v_sale_status public.sale_status;
  v_payment_method public.payment_method;
  v_sale_id uuid;
  v_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_paid_amount numeric(14,2) := 0;
  v_balance_due numeric(14,2) := 0;
  v_open_cash_session_id uuid;
  v_client record;
  v_item record;
  v_product record;
  v_item_count integer := 0;
  v_note text;
  v_now timestamptz := timezone('utc', now());
  v_default_days integer;
  v_due_days integer;
  v_due_date date;
  v_enforce_stock boolean := true;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida. Inicia sesión de nuevo.'
      using errcode = '28000';
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal actual.'
      using errcode = '42501';
  end if;

  if not public.can_operate_pos() then
    raise exception 'Tu rol no puede operar el POS.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_sale_status := case when p_as_credit then 'credit'::public.sale_status
                        else 'completed'::public.sale_status end;
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  if not p_as_credit then
    begin
      v_payment_method := coalesce(nullif(trim(p_payment_method), ''), 'cash')
        ::public.payment_method;
    exception
      when invalid_text_representation then
        raise exception 'Método de pago no soportado: %', p_payment_method
          using errcode = '22023';
    end;
  end if;

  if p_client_id is not null then
    select c.id, c.full_name, c.balance_due, c.credit_limit, c.is_active
    into v_client
    from public.clients c
    where c.id = p_client_id and c.branch_id = v_branch_id;
    if not found then
      raise exception 'Cliente no encontrado en la sucursal actual.'
        using errcode = '23503';
    end if;
    if not v_client.is_active then
      raise exception 'Cliente "%": cuenta inactiva.', v_client.full_name
        using errcode = '22023';
    end if;
  end if;

  if p_as_credit and p_client_id is null then
    raise exception 'Las ventas a crédito requieren un cliente.'
      using errcode = '22023';
  end if;

  -- Resolver la sesión de caja: explícita > más reciente del usuario.
  if p_cash_session_id is not null then
    select id into v_open_cash_session_id
      from public.cash_sessions
     where id = p_cash_session_id
       and branch_id = v_branch_id
       and opened_by = v_user_id
       and status = 'open';

    if v_open_cash_session_id is null then
      raise exception 'La caja seleccionada no está abierta o no es tuya.'
        using errcode = '22023';
    end if;
  else
    -- Fallback legacy: sesión abierta más reciente del usuario.
    select id into v_open_cash_session_id
      from public.cash_sessions
     where branch_id = v_branch_id
       and status = 'open'
       and opened_by = v_user_id
     order by opened_at desc
     limit 1;
  end if;

  begin
    select coalesce(s.inv_disallow_no_stock, true)
      into v_enforce_stock
      from public.app_settings s
      join public.branches b on b.company_id = s.company_id
     where b.id = v_branch_id
     limit 1;
    if v_enforce_stock is null then
      v_enforce_stock := true;
    end if;
  exception
    when undefined_column or undefined_table or undefined_function then
      v_enforce_stock := true;
  end;

  create temp table if not exists tmp_checkout_items (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2)
  ) on commit drop;
  truncate tmp_checkout_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en el carrito.' using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;

    select p.id, p.name, p.price, p.tax_rate, p.stock, p.is_active,
           p.allow_negative_stock, p.is_service, p.is_tax_exempt
    into v_product
    from public.products p
    where p.id = v_item.product_id and p.branch_id = v_branch_id;

    if not found then
      raise exception 'Producto no encontrado: %', v_item.product_id
        using errcode = '23503';
    end if;
    if not v_product.is_active then
      raise exception 'Producto "%": inactivo.', v_product.name
        using errcode = '22023';
    end if;

    if v_enforce_stock
       and (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    insert into tmp_checkout_items
    values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      case when v_product.is_tax_exempt then 0 else v_product.tax_rate end,
      round((v_item.unit_price * v_item.quantity)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             case when v_product.is_tax_exempt then 0
                  else v_product.tax_rate end / 100)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             (1 + case when v_product.is_tax_exempt then 0
                       else v_product.tax_rate end / 100))::numeric, 2)
    );
    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos válidos en el carrito.'
      using errcode = '22023';
  end if;

  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_checkout_items;

  v_paid_amount := case when p_as_credit then 0 else v_total_amount end;
  v_balance_due := case when p_as_credit then v_total_amount else 0 end;

  if p_as_credit then
    select credit_default_days into v_default_days
    from public.app_settings where id = 1;
    v_default_days := coalesce(v_default_days, 30);
    v_due_days := coalesce(p_credit_due_days, v_default_days);
    if v_due_days <= 0 or v_due_days > 365 then
      v_due_days := v_default_days;
    end if;
    v_due_date := (v_now at time zone 'UTC')::date
                  + (v_due_days || ' days')::interval;
  end if;

  v_sale_number := 'VTA-'
    || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS')
    || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));

  insert into public.sales (
    branch_id, sale_number, client_id, cashier_id, receipt_type, status,
    sale_date, subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, balance_due, notes, due_date, cash_session_id
  ) values (
    v_branch_id, v_sale_number, p_client_id, v_user_id, v_receipt_type,
    v_sale_status, v_now, v_subtotal, 0, v_tax_amount, v_total_amount,
    v_paid_amount, v_balance_due, v_note, v_due_date, v_open_cash_session_id
  )
  returning id into v_sale_id;

  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, 0, tax_rate, line_subtotal, line_tax, line_total
  from tmp_checkout_items
  order by product_id;

  if not p_as_credit then
    insert into public.payments (
      branch_id, sale_id, client_id, cash_session_id, payment_method,
      amount, paid_at, reference, notes
    ) values (
      v_branch_id, v_sale_id, p_client_id, v_open_cash_session_id,
      v_payment_method, v_total_amount, v_now, v_sale_number, v_note
    );
  elsif p_client_id is not null then
    update public.clients
    set balance_due = round(
      (coalesce(balance_due, 0) + v_total_amount)::numeric, 2
    )
    where id = p_client_id and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'sale_number', v_sale_number,
    'branch_id', v_branch_id,
    'cash_session_id', v_open_cash_session_id,
    'receipt_type', v_receipt_type,
    'status', v_sale_status,
    'subtotal', v_subtotal,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'due_date', v_due_date,
    'items_count', (select count(*) from tmp_checkout_items)
  );
end;
$$;

grant execute on function public.checkout_sale_transactional(
  jsonb, text, boolean, text, uuid, text, integer, uuid
) to authenticated;

commit;
