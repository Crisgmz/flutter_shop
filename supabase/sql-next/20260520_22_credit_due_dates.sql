-- Plazos de crédito por venta.
--
-- Diseño:
--   1. Nuevo campo `due_date` (date) en `sales` — fecha de vencimiento del
--      crédito. Se setea automáticamente al hacer una venta a crédito (RPC
--      `checkout_sale_transactional`) sumando `app_settings.credit_default_days`
--      a la fecha de venta. Permite override por venta.
--   2. Dos campos nuevos en `app_settings`:
--        - `credit_default_days` (int, default 30): plazo estándar
--        - `credit_warn_days` (int, default 7): umbral de alerta "próximo a vencer"
--   3. Backfill: ventas a crédito existentes reciben
--      `due_date = sale_date::date + credit_default_days`.
--   4. RPC `checkout_sale_transactional` extendido con `p_credit_due_days`.
--      Si la venta no es a crédito, se ignora.
--
-- Ejecutar después de los anteriores 01-21. Idempotente.

begin;

-- 1) Columna due_date en sales -------------------------------------------------

alter table public.sales
  add column if not exists due_date date;

create index if not exists idx_sales_credit_due_date
  on public.sales (branch_id, due_date)
  where status = 'credit' and balance_due > 0;

-- 2) Settings: días default + umbral de alerta --------------------------------

alter table public.app_settings
  add column if not exists credit_default_days integer not null default 30,
  add column if not exists credit_warn_days integer not null default 7;

-- Validaciones suaves: días positivos.
alter table public.app_settings
  drop constraint if exists app_settings_credit_default_days_positive;
alter table public.app_settings
  add constraint app_settings_credit_default_days_positive
  check (credit_default_days > 0 and credit_default_days <= 365);

alter table public.app_settings
  drop constraint if exists app_settings_credit_warn_days_positive;
alter table public.app_settings
  add constraint app_settings_credit_warn_days_positive
  check (credit_warn_days >= 0 and credit_warn_days <= 90);

-- 3) Backfill de due_date en ventas a crédito sin fecha -----------------------

update public.sales s
set due_date = (s.sale_date at time zone 'UTC')::date
              + (coalesce(a.credit_default_days, 30) || ' days')::interval
from public.app_settings a
where s.status = 'credit'
  and s.balance_due > 0
  and s.due_date is null
  and a.id = 1;

-- 4) RPC extendido: acepta p_credit_due_days ----------------------------------
-- Reemplaza la firma anterior para incluir el nuevo parámetro al final.
-- El cliente puede pasar null para usar el default de app_settings.

create or replace function public.checkout_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_as_credit boolean default false,
  p_payment_method text default null,
  p_client_id uuid default null,
  p_notes text default null,
  p_credit_due_days integer default null
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

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_sale_status := case when p_as_credit then 'credit'::public.sale_status else 'completed'::public.sale_status end;
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  if not p_as_credit then
    begin
      v_payment_method := coalesce(nullif(trim(p_payment_method), ''), 'cash')::public.payment_method;
    exception
      when invalid_text_representation then
        raise exception 'Método de pago no soportado: %', p_payment_method
          using errcode = '22023';
    end;
  end if;

  if p_client_id is not null then
    select
      c.id,
      c.full_name,
      c.balance_due,
      c.credit_limit,
      c.is_active
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

  -- Determinar la sesión de caja abierta en la sucursal (si la hay).
  select id into v_open_cash_session_id
  from public.cash_sessions
  where branch_id = v_branch_id and status = 'open'
  order by opened_at desc
  limit 1;

  -- Tabla temporal con los items normalizados.
  -- `on commit drop` la elimina al final de la transacción, así que no es
  -- necesario limpiar al inicio (un DELETE sin WHERE además es rechazado
  -- por Supabase en algunos esquemas de seguridad).
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
      raise exception 'Producto sin id en el carrito.'
        using errcode = '22023';
    end if;

    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;

    select
      p.id,
      p.name,
      p.price,
      p.tax_rate,
      p.stock,
      p.is_active,
      p.allow_negative_stock,
      p.is_service,
      p.is_tax_exempt
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

    if (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    insert into tmp_checkout_items (
      product_id,
      description,
      quantity,
      unit_price,
      tax_rate,
      line_subtotal,
      line_tax,
      line_total
    ) values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      case when v_product.is_tax_exempt then 0 else v_product.tax_rate end,
      round((v_item.unit_price * v_item.quantity)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             case when v_product.is_tax_exempt then 0 else v_product.tax_rate end / 100)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             (1 + case when v_product.is_tax_exempt then 0 else v_product.tax_rate end / 100))::numeric, 2)
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

  -- Calcular due_date si la venta es a crédito.
  if p_as_credit then
    select credit_default_days into v_default_days
    from public.app_settings
    where id = 1;

    v_default_days := coalesce(v_default_days, 30);
    v_due_days := coalesce(p_credit_due_days, v_default_days);

    if v_due_days <= 0 or v_due_days > 365 then
      v_due_days := v_default_days;
    end if;

    v_due_date := (v_now at time zone 'UTC')::date + (v_due_days || ' days')::interval;
  end if;

  v_sale_number := 'VTA-' || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));

  insert into public.sales (
    branch_id,
    sale_number,
    client_id,
    cashier_id,
    receipt_type,
    status,
    sale_date,
    subtotal,
    discount_amount,
    tax_amount,
    total_amount,
    paid_amount,
    balance_due,
    notes,
    due_date
  ) values (
    v_branch_id,
    v_sale_number,
    p_client_id,
    v_user_id,
    v_receipt_type,
    v_sale_status,
    v_now,
    v_subtotal,
    0,
    v_tax_amount,
    v_total_amount,
    v_paid_amount,
    v_balance_due,
    v_note,
    v_due_date
  )
  returning id into v_sale_id;

  insert into public.sale_items (
    sale_id,
    branch_id,
    product_id,
    description,
    quantity,
    unit_price,
    discount_amount,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total
  )
  select
    v_sale_id,
    v_branch_id,
    product_id,
    description,
    quantity,
    unit_price,
    0,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total
  from tmp_checkout_items
  order by product_id;

  if not p_as_credit then
    insert into public.payments (
      branch_id,
      sale_id,
      client_id,
      cash_session_id,
      payment_method,
      amount,
      paid_at,
      reference,
      notes
    ) values (
      v_branch_id,
      v_sale_id,
      p_client_id,
      v_open_cash_session_id,
      v_payment_method,
      v_total_amount,
      v_now,
      v_sale_number,
      v_note
    );
  elsif p_client_id is not null then
    update public.clients
    set balance_due = round((coalesce(balance_due, 0) + v_total_amount)::numeric, 2)
    where id = p_client_id
      and branch_id = v_branch_id;
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

grant execute on function public.checkout_sale_transactional(jsonb, text, boolean, text, uuid, text, integer) to authenticated;

commit;
