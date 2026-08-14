-- ============================================================================
-- Migración 77 — Editar una venta deja de perder (y de inventar) el descuento
-- ============================================================================
-- BUG DE DINERO REAL. Facturar y editar hablaban idiomas distintos:
--   · checkout/hold (migración 76) reciben `discount_amount` — MONTO.
--   · `edit_sale_transactional` (migración 70) recibía `discount_pct` —
--     PORCENTAJE, casteado a numeric(5,2).
-- Y el cliente Dart reconstruía el porcentaje como
-- `(bruto − line_subtotal) / bruto × 100`. Dos consecuencias, las dos caras:
--
--   (a) Producto con ITBIS INCLUIDO. `line_subtotal` se guarda SIN impuesto,
--       así que la resta lee el ITBIS como si fuera descuento. Un producto de
--       118.00 sin ningún descuento daba pct = 15.25 y, con solo abrir y
--       guardar la edición, el total caía de 118.00 a 100.00. La venta perdía
--       18 pesos que el cliente ya había pagado.
--   (b) Pérdida por el cast. Bruto 5000 con descuento 100.05 → pct 2.001 →
--       numeric(5,2) lo corta a 2.00 → el descuento pasa a 100.00. Cada
--       edición raspaba centavos.
--
-- ARREGLO
--   1) `edit_sale_transactional` recibe `discount_amount` (MONTO) por ítem y
--      aplica EXACTAMENTE la fórmula de la migración 76:
--        bruto     = round(unit_price × quantity, 2)
--        descuento = clamp(discount_amount, 0, bruto)
--        neto      = bruto − descuento
--        con price_includes_tax y tasa > 0:
--          line_total = neto; line_tax = round(neto × t / (100 + t), 2);
--          line_subtotal = line_total − line_tax
--        si no:
--          line_subtotal = neto; line_tax = round(neto × t / 100, 2);
--          line_total = line_subtotal + line_tax
--      Facturar, guardar cuenta y editar quedan con la MISMA matemática.
--   2) `discount_pct` se sigue aceptando como FALLBACK: solo se usa si el ítem
--      no trae `discount_amount`. Sirve para no romper mientras un cliente
--      viejo siga en la calle. El cliente Dart de este repo ya manda el monto.
--   3) `sales.discount_amount` (la cabecera) guarda la SUMA de los descuentos
--      de línea, igual que la 76. Es informativa: el subtotal ya viene NETO,
--      así que subtotal + tax_amount = total_amount se mantiene y NADIE debe
--      restarla otra vez.
--   4) `report_discounts_view` se recrea para que el porcentaje se calcule
--      sobre el BRUTO (subtotal + descuento) y no sobre el subtotal ya neto,
--      que lo sobreestimaba. El filtro `discount_amount > 0` ya no deja el
--      reporte vacío porque la cabecera por fin trae el monto.
--
-- CONSUMIDORES DE `sales.discount_amount` REVISADOS (ninguno descuenta dos
-- veces, porque ninguno resta la cabecera del subtotal):
--   · `report_discounts_view` — se recrea aquí (punto 4).
--   · `sales_daily_view` / `mv_sales_daily` — `discount_total` = suma de la
--     cabecera (antes siempre 0, ahora el monto real) y `net_total` = suma de
--     `total_amount`, que se lee directo. OJO con el nombre: `gross_total` es
--     `sum(subtotal)`, o sea NETO de descuento; se deja como está para no
--     cambiarle el significado a los reportes que ya lo consumen.
--   · trigger de NCF (migraciones 18/21) — copia la cabecera a
--     `fiscal_documents.discount_amount`; es un snapshot informativo.
--   · `convert_quote_paid` (migración 62) — copia `quotations.discount_amount`
--     (siempre 0: la cotización también guarda el descuento por línea).
--   · Recibo impreso — `SalePrintDocumentAdapter` imprime el subtotal BRUTO
--     (subtotal + descuento) y debajo la fila "Descuento", así el papel cuadra.
--
-- La función de abajo es copia FIEL de su definición vigente en
-- 20260814_70_imei_restore_on_void_and_edit.sql, con solo los cambios de
-- arriba. Queda intacto: la restauración de IMEIs de las líneas viejas (paso
-- 0), el re-descuento de los IMEIs que quedan (paso 5b), el guard de
-- `track_inventory` al restaurar y al aplicar stock, el manejo de pagos y el
-- ajuste de `clients.balance_due`. La firma no cambia, así que basta
-- `create or replace` (sin drops) y el grant se repite idéntico.
--
-- Ejecutar después de:
--   supabase/sql-next/20260814_76_checkout_line_discount.sql
--
-- Idempotente.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1) edit_sale_transactional — descuento por línea en MONTO
-- ----------------------------------------------------------------------------

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

-- ----------------------------------------------------------------------------
-- 2) report_discounts_view — el porcentaje se calcula sobre el bruto
-- ----------------------------------------------------------------------------
-- Copia de 20260509_13_reports_round2_views.sql con un solo cambio: el
-- denominador. `s.subtotal` ya viene NETO de descuento, así que dividir por él
-- inflaba el porcentaje (200 de descuento sobre 800 netos daba 25% cuando el
-- descuento real fue 200/1000 = 20%). El bruto es subtotal + discount_amount.
-- El filtro `discount_amount > 0` se mantiene: ahora la cabecera sí trae el
-- monto (migraciones 76 y 77), así que el reporte deja de salir vacío.
--
-- OJO: las ventas ANTERIORES a estas migraciones tienen la cabecera en 0 y no
-- van a aparecer en este reporte. No se hace backfill a propósito: los
-- `sale_items.discount_amount` que escribió la versión vieja de
-- edit_sale_transactional sobre productos con ITBIS incluido son montos
-- inventados (leyeron el impuesto como descuento) y arrastrarlos al reporte
-- sería propagar el error.

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
  case when (s.subtotal + s.discount_amount) > 0
       then round(
         (s.discount_amount / (s.subtotal + s.discount_amount)) * 100, 2
       )
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

notify pgrst, 'reload schema';
