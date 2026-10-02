-- ============================================================================
-- Migración 97 — Editar ventas obedece a "No permitir venta sin stock"
-- ============================================================================
-- DECISIÓN (2 oct 2026): nada de interruptor aparte. El mismo botón de
-- Configuración → Inventario → "No permitir venta de artículos sin stock"
-- (`app_settings.inv_disallow_no_stock`, por negocio) decide las dos cosas:
--   · APAGADO  → se vende y se EDITA aunque no haya stock (queda en negativo).
--   · PRENDIDO → el POS no vende sin stock y el editor tampoco lo permite.
-- Es la misma regla que trae la 97 de shop-plus para su versión de la función.
--
-- Reemplaza a la 96 (su interruptor `inv_edit_sale_ignores_stock` deja de
-- usarse; la columna se queda, sin efecto). Igual que la 96, NO copia la
-- función: lee la definición REAL con `pg_get_functiondef` y cambia solo la
-- condición del aviso 'Stock insuficiente para ...'. Tres casos:
--
--   1) La función tiene el parche de la 96 → su condición pasa de mirar
--      `inv_edit_sale_ignores_stock` a mirar `inv_disallow_no_stock`.
--   2) Ya lee `inv_disallow_no_stock` (97/99 de shop-plus, o esta migración
--      ya corrió) → no hace nada.
--   3) Ninguna de las dos (91/92 de shop-plus recién recreada) → envuelve el
--      único `raise exception 'Stock insuficiente para ...';` en
--      `if <No permitir venta sin stock del negocio> then ... end if;`.
-- Si algo no aparece exactamente una vez, aborta sin cambiar nada.
--
-- NO AFECTA LAS MIGRACIONES DE SHOP-PLUS: misma firma (su `create or replace`
-- entra igual), no cambia lo que sus diagnósticos (04, 07, 13) y su parche 85
-- buscan en el texto de la función, y no crea ni borra nada suyo.
--
-- ⚠️ Con el botón PRENDIDO y la versión 91/92 viva, el editor exige stock
--    contra la cantidad total: una venta con un producto que YA está en
--    negativo no se guarda aunque no se le suba nada. La regla fina (solo
--    bloquear si se sube la cantidad) llega con la 97 de shop-plus.
-- ⚠️ Si shop-plus vuelve a crear la función con una versión que no lee el
--    botón, volver a correr esta migración.
--
-- Idempotente.
-- ============================================================================

begin;

do $$
declare
  v_fn regprocedure := to_regprocedure(
    'public.edit_sale_transactional(uuid, jsonb, uuid, boolean, text, boolean, boolean)'
  );
  -- Encabezado exacto que dejó la 96 alrededor del aviso.
  v_old_head constant text := $h$if not coalesce((
        select s.inv_edit_sale_ignores_stock
          from public.app_settings s
          join public.branches b on b.company_id = s.company_id
         where b.id = v_branch_id
         limit 1), false) then$h$;
  -- Sin fila de configuración se exige stock, igual que la 97 de shop-plus.
  v_new_head constant text := $h$if coalesce((
        select s.inv_disallow_no_stock
          from public.app_settings s
          join public.branches b on b.company_id = s.company_id
         where b.id = v_branch_id
         limit 1), true) then$h$;
  -- La sentencia raise completa: no lleva ';' por dentro, termina en el suyo.
  v_raise constant text := 'raise exception ''Stock insuficiente para[^;]*;';
  v_def text;
  v_hits integer;
begin
  if v_fn is null then
    raise exception
      'No existe edit_sale_transactional de 7 parámetros (shop-plus). No se cambia nada.';
  end if;

  v_def := pg_get_functiondef(v_fn);

  -- 1) Parche de la 96 → mirar el botón de siempre.
  if position('inv_edit_sale_ignores_stock' in v_def) > 0 then
    v_hits := (length(v_def) - length(replace(v_def, v_old_head, '')))
              / length(v_old_head);
    if v_hits <> 1 then
      raise exception
        'La función tiene el interruptor de la 96 pero no con el texto esperado (% coincidencias). No se cambia nada.',
        v_hits;
    end if;
    execute replace(v_def, v_old_head, v_new_head);
    raise notice 'edit_sale_transactional: la condición de la 96 ahora mira "No permitir venta sin stock".';
    return;
  end if;

  -- 2) Ya obedece al botón.
  if position('inv_disallow_no_stock' in v_def) > 0 then
    raise notice 'edit_sale_transactional ya lee inv_disallow_no_stock: nada que hacer.';
    return;
  end if;

  -- 3) Sin ningún parche → envolver el aviso de stock.
  select count(*) into v_hits from regexp_matches(v_def, v_raise, 'g');
  if v_hits <> 1 then
    raise exception
      'La edit_sale_transactional viva no es la esperada (% avisos de "Stock insuficiente", se esperaba 1). No se cambia nada.',
      v_hits;
  end if;
  if position('v_branch_id' in v_def) = 0 then
    raise exception
      'La edit_sale_transactional viva no tiene v_branch_id. No se cambia nada.';
  end if;

  -- `\&` es la sentencia raise encontrada, tal cual.
  execute regexp_replace(v_def, v_raise, v_new_head || $g$
      \&
      end if;$g$);
  raise notice 'edit_sale_transactional: el aviso de stock ahora obedece a "No permitir venta sin stock".';
end $$;

commit;

notify pgrst, 'reload schema';

-- Verificación (debe devolver true):
--   select position('inv_disallow_no_stock' in pg_get_functiondef(
--     'public.edit_sale_transactional(uuid, jsonb, uuid, boolean, text, boolean, boolean)'::regprocedure
--   )) > 0 as editor_obedece_el_boton;
--
-- Negocios que hoy NO dejan vender ni editar sin stock (botón prendido):
--   select c.name
--     from public.app_settings s
--     join public.companies c on c.id = s.company_id
--    where s.inv_disallow_no_stock;
