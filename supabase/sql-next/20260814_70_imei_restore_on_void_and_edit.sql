-- ============================================================================
-- Migración 70 — IMEIs: devolver el equipo al inventario al anular/editar
-- ============================================================================
-- El modelo de IMEI es destructivo: `products.imeis` es un text[], vender saca
-- el IMEI del array y lo COPIA a `sale_items.imeis`. Esa copia en la línea de
-- venta es la ÚNICA que queda. Por lo tanto, cualquier borrado de sale_items
-- destruye el último rastro del equipo: el teléfono desaparece del sistema.
--
-- Dos RPCs borran sale_items hoy:
--   · public.void_sale_with_stock_return(uuid)   — anular venta
--   · public.edit_sale_transactional(...)        — editar venta
--
-- Esta migración los corrige: ANTES del `delete from public.sale_items`,
-- devuelven los IMEIs de las líneas viejas al producto con
-- public.restore_product_imeis(). El orden importa: hacerlo después es tarde,
-- los IMEIs ya se perdieron.
--
-- Además crea los índices GIN que permiten "buscar la factura por IMEI".
--
-- Ejecutar después de:
--   supabase/sql-next/20260521_30_void_sale_with_stock_return.sql
--   supabase/sql-next/20260717_66_tax_inclusive_pricing.sql
--   supabase/sql-next/20260814_69_returns_cash_and_imeis.sql  (define el helper)
--
-- Idempotente.
-- ============================================================================

begin;

-- ============================================================================
-- 1) Helper (re-declarado idéntico a la migración 69 para que este archivo
--    pueda correrse solo). `create or replace` con el mismo cuerpo.
-- ============================================================================

create or replace function public.restore_product_imeis(
  p_product_id uuid,
  p_branch_id uuid,
  p_imeis text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_product_id is null or p_branch_id is null then
    return;
  end if;

  if coalesce(array_length(p_imeis, 1), 0) = 0 then
    return;
  end if;

  update public.products p
     set imeis = coalesce(
           (
             select array_agg(s.v order by s.v)
               from (
                 select distinct nullif(trim(x), '') as v
                   from unnest(
                     coalesce(p.imeis, '{}'::text[]) || coalesce(p_imeis, '{}'::text[])
                   ) as x
               ) s
              where s.v is not null
           ),
           '{}'::text[]
         )
   where p.id = p_product_id
     and p.branch_id = p_branch_id;
end;
$$;

grant execute on function public.restore_product_imeis(uuid, uuid, text[])
  to authenticated;

-- ============================================================================
-- 2) Índices GIN — buscar la factura (o la devolución) por IMEI
-- ============================================================================
-- Permiten `where imeis @> array['359...']` sin escanear toda la tabla.

create index if not exists sale_items_imeis_gin
  on public.sale_items using gin (imeis);

create index if not exists return_items_imeis_gin
  on public.return_items using gin (imeis);

-- ============================================================================
-- 3) void_sale_with_stock_return — devolver IMEIs antes de borrar las líneas
-- ============================================================================
-- Copia de 20260521_30_void_sale_with_stock_return.sql con un paso 1 nuevo.

create or replace function public.void_sale_with_stock_return(
  p_sale_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_status public.sale_status;
  v_line record;
begin
  if p_sale_id is null then
    raise exception 'p_sale_id es requerido.'
      using errcode = '22023';
  end if;

  select branch_id, status into v_branch_id, v_status
  from public.sales
  where id = p_sale_id;

  if v_branch_id is null then
    raise exception 'Venta no encontrada.'
      using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esta venta.'
      using errcode = '42501';
  end if;

  if v_status = 'voided'::public.sale_status then
    raise exception 'La venta ya está anulada.'
      using errcode = '23505';
  end if;

  -- 0) Devolver los IMEIs al inventario. TIENE que ir antes del delete: la
  --    línea de venta es la única copia que queda del IMEI.
  for v_line in
    select si.product_id, si.branch_id, si.imeis
      from public.sale_items si
     where si.sale_id = p_sale_id
       and coalesce(array_length(si.imeis, 1), 0) > 0
  loop
    perform public.restore_product_imeis(
      v_line.product_id, v_line.branch_id, v_line.imeis
    );
  end loop;

  -- 1) Borrar sale_items. El trigger trg_sale_items_stock corre por cada
  --    fila y devuelve el stock al producto.
  delete from public.sale_items
  where sale_id = p_sale_id;

  -- 2) Borrar pagos vinculados (no quedan apuntando a una venta anulada).
  delete from public.payments
  where sale_id = p_sale_id;

  -- 3) Marcar la venta como anulada.
  update public.sales
    set status = 'voided'::public.sale_status,
        updated_at = timezone('utc', now())
  where id = p_sale_id;
end;
$$;

grant execute on function public.void_sale_with_stock_return(uuid)
  to authenticated;

-- ============================================================================
-- 4) edit_sale_transactional — round-trip completo de IMEIs
-- ============================================================================
-- Copia de la versión vigente en 20260717_66_tax_inclusive_pricing.sql
-- (líneas 769-1107), con la matemática de ITBIS incluido intacta, más:
--   · paso 0: los IMEIs de las líneas VIEJAS vuelven al producto (antes del
--     delete, que es lo que los destruía).
--   · las líneas NUEVAS aceptan `imeis` en p_items: se guardan en sale_items
--     y se vuelven a sacar del inventario.
-- Si el cliente Dart todavía no manda `imeis` al editar, el resultado es que
-- los equipos quedan DISPONIBLES en el producto y la venta editada sin IMEIs.
-- Es una inconsistencia visible y corregible a mano; perder el IMEI no lo es.
-- En ese caso se emite un `raise notice` para dejar rastro en los logs.

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
      coalesce((item->>'discount_pct')::numeric, 0)::numeric(5,2) as discount_pct,
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
    if v_item.discount_pct < 0 or v_item.discount_pct > 100 then
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

    if (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and coalesce(v_product.track_inventory, true)
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
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
      v_disc numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity * v_item.discount_pct / 100)::numeric,
        2
      );
      v_sub numeric(14,2);
      v_tax numeric(14,2);
      v_line_total numeric(14,2);
    begin
      if coalesce(v_product.price_includes_tax, false) and v_rate > 0 then
        -- Precio con ITBIS incluido: el neto tras descuento es el total exacto
        -- y el impuesto se extrae.
        v_line_total := round((v_gross - v_disc)::numeric, 2);
        v_tax := round((v_line_total * v_rate / (100 + v_rate))::numeric, 2);
        v_sub := v_line_total - v_tax;
      else
        -- Exclusivo (comportamiento histórico, mismos redondeos).
        v_sub := round((v_gross - v_disc)::numeric, 2);
        v_tax := round((v_sub * v_rate / 100)::numeric, 2);
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
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
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

  -- 8) Actualizar la fila sales.
  update public.sales
  set
    subtotal = v_subtotal,
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
