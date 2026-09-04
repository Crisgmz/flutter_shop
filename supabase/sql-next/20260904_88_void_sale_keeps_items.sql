-- ============================================================================
-- Migración 88 — Anular una venta: conserva el detalle y exige permiso
-- ============================================================================
-- Dos reportes del mismo día (2026-09-04), y los dos viven en
-- `void_sale_with_stock_return`:
--
--   1) "La factura anulada no muestra los artículos que se anularon."
--   2) "El usuario anula aunque no tenga permiso para anular."
--
-- ── PROBLEMA 1: el detalle se destruye ──────────────────────────────────────
-- El RPC devolvía el stock de la forma más corta posible:
--
--     delete from public.sale_items where sale_id = p_sale_id;
--
-- ...apoyándose en que el trigger `trg_sale_items_stock` suma de vuelta en
-- cada DELETE. Funciona para el inventario, pero BORRA LA FACTURA: la venta
-- queda con cabecera y sin líneas. Reimprimirla no muestra nada, el detalle
-- sale vacío, y el bloque "Devoluciones" del dashboard (que ya agrupa
-- `voided_items`) siempre da cero porque no queda una sola fila que agrupar.
-- Para un comprobante fiscal anulado eso además es un problema de auditoría:
-- se pierde la evidencia de QUÉ se anuló.
--
-- Ahora el stock se devuelve con un `update` explícito — los mismos guards de
-- `is_service` / `track_inventory` que ya usa `edit_sale_transactional` en su
-- paso 1 — y las líneas SE QUEDAN. La venta anulada conserva su detalle.
--
-- Verificado antes de cambiarlo: TODAS las vistas y funciones de reporte que
-- leen `sale_items` filtran con `s.status = 'completed'` (filtro positivo, no
-- `<> voided`), así que conservar las líneas de una venta `voided` no suma ni
-- un peso a ningún reporte:
--   · mv_sales_by_item, mv_sales_by_category
--   · sales_by_item_view, sales_by_category_view
--   · report_tax_breakdown_view, report_employees_view, report_discounts_view
--   · report_pl / report_commission / dashboard_v2 / closeout (subqueries
--     correlacionadas contra un CTE ya filtrado por 'completed')
--
-- Los `payments` SÍ se siguen borrando, y es a propósito: el dinero de una
-- venta anulada se devolvió, y dejar sus pagos vivos le sumaría al esperado
-- del cierre de caja un efectivo que ya no está en la gaveta.
--
-- EFECTO COLATERAL QUE HAY QUE TAPAR: hasta hoy, buscar una venta anulada
-- para DEVOLVERLA fallaba sola ("la venta no tiene items recuperables"),
-- porque no había líneas que cargar. Al conservarlas, esa puerta se abre: se
-- podría devolver una venta ya anulada y regresar el stock y el dinero DOS
-- veces. Por eso `process_return` pasa a rechazarlo explícitamente (punto 3).
--
-- ── PROBLEMA 2: cualquiera podía anular ─────────────────────────────────────
-- El RPC solo comprobaba `has_branch_access(branch_id)` — o sea, el rol NO se
-- miraba. Y al ser `security definer` se salta la RLS, así que cualquier
-- usuario autenticado de la sucursal podía anular la venta que quisiera. En
-- la pantalla tampoco había gate: el botón de anular se le mostraba a todo el
-- mundo. Compárese con `edit_sale_transactional`, que desde siempre exige
-- admin o supervisor.
--
-- Ahora se exige permiso con la MISMA semántica que usa el cliente
-- (`RoleAccess.hasPermission`): el override explícito del usuario sobre
-- `sales.void` manda en los dos sentidos, y si no hay override decide el rol
-- (admin o supervisor). El admin siempre puede — es el dueño.
--
-- Nótese que el permiso `sales.void` ("Anular Ventas") YA existía en el
-- catálogo desde la migración estructural; nadie lo estaba consultando. Aquí
-- además se le asigna a `supervisor` en `role_permissions` para que la
-- pantalla de permisos muestre el mismo default que aplica el código.
--
-- Idempotente.
-- ============================================================================

begin;

-- ── 1) El default por rol de `sales.void`, visible en la pantalla ───────────
-- Sin esto la pantalla de empleados mostraría el switch de "Anular Ventas"
-- apagado para un supervisor que sí puede anular. `do nothing`: si un admin
-- ya lo revocó a mano, correr esto otra vez no debe re-otorgarlo.
insert into public.role_permissions (role_key, permission_id, allowed)
select 'supervisor', p.id, true
from public.permissions p
where p.code = 'sales.void'
on conflict (role_key, permission_id) do nothing;

-- ── 2) void_sale_with_stock_return ─────────────────────────────────────────
-- Copia fiel de la versión vigente en 20260814_70_imei_restore_on_void_and_edit
-- con dos cambios: el chequeo de permiso (nuevo paso -1) y la devolución de
-- stock sin borrar las líneas (paso 1). La restauración de IMEIs del paso 0 y
-- el borrado de pagos quedan igual. La firma no cambia.
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
  v_override boolean;
  v_can_void boolean;
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

  -- -1) Permiso para anular. Misma resolución que `RoleAccess.hasPermission`
  --     en el cliente: primero el override explícito del usuario sobre
  --     `sales.void` (el de la sucursal gana sobre el global), y si no hay
  --     override decide el rol. Se resuelve a mano en vez de con
  --     `has_permission()` porque esa función no distingue "sin override y
  --     sin grant de rol" de "override en false", y aquí esa diferencia es la
  --     que permite quitarle el permiso a un supervisor.
  select up.granted
    into v_override
    from public.user_permissions up
    join public.permissions p on p.id = up.permission_id
   where up.user_id = auth.uid()
     and up.is_active
     and p.code = 'sales.void'
     and (up.branch_id is null or up.branch_id = v_branch_id)
   order by case when up.branch_id = v_branch_id then 0 else 1 end,
            up.created_at desc
   limit 1;

  v_can_void := public.is_admin() or coalesce(
    v_override,
    public.current_user_role() = 'supervisor'::public.app_role
  );

  if not v_can_void then
    raise exception 'No tienes permiso para anular ventas.'
      using errcode = '42501';
  end if;

  if v_status = 'voided'::public.sale_status then
    raise exception 'La venta ya está anulada.'
      using errcode = '23505';
  end if;

  -- 0) Devolver los IMEIs al inventario para que los equipos se puedan volver
  --    a vender. La copia en `sale_items.imeis` se queda como rastro de qué
  --    traía la factura anulada; buscar una venta por IMEI toma la línea más
  --    reciente, así que una reventa posterior sigue ganando.
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

  -- 1) Devolver el stock SIN borrar las líneas. Antes esto era un
  --    `delete from public.sale_items` que dejaba que el trigger
  --    `trg_sale_items_stock` hiciera la suma — y de paso borraba la factura.
  --    Los guards de servicio / sin control de inventario son los mismos que
  --    aplica el trigger, para que el resultado en `products.stock` sea
  --    idéntico al de antes.
  update public.products p
  set stock = round(
    (coalesce(p.stock, 0) + si.quantity)::numeric(14, 3),
    3
  )
  from public.sale_items si
  where si.sale_id = p_sale_id
    and p.id = si.product_id
    and p.branch_id = si.branch_id
    and coalesce(p.is_service, false) = false
    and coalesce(p.track_inventory, true) = true;

  -- 2) Borrar pagos vinculados: el dinero se devolvió, y dejarlos vivos le
  --    sumaría al esperado del cierre un efectivo que ya no está en la caja.
  delete from public.payments
  where sale_id = p_sale_id;

  -- 3) Marcar la venta como anulada. Las líneas se quedan: es lo que hace que
  --    la factura anulada siga mostrando qué se anuló.
  update public.sales
    set status = 'voided'::public.sale_status,
        updated_at = timezone('utc', now())
  where id = p_sale_id;
end;
$$;

grant execute on function public.void_sale_with_stock_return(uuid)
  to authenticated;

-- ── 3) process_return — no se devuelve una venta ya anulada ────────────────
-- Copia fiel de la versión vigente en 20260814_69_returns_cash_and_imeis.sql
-- con un solo cambio: el bloque que valida `p_original_sale_id` ahora
-- rechaza las ventas anuladas. Es el guard que reemplaza a la protección
-- accidental que daba el borrado de líneas (ver la cabecera de esta
-- migración). Todo lo demás — sesión de caja, reembolso, IMEIs, correlativo
-- de `return_number`, ajuste de `clients.balance_due` — queda intacto.

create or replace function public.process_return(
  p_branch_id uuid default null,
  p_client_id uuid default null,
  p_original_sale_id uuid default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb,
  p_cash_session_id uuid default null,
  p_refund_method text default 'cash'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_user uuid;
  v_return_id uuid;
  v_return_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_items_count integer := 0;
  v_item jsonb;
  v_qty numeric(14,3);
  v_price numeric(14,2);
  v_tax_rate numeric(5,2);
  v_gross numeric(14,2);
  v_line_subtotal numeric(14,2);
  v_line_tax numeric(14,2);
  v_line_total numeric(14,2);
  v_product_id uuid;
  v_product_name text;
  v_price_includes_tax boolean;
  v_line_imeis text[];
  v_bad_imeis text[];
  v_was_credit_sale boolean := false;
  v_original_voided boolean := false;
  v_prefix text;
  v_seq bigint;
  v_cash_session_id uuid;
  v_refund_method text;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_user := auth.uid();

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada al usuario';
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Una devolución requiere al menos un artículo';
  end if;

  v_refund_method := coalesce(nullif(trim(coalesce(p_refund_method, '')), ''), 'cash');

  -- Resolver la sesión de caja (mismo bloque que checkout_sale_transactional).
  -- A diferencia del checkout, aquí NO se exige caja abierta: una devolución
  -- puede registrarse fuera de caja y queda con cash_session_id null.
  if p_cash_session_id is not null then
    select cs.id into v_cash_session_id
      from public.cash_sessions cs
     where cs.id = p_cash_session_id
       and cs.branch_id = v_branch_id
       and cs.status = 'open'
       and (
         cs.opened_by = v_user
         or cs.cash_register_id is null
         or exists (
           select 1 from public.cash_register_users cru
           where cru.cash_register_id = cs.cash_register_id
             and cru.user_id = v_user
             and cru.is_active
         )
       );

    if v_cash_session_id is null then
      raise exception 'La caja seleccionada no está abierta o no tienes acceso a ella.'
        using errcode = '22023';
    end if;
  else
    select cs.id into v_cash_session_id
      from public.cash_sessions cs
     where cs.branch_id = v_branch_id
       and cs.status = 'open'
       and (
         cs.opened_by = v_user
         or exists (
           select 1 from public.cash_register_users cru
           where cru.cash_register_id = cs.cash_register_id
             and cru.user_id = v_user
             and cru.is_active
         )
       )
     order by cs.opened_at desc
     limit 1;
  end if;

  -- Si hay venta original: validar que pertenece a la sucursal y guardar
  -- si fue a crédito (para ajustar balance_due).
  if p_original_sale_id is not null then
    select status = 'credit'::public.sale_status,
           status = 'voided'::public.sale_status
      into v_was_credit_sale, v_original_voided
      from public.sales
     where id = p_original_sale_id
       and branch_id = v_branch_id;
    if not found then
      raise exception 'La venta original no existe en esta sucursal';
    end if;
    -- Una venta anulada ya devolvió su stock y su dinero. Devolverla otra vez
    -- lo haría por partida doble. Hasta la migración 88 esto no podía pasar
    -- por accidente: anular BORRABA las líneas, así que el POS no encontraba
    -- nada que cargar. Ahora que la factura anulada conserva su detalle, el
    -- rechazo tiene que ser explícito.
    if v_original_voided then
      raise exception 'La venta % está anulada: su stock y su dinero ya se '
                      'devolvieron al anularla.', p_original_sale_id
        using errcode = '22023';
    end if;
  end if;

  -- Insertar la cabecera con totales en 0; los recalculamos al final.
  insert into public.returns (
    branch_id, client_id, original_sale_id, cashier_id, notes,
    subtotal, tax_amount, total_amount, cash_session_id, refund_method
  ) values (
    v_branch_id, p_client_id, p_original_sale_id, v_user, p_notes,
    0, 0, 0, v_cash_session_id, v_refund_method
  ) returning id into v_return_id;

  -- Asignar return_number con prefijo de app_settings + correlativo por sucursal.
  -- El prefijo se resuelve por COMPAÑÍA de la sucursal: `where id = 1` tomaba
  -- la fila de otra empresa en instalaciones multi-empresa.
  select coalesce(s.prefix_credit_note, 'NC') into v_prefix
    from public.app_settings s
    join public.branches b on b.company_id = s.company_id
   where b.id = v_branch_id
   limit 1;
  v_prefix := coalesce(v_prefix, 'NC');

  select coalesce(count(*), 0) + 1 into v_seq
    from public.returns
   where branch_id = v_branch_id
     and id <> v_return_id;

  v_return_number := v_prefix || '-' || lpad(v_seq::text, 5, '0');
  update public.returns set return_number = v_return_number where id = v_return_id;

  -- Insertar líneas
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric(14,3);
    v_price := (v_item->>'unit_price')::numeric(14,2);
    v_tax_rate := coalesce((v_item->>'tax_rate')::numeric(5,2), 18.00);

    if v_qty is null or v_qty <= 0 then
      raise exception 'La cantidad de cada línea debe ser mayor que cero';
    end if;
    if v_price is null or v_price < 0 then
      raise exception 'El precio unitario es inválido';
    end if;

    -- IMEIs devueltos en esta línea (opcional). Se normalizan aquí mismo:
    -- trim, se descartan vacíos y se deduplican, para que el conteo con el
    -- que se valida abajo sea el mismo que se guarda y se restaura.
    select coalesce(array_agg(distinct t.v order by t.v), '{}'::text[])
      into v_line_imeis
      from jsonb_array_elements_text(
             case when jsonb_typeof(v_item->'imeis') = 'array'
                  then v_item->'imeis' else '[]'::jsonb end) as u(raw)
      cross join lateral (select nullif(trim(u.raw), '') as v) t
     where t.v is not null;

    select name, coalesce(price_includes_tax, false)
      into v_product_name, v_price_includes_tax
      from public.products
     where id = v_product_id
       and branch_id = v_branch_id;
    if not found then
      raise exception 'Producto no encontrado en la sucursal';
    end if;

    -- Defensa contra devoluciones PARCIALES mal armadas: si la línea trae más
    -- IMEIs que unidades devueltas, restaurarlos todos dejaría equipos vendidos
    -- otra vez disponibles en el inventario. El RPC no confía en el cliente.
    if coalesce(array_length(v_line_imeis, 1), 0) > v_qty then
      raise exception
        'La línea de "%" trae % IMEI(s) para una cantidad devuelta de %. No se pueden devolver más equipos que unidades.',
        v_product_name, coalesce(array_length(v_line_imeis, 1), 0), v_qty
        using errcode = '22023';
    end if;

    -- Si la devolución está ligada a una venta, cada IMEI tiene que haber
    -- salido de ESA venta. Así no se cuela al inventario un equipo de otra
    -- factura (o inventado) por la vía de la devolución.
    if p_original_sale_id is not null
       and coalesce(array_length(v_line_imeis, 1), 0) > 0 then
      select array_agg(u.imei order by u.imei)
        into v_bad_imeis
        from unnest(v_line_imeis) as u(imei)
       where not exists (
         select 1
           from public.sale_items si
          where si.sale_id = p_original_sale_id
            and si.branch_id = v_branch_id
            and si.imeis @> array[u.imei]
       );

      if coalesce(array_length(v_bad_imeis, 1), 0) > 0 then
        raise exception
          'Los IMEI % no pertenecen a la venta original.',
          array_to_string(v_bad_imeis, ', ')
          using errcode = '22023';
      end if;
    end if;

    v_gross := round(v_qty * v_price, 2);
    if v_price_includes_tax and v_tax_rate > 0 then
      -- Precio con ITBIS incluido: se reembolsa el total exacto y el
      -- impuesto se extrae.
      v_line_total := v_gross;
      v_line_tax := round((v_gross * v_tax_rate / (100 + v_tax_rate))::numeric, 2);
      v_line_subtotal := v_line_total - v_line_tax;
    else
      -- Exclusivo (comportamiento histórico, mismos redondeos).
      v_line_subtotal := v_gross;
      v_line_tax := round(v_line_subtotal * v_tax_rate / 100.0, 2);
      v_line_total := v_line_subtotal + v_line_tax;
    end if;

    insert into public.return_items (
      return_id, branch_id, product_id, description, quantity,
      unit_price, tax_rate, line_subtotal, line_tax, line_total, imeis
    ) values (
      v_return_id, v_branch_id, v_product_id, v_product_name, v_qty,
      v_price, v_tax_rate, v_line_subtotal, v_line_tax, v_line_total,
      v_line_imeis
    );

    -- El equipo vuelve a estar disponible en el inventario.
    if coalesce(array_length(v_line_imeis, 1), 0) > 0 then
      perform public.restore_product_imeis(v_product_id, v_branch_id, v_line_imeis);
    end if;

    v_subtotal := v_subtotal + v_line_subtotal;
    v_tax := v_tax + v_line_tax;
    v_total := v_total + v_line_total;
    v_items_count := v_items_count + 1;
  end loop;

  update public.returns
     set subtotal = v_subtotal,
         tax_amount = v_tax,
         total_amount = v_total
   where id = v_return_id;

  -- Si la venta original fue a crédito y hay cliente, ajustar saldo.
  if v_was_credit_sale and p_client_id is not null then
    update public.clients
       set balance_due = greatest(0, balance_due - v_total)
     where id = p_client_id
       and branch_id = v_branch_id;
  end if;

  -- Recordatorio: NO se inserta en public.cash_register_movements. El cierre
  -- de caja resta los reembolsos leyendo `returns` directamente; un movimiento
  -- aquí haría que se descuenten dos veces.

  return jsonb_build_object(
    'return_id', v_return_id,
    'return_number', v_return_number,
    'total_amount', v_total,
    'items_count', v_items_count,
    'cash_session_id', v_cash_session_id,
    'refund_method', v_refund_method,
    'credit_balance_adjusted', v_was_credit_sale and p_client_id is not null
  );
end;
$$;

grant execute on function public.process_return(
  uuid, uuid, uuid, text, jsonb, uuid, text
) to authenticated;

commit;

notify pgrst, 'reload schema';
