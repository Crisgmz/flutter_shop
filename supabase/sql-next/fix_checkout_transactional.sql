-- Fix: deploy checkout_sale_transactional and normalize_receipt_type.
-- Run this in the Supabase SQL Editor to register the functions and
-- reload the PostgREST schema cache so the RPC is immediately callable.

-- =========================================================
-- Helper: canonical receipt_type normalization
-- =========================================================
create or replace function public.normalize_receipt_type(p_value text)
returns public.receipt_type
language plpgsql
stable
set search_path = public
as $$
declare
  v_normalized text;
begin
  v_normalized := lower(coalesce(trim(p_value), ''));
  v_normalized := replace(v_normalized, 'á', 'a');
  v_normalized := replace(v_normalized, 'é', 'e');
  v_normalized := replace(v_normalized, 'í', 'i');
  v_normalized := replace(v_normalized, 'ó', 'o');
  v_normalized := replace(v_normalized, 'ú', 'u');
  v_normalized := regexp_replace(v_normalized, '[^a-z0-9]+', '_', 'g');
  v_normalized := regexp_replace(v_normalized, '_+',          '_', 'g');
  v_normalized := regexp_replace(v_normalized, '^_|_$',       '',  'g');

  case v_normalized
    when '', 'consumer_final', 'consumidor_final' then
      return 'consumer_final'::public.receipt_type;
    when 'fiscal_credit', 'credito_fiscal' then
      return 'fiscal_credit'::public.receipt_type;
    when 'governmental', 'gubernamental' then
      return 'governmental'::public.receipt_type;
    when 'special', 'regimen_especial' then
      return 'special'::public.receipt_type;
    when 'export', 'exportacion' then
      return 'export'::public.receipt_type;
    else
      raise exception 'Tipo de comprobante no soportado: %', p_value
        using errcode = '22023';
  end case;
end;
$$;

grant execute on function public.normalize_receipt_type(text) to authenticated;

-- =========================================================
-- Main POS checkout RPC
-- =========================================================
create or replace function public.checkout_sale_transactional(
  p_items          jsonb,
  p_receipt_type   text    default 'consumer_final',
  p_as_credit      boolean default false,
  p_payment_method text    default null,
  p_client_id      uuid    default null,
  p_notes          text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id             uuid               := auth.uid();
  v_branch_id           uuid               := public.current_branch_id();
  v_receipt_type        public.receipt_type;
  v_sale_status         public.sale_status;
  v_payment_method      public.payment_method;
  v_sale_id             uuid;
  v_sale_number         text;
  v_subtotal            numeric(14,2)      := 0;
  v_tax_amount          numeric(14,2)      := 0;
  v_total_amount        numeric(14,2)      := 0;
  v_paid_amount         numeric(14,2)      := 0;
  v_balance_due         numeric(14,2)      := 0;
  v_open_cash_session_id uuid;
  v_client              record;
  v_item                record;
  v_product             record;
  v_item_count          integer            := 0;
  v_note                text;
  v_now                 timestamptz        := timezone('utc', now());
begin
  -- Auth guards
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

  -- Validate items array
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  -- Normalize inputs
  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_sale_status  := case when p_as_credit
                         then 'credit'::public.sale_status
                         else 'completed'::public.sale_status end;
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  -- Payment method (cash sales only)
  if not p_as_credit then
    begin
      v_payment_method :=
        coalesce(nullif(trim(p_payment_method), ''), 'cash')::public.payment_method;
    exception
      when invalid_text_representation then
        raise exception 'Método de pago no soportado: %', p_payment_method
          using errcode = '22023';
    end;
  end if;

  -- Resolve client
  if p_client_id is not null then
    select c.id, c.full_name, c.legal_name, c.document_number, c.is_active
      into v_client
      from public.clients c
     where c.id = p_client_id
       and c.branch_id = v_branch_id
     limit 1;

    if not found then
      raise exception 'El cliente seleccionado no existe en la sucursal actual.'
        using errcode = '23503';
    end if;

    if coalesce(v_client.is_active, false) is false then
      raise exception 'El cliente seleccionado está inactivo.'
        using errcode = '22023';
    end if;
  end if;

  if p_as_credit and p_client_id is null then
    raise exception 'Para ventas a crédito debe seleccionar un cliente.'
      using errcode = '22023';
  end if;

  -- Fiscal comprobante requires client + document
  if v_receipt_type <> 'consumer_final'::public.receipt_type then
    if p_client_id is null then
      raise exception 'Debe seleccionar un cliente para este tipo de comprobante.'
        using errcode = '22023';
    end if;
    if nullif(trim(coalesce(v_client.document_number, '')), '') is null then
      raise exception 'El cliente debe tener documento fiscal para este comprobante.'
        using errcode = '22023';
    end if;
    if nullif(trim(coalesce(v_client.legal_name, v_client.full_name, '')), '') is null then
      raise exception 'El cliente debe tener nombre válido para este comprobante.'
        using errcode = '22023';
    end if;
  end if;

  -- Temp table: drop first so connection-pool session reuse never sees stale data
  drop table if exists tmp_checkout_items;
  create temporary table tmp_checkout_items (
    product_id    uuid          primary key,
    description   text,
    quantity      numeric(14,3) not null,
    unit_price    numeric(14,2) not null,
    tax_rate      numeric(5,2)  not null,
    line_subtotal numeric(14,2),
    line_tax      numeric(14,2),
    line_total    numeric(14,2)
  ) on commit drop;

  -- Load items from JSON
  for v_item in
    select *
      from jsonb_to_recordset(p_items) as x(
        product_id  uuid,
        description text,
        quantity    numeric,
        unit_price  numeric,
        tax_rate    numeric
      )
  loop
    v_item_count := v_item_count + 1;

    if v_item.product_id is null then
      raise exception 'Hay una línea sin producto válido.'
        using errcode = '22023';
    end if;
    if coalesce(v_item.quantity, 0) <= 0 then
      raise exception 'La cantidad del producto % debe ser mayor que cero.', v_item.product_id
        using errcode = '22023';
    end if;
    if coalesce(v_item.unit_price, 0) < 0 then
      raise exception 'El precio del producto % no es válido.', v_item.product_id
        using errcode = '22023';
    end if;
    if coalesce(v_item.tax_rate, 0) < 0 or coalesce(v_item.tax_rate, 0) > 100 then
      raise exception 'La tasa de impuesto del producto % no es válida.', v_item.product_id
        using errcode = '22023';
    end if;

    insert into tmp_checkout_items (product_id, description, quantity, unit_price, tax_rate)
    values (
      v_item.product_id,
      nullif(trim(coalesce(v_item.description, '')), ''),
      round(v_item.quantity::numeric, 3),
      round(v_item.unit_price::numeric, 2),
      round(v_item.tax_rate::numeric, 2)
    )
    on conflict (product_id) do update set
      description = coalesce(excluded.description, tmp_checkout_items.description),
      quantity    = round(tmp_checkout_items.quantity + excluded.quantity, 3),
      unit_price  = excluded.unit_price,
      tax_rate    = excluded.tax_rate;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos en el carrito.' using errcode = '22023';
  end if;

  -- Validate stock and compute line totals
  for v_item in select * from tmp_checkout_items order by product_id loop
    select p.id, p.name, p.stock, p.is_active
      into v_product
      from public.products p
     where p.id = v_item.product_id
       and p.branch_id = v_branch_id
     for update;

    if not found then
      raise exception 'Producto no encontrado en la sucursal actual: %', v_item.product_id
        using errcode = '23503';
    end if;
    if coalesce(v_product.is_active, false) is false then
      raise exception 'El producto % está inactivo.',
        coalesce(v_product.name, v_item.product_id::text)
        using errcode = '22023';
    end if;
    if coalesce(v_product.stock, 0) < v_item.quantity then
      raise exception 'Stock insuficiente para %: disponible %, solicitado %.',
        coalesce(v_product.name, v_item.product_id::text),
        round(coalesce(v_product.stock, 0)::numeric, 3),
        round(v_item.quantity::numeric, 3)
        using errcode = '22023';
    end if;

    update tmp_checkout_items set
      description   = coalesce(v_item.description, v_product.name),
      line_subtotal = round((v_item.quantity * v_item.unit_price)::numeric, 2),
      line_tax      = round((v_item.quantity * v_item.unit_price * v_item.tax_rate / 100)::numeric, 2),
      line_total    = round((v_item.quantity * v_item.unit_price * (1 + v_item.tax_rate / 100))::numeric, 2)
    where product_id = v_item.product_id;
  end loop;

  -- Aggregate totals
  select
    round(coalesce(sum(line_subtotal), 0)::numeric, 2),
    round(coalesce(sum(line_tax),      0)::numeric, 2),
    round(coalesce(sum(line_total),    0)::numeric, 2)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_checkout_items;

  v_paid_amount := case when p_as_credit then 0            else v_total_amount end;
  v_balance_due := case when p_as_credit then v_total_amount else 0             end;

  -- Require open cash session for cash sales
  if not p_as_credit then
    select cs.id
      into v_open_cash_session_id
      from public.cash_sessions cs
     where cs.branch_id = v_branch_id
       and cs.status    = 'open'::public.cash_session_status
     order by cs.opened_at desc
     limit 1
     for update;

    if v_open_cash_session_id is null then
      raise exception 'Debe abrir una sesión de caja antes de cobrar una venta.'
        using errcode = '22023';
    end if;
  end if;

  -- Build sale number
  v_sale_number := 'VTA-'
    || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS')
    || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));

  -- Insert sale header
  insert into public.sales (
    branch_id, sale_number, client_id, cashier_id,
    receipt_type, status, sale_date,
    subtotal, discount_amount, tax_amount,
    total_amount, paid_amount, balance_due, notes
  ) values (
    v_branch_id, v_sale_number, p_client_id, v_user_id,
    v_receipt_type, v_sale_status, v_now,
    v_subtotal, 0, v_tax_amount,
    v_total_amount, v_paid_amount, v_balance_due, v_note
  )
  returning id into v_sale_id;

  -- Insert sale lines
  insert into public.sale_items (
    sale_id, branch_id, product_id, description,
    quantity, unit_price, discount_amount, tax_rate,
    line_subtotal, line_tax, line_total
  )
  select
    v_sale_id, v_branch_id, product_id, description,
    quantity, unit_price, 0, tax_rate,
    line_subtotal, line_tax, line_total
  from tmp_checkout_items
  order by product_id;

  -- Cash sale: record payment
  if not p_as_credit then
    insert into public.payments (
      branch_id, sale_id, client_id, cash_session_id,
      payment_method, amount, paid_at, reference, notes
    ) values (
      v_branch_id, v_sale_id, p_client_id, v_open_cash_session_id,
      v_payment_method, v_total_amount, v_now, v_sale_number, v_note
    );
  -- Credit sale: update client balance
  elsif p_client_id is not null then
    update public.clients
       set balance_due = round((coalesce(balance_due, 0) + v_total_amount)::numeric, 2)
     where id = p_client_id
       and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'sale_id',         v_sale_id,
    'sale_number',     v_sale_number,
    'branch_id',       v_branch_id,
    'cash_session_id', v_open_cash_session_id,
    'receipt_type',    v_receipt_type,
    'status',          v_sale_status,
    'subtotal',        v_subtotal,
    'tax_amount',      v_tax_amount,
    'total_amount',    v_total_amount,
    'paid_amount',     v_paid_amount,
    'balance_due',     v_balance_due,
    'items_count',     (select count(*) from tmp_checkout_items)
  );
end;
$$;

grant execute on function public.checkout_sale_transactional(jsonb, text, boolean, text, uuid, text) to authenticated;

-- Reload PostgREST schema cache so the function is immediately callable
notify pgrst, 'reload schema';
