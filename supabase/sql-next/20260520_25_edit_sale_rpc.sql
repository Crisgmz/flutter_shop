-- RPC para editar una venta completada/a crédito DESPUÉS de emitirla.
--
-- Permite cambiar:
--   - Items (agregar, quitar, modificar cantidad/precio/descuento)
--   - Notas
--   - Cliente asignado
--
-- NO cambia:
--   - sale_number, sale_date, cashier_id (auditoría)
--   - NCF (fiscalidad — si necesita corregir un NCF, usar nota de crédito)
--   - receipt_type, status, due_date
--
-- Stock: se restaura la cantidad vieja en todos los items y se aplica la
-- nueva. Todo dentro de una transacción para que no quede inconsistente.
--
-- Recálculo: subtotal, tax_amount, total_amount, balance_due se vuelven a
-- computar desde los nuevos items. paid_amount se preserva tal cual; si el
-- nuevo total < paid se considera un sobre-pago (balance_due = 0).
--
-- Si la venta es a crédito, se ajusta `clients.balance_due` por la
-- diferencia (nuevo total − viejo total).
--
-- Solo admin / supervisor pueden ejecutarla — los cajeros no.
--
-- Idempotente. Reemplaza la función si ya existe.

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
  v_balance_due numeric(14,2);
  v_note text;
  v_target_client uuid;
  v_item_count integer := 0;
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

  -- Bloqueo de la fila para evitar ediciones concurrentes.
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

  -- Resolver cliente final.
  if p_clear_client then
    v_target_client := null;
  elsif p_client_id is not null then
    v_target_client := p_client_id;
  else
    v_target_client := v_old_client_id;
  end if;

  -- Validar cliente nuevo si cambió.
  if v_target_client is not null and v_target_client is distinct from v_old_client_id then
    if not exists (
      select 1 from public.clients
      where id = v_target_client and branch_id = v_branch_id and is_active
    ) then
      raise exception 'Cliente nuevo no válido para esta sucursal.'
        using errcode = '23503';
    end if;
  end if;

  -- Resolver notas.
  if p_clear_notes then
    v_note := null;
  elsif p_notes is not null then
    v_note := nullif(trim(p_notes), '');
  else
    v_note := v_sale.notes;
  end if;

  -- 1) Restaurar stock de los items viejos.
  --    Solo productos físicos (track_inventory true e is_service false).
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
  create temp table if not exists tmp_edit_items (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    discount_amount numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2)
  ) on commit drop;
  truncate tmp_edit_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      coalesce((item->>'discount_pct')::numeric, 0)::numeric(5,2) as discount_pct
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
           p.is_tax_exempt, p.track_inventory
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

    -- Validación de stock (stock ya restaurado, así que comparamos contra
    -- el stock actualizado).
    if (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and coalesce(v_product.track_inventory, true)
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

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
    begin
      v_sub := round((v_gross - v_disc)::numeric, 2);
      v_tax := round((v_sub * v_rate / 100)::numeric, 2);

      insert into tmp_edit_items (
        product_id,
        description,
        quantity,
        unit_price,
        discount_amount,
        tax_rate,
        line_subtotal,
        line_tax,
        line_total
      ) values (
        v_item.product_id,
        coalesce(nullif(v_item.description, ''), v_product.name),
        v_item.quantity,
        v_item.unit_price,
        v_disc,
        v_rate,
        v_sub,
        v_tax,
        round((v_sub + v_tax)::numeric, 2)
      );
    end;

    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No se procesó ningún item válido.'
      using errcode = '22023';
  end if;

  -- 4) Aplicar el nuevo stock (deducir cantidad nueva).
  update public.products p
  set stock = round(
    (coalesce(p.stock, 0) - tei.quantity)::numeric(14, 3),
    3
  )
  from tmp_edit_items tei
  where p.id = tei.product_id
    and p.branch_id = v_branch_id
    and coalesce(p.is_service, false) = false
    and coalesce(p.track_inventory, true) = true;

  -- 5) Insertar los nuevos items.
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
    p_sale_id,
    v_branch_id,
    product_id,
    description,
    quantity,
    unit_price,
    discount_amount,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total
  from tmp_edit_items
  order by product_id;

  -- 6) Recalcular totales desde tmp_edit_items.
  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_edit_items;

  -- 7) balance_due = nuevo total − pagado (no negativo).
  v_balance_due := greatest(
    round((v_total_amount - coalesce(v_sale.paid_amount, 0))::numeric, 2),
    0
  );

  -- 8) Actualizar la fila sales (sin tocar sale_number, sale_date, NCF,
  --    cashier_id, receipt_type, status, due_date).
  update public.sales
  set
    subtotal = v_subtotal,
    tax_amount = v_tax_amount,
    total_amount = v_total_amount,
    balance_due = v_balance_due,
    client_id = v_target_client,
    notes = v_note,
    updated_at = timezone('utc', now())
  where id = p_sale_id;

  -- 9) Ajustar clients.balance_due por la diferencia.
  --    Caso A: cliente cambia → restar todo el viejo total al cliente
  --    anterior, sumar nuevo total al nuevo cliente (si la venta es de
  --    crédito o tiene balance pendiente).
  --    Caso B: mismo cliente → ajustar por diferencia.
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
    'paid_amount', coalesce(v_sale.paid_amount, 0),
    'balance_due', v_balance_due,
    'items_count', v_item_count,
    'client_id', v_target_client,
    'old_total', v_old_total
  );
end;
$$;

grant execute on function public.edit_sale_transactional(
  uuid, jsonb, uuid, boolean, text, boolean
) to authenticated;

commit;
