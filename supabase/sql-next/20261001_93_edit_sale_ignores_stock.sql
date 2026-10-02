-- ============================================================================
-- Migración 93 — Editar una venta ya no valida stock
-- ============================================================================
-- PEDIDO (1 oct 2026): "que se pueda editar aunque no haya en stock".
--
-- La 87 dejó de trancar las ventas con productos en negativo, pero con el
-- interruptor "No permitir venta sin stock" prendido seguía rechazando SUBIR
-- la cantidad o AGREGAR un producto sin existencias:
--
--   Stock insuficiente para "...": disponible 0.000 requerido 2.000
--
-- La venta ya se hizo y la mercancía ya salió; el editor existe para corregir
-- lo que se facturó, no para decidir si se podía vender. Así que el editor
-- deja de validar existencias del todo: el stock se descuenta igual (paso 4)
-- y, si no alcanzaba, el producto queda en negativo, que es lo que el
-- inventario tiene que reflejar.
--
-- El POS NO cambia: al facturar se sigue respetando
-- `app_settings.inv_disallow_no_stock`.
--
-- La función de abajo es copia FIEL de su definición en
-- 20260904_87_edit_sale_negative_stock.sql, quitando solo:
--   - la lectura de `inv_disallow_no_stock` (paso 0-bis),
--   - el snapshot `tmp_edit_prev_qty` (paso 0-ter), que solo servía a la
--     validación,
--   - el `raise exception 'Stock insuficiente ...'`.
-- Todo lo demás queda intacto (IMEIs, descuentos, pagos, saldo del cliente).
-- La firma no cambia: basta `create or replace` y el grant se repite igual.
--
-- Reemplaza a la 87: si la 87 todavía no se corrió, se puede saltar y correr
-- solo esta. Si ya se corrió, esta la pisa.
--
-- Idempotente.
-- ============================================================================

begin;

create or replace function public.edit_sale_transactional(
  p_sale_id uuid,
  p_items jsonb,
  p_client_id uuid default null,
  p_clear_client boolean default false,
  p_notes text default null,
  p_clear_notes boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid;
  v_sale record;
  v_old_total numeric(14,2);
  v_old_client_id uuid;
  v_item record;
  v_product record;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_discount_total numeric(14,2) := 0;
  v_paid_amount numeric(14,2);
  v_balance_due numeric(14,2);
  v_payment_count integer;
  v_note text;
  v_target_client uuid;
  v_item_count integer := 0;
  v_line record;
  v_old_imei_count integer := 0;
  v_new_imei_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida.' using errcode = '28000';
  end if;

  if not public.is_admin()
     and public.current_user_role() <> 'supervisor'::public.app_role then
    raise exception 'Solo admin o supervisor pueden editar ventas.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no puede quedar sin items.'
      using errcode = '22023';
  end if;

  select id, branch_id, status, total_amount, paid_amount, client_id, notes
  into v_sale
  from public.sales
  where id = p_sale_id
  for update;

  if not found then
    raise exception 'Venta % no encontrada.', p_sale_id
      using errcode = '23503';
  end if;

  if v_sale.status = 'voided'::public.sale_status then
    raise exception 'No se puede editar una venta anulada.'
      using errcode = '22023';
  end if;

  v_branch_id := v_sale.branch_id;
  v_old_total := coalesce(v_sale.total_amount, 0);
  v_old_client_id := v_sale.client_id;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta venta.'
      using errcode = '42501';
  end if;

  if p_clear_client then
    v_target_client := null;
  elsif p_client_id is not null then
    v_target_client := p_client_id;
  else
    v_target_client := v_old_client_id;
  end if;

  if v_target_client is not null and v_target_client is distinct from v_old_client_id then
    if not exists (
      select 1 from public.clients
      where id = v_target_client and branch_id = v_branch_id and is_active
    ) then
      raise exception 'Cliente nuevo no válido para esta sucursal.'
        using errcode = '23503';
    end if;
  end if;

  if p_clear_notes then
    v_note := null;
  elsif p_notes is not null then
    v_note := nullif(trim(p_notes), '');
  else
    v_note := v_sale.notes;
  end if;

  -- 0) Devolver al producto los IMEIs de las líneas VIEJAS. Va antes del
  --    delete del paso 2: la línea es la única copia que queda del IMEI.
  for v_line in
    select si.product_id, si.branch_id, si.imeis
      from public.sale_items si
     where si.sale_id = p_sale_id
       and coalesce(array_length(si.imeis, 1), 0) > 0
  loop
    v_old_imei_count := v_old_imei_count + coalesce(array_length(v_line.imeis, 1), 0);
    perform public.restore_product_imeis(
      v_line.product_id, v_line.branch_id, v_line.imeis
    );
  end loop;

  -- 1) Restaurar stock de los items viejos.
  update public.products p
  set stock = round(
    (coalesce(p.stock, 0) + si.quantity)::numeric(14, 3),
    3
  )
  from public.sale_items si
  where si.sale_id = p_sale_id
    and p.id = si.product_id
    and p.branch_id = v_branch_id
    and coalesce(p.is_service, false) = false
    and coalesce(p.track_inventory, true) = true;

  -- 2) Borrar los items viejos.
  delete from public.sale_items where sale_id = p_sale_id;

  -- 3) Tabla temporal con items normalizados.
  create temp table if not exists tmp_edit_items_imeis (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    discount_amount numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2),
    imeis text[]
  ) on commit drop;
  truncate tmp_edit_items_imeis;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      -- Descuento de la línea en MONTO absoluto (criterio unificado con
      -- checkout/hold). `discount_pct` queda solo como fallback para clientes
      -- viejos: se usa únicamente si no vino el monto.
      nullif(item->>'discount_amount', '')::numeric as discount_amount_in,
      nullif(item->>'discount_pct', '')::numeric as discount_pct_in,
      coalesce(
        (select array_agg(x) from jsonb_array_elements_text(
           case when jsonb_typeof(item->'imeis') = 'array'
                then item->'imeis' else '[]'::jsonb end) as x),
        '{}'::text[]) as imeis
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en la edición.'
        using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;
    if v_item.discount_amount_in is null
       and v_item.discount_pct_in is not null
       and (v_item.discount_pct_in < 0 or v_item.discount_pct_in > 100) then
      raise exception 'Descuento fuera de rango (0-100).'
        using errcode = '22023';
    end if;

    select p.id, p.name, p.price, p.tax_rate, p.stock,
           p.is_active, p.allow_negative_stock, p.is_service,
           p.is_tax_exempt, p.track_inventory, p.price_includes_tax
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

    v_new_imei_count := v_new_imei_count + coalesce(array_length(v_item.imeis, 1), 0);

    declare
      v_rate numeric(5,2) := case
        when v_product.is_tax_exempt then 0
        else v_product.tax_rate
      end;
      v_gross numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity)::numeric, 2
      );
      v_disc numeric(14,2);
      v_net numeric(14,2);
      v_sub numeric(14,2);
      v_tax numeric(14,2);
      v_line_total numeric(14,2);
    begin
      -- Monto si vino; si no, el porcentaje del fallback sobre el bruto.
      v_disc := coalesce(
        v_item.discount_amount_in,
        round((v_gross * coalesce(v_item.discount_pct_in, 0) / 100)::numeric, 2)
      );
      -- El descuento nunca puede dejar la línea en negativo ni sumar al total.
      v_disc := least(greatest(v_disc, 0::numeric), v_gross);
      v_net := round((v_gross - v_disc)::numeric, 2);

      if coalesce(v_product.price_includes_tax, false) and v_rate > 0 then
        -- Precio con ITBIS incluido: el neto es el total exacto y el impuesto
        -- se extrae.
        v_line_total := v_net;
        v_tax := round((v_net * v_rate / (100 + v_rate))::numeric, 2);
        v_sub := v_line_total - v_tax;
      else
        -- Exclusivo: el ITBIS se agrega encima del neto.
        v_sub := v_net;
        v_tax := round((v_net * v_rate / 100)::numeric, 2);
        v_line_total := round((v_sub + v_tax)::numeric, 2);
      end if;

      insert into tmp_edit_items_imeis (
        product_id, description, quantity, unit_price, discount_amount,
        tax_rate, line_subtotal, line_tax, line_total, imeis
      ) values (
        v_item.product_id,
        coalesce(nullif(v_item.description, ''), v_product.name),
        v_item.quantity, v_item.unit_price, v_disc, v_rate, v_sub, v_tax,
        v_line_total, coalesce(v_item.imeis, '{}'::text[])
      );
    end;

    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No se procesó ningún item válido.'
      using errcode = '22023';
  end if;

  if v_old_imei_count > 0 and v_new_imei_count = 0 then
    raise notice
      'edit_sale_transactional(%): % IMEI(s) devueltos al inventario porque la edición no envió imeis. La venta editada queda sin IMEIs.',
      p_sale_id, v_old_imei_count;
  end if;

  -- 4) Aplicar el nuevo stock (deducir cantidad nueva).
  update public.products p
  set stock = round(
    (coalesce(p.stock, 0) - tei.quantity)::numeric(14, 3),
    3
  )
  from tmp_edit_items_imeis tei
  where p.id = tei.product_id
    and p.branch_id = v_branch_id
    and coalesce(p.is_service, false) = false
    and coalesce(p.track_inventory, true) = true;

  -- 5) Insertar los nuevos items.
  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis
  )
  select
    p_sale_id, v_branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total,
    coalesce(imeis, '{}'::text[])
  from tmp_edit_items_imeis
  order by product_id;

  -- 5b) Los IMEIs que quedaron en la venta salen otra vez del inventario.
  for v_line in
    select product_id, imeis as sold
      from tmp_edit_items_imeis
     where coalesce(array_length(imeis, 1), 0) > 0
  loop
    update public.products p
       set imeis = coalesce(
             (select array_agg(e order by e)
                from unnest(p.imeis) as e
               where not (e = any(v_line.sold))),
             '{}'::text[])
     where p.id = v_line.product_id and p.branch_id = v_branch_id;
  end loop;

  -- 6) Recalcular totales desde tmp_edit_items_imeis.
  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0),
    coalesce(sum(discount_amount), 0)
  into v_subtotal, v_tax_amount, v_total_amount, v_discount_total
  from tmp_edit_items_imeis;

  -- 7) Pago y saldo según el estado de la venta.
  if v_sale.status = 'completed'::public.sale_status then
    -- Venta pagada: el pago sigue al total (queda saldada).
    v_paid_amount := v_total_amount;
    v_balance_due := 0;

    -- Si hay UN solo pago (caso normal del POS), ajustar su monto para que el
    -- cuadre de caja y los reportes reflejen el total corregido. Si hay varios
    -- (pago dividido), no tocamos los pagos: solo ajustamos el encabezado.
    select count(*) into v_payment_count
      from public.payments where sale_id = p_sale_id;
    if v_payment_count = 1 then
      update public.payments
         set amount = v_total_amount
       where sale_id = p_sale_id;
    end if;
  else
    -- Crédito (u otros): se preserva lo pagado; el saldo se recalcula.
    v_paid_amount := coalesce(v_sale.paid_amount, 0);
    v_balance_due := greatest(
      round((v_total_amount - v_paid_amount)::numeric, 2),
      0
    );
  end if;

  -- 8) Actualizar la fila sales. discount_amount = suma de los descuentos de
  --    línea: informativo para recibo y reportes, NO se resta del total (el
  --    subtotal ya viene neto).
  update public.sales
  set
    subtotal = v_subtotal,
    discount_amount = v_discount_total,
    tax_amount = v_tax_amount,
    total_amount = v_total_amount,
    paid_amount = v_paid_amount,
    balance_due = v_balance_due,
    client_id = v_target_client,
    notes = v_note,
    updated_at = timezone('utc', now())
  where id = p_sale_id;

  -- 9) Ajustar clients.balance_due por la diferencia (solo crédito / saldo).
  if v_sale.status = 'credit'::public.sale_status
     or v_balance_due > 0 then
    if v_old_client_id is distinct from v_target_client then
      if v_old_client_id is not null then
        update public.clients
        set balance_due = greatest(
          round((coalesce(balance_due, 0) - v_old_total)::numeric, 2),
          0
        )
        where id = v_old_client_id and branch_id = v_branch_id;
      end if;
      if v_target_client is not null then
        update public.clients
        set balance_due = round(
          (coalesce(balance_due, 0) + v_total_amount)::numeric, 2
        )
        where id = v_target_client and branch_id = v_branch_id;
      end if;
    elsif v_target_client is not null then
      update public.clients
      set balance_due = greatest(
        round(
          (coalesce(balance_due, 0) + (v_total_amount - v_old_total))::numeric,
          2
        ),
        0
      )
      where id = v_target_client and branch_id = v_branch_id;
    end if;
  end if;

  return jsonb_build_object(
    'sale_id', p_sale_id,
    'subtotal', v_subtotal,
    'discount_amount', v_discount_total,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'items_count', v_item_count,
    'client_id', v_target_client,
    'old_total', v_old_total,
    'imeis_restored', v_old_imei_count,
    'imeis_kept', v_new_imei_count
  );
end;
$$;

grant execute on function public.edit_sale_transactional(
  uuid, jsonb, uuid, boolean, text, boolean
) to authenticated;

commit;

notify pgrst, 'reload schema';
