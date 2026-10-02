-- ============================================================================
-- Migración 96 — "Permitir editar ventas aunque no haya stock" (por negocio)
-- ============================================================================
-- PEDIDO (1-2 oct 2026): que una venta ya facturada se pueda editar aunque el
-- producto no tenga existencias.
--
-- La `edit_sale_transactional` viva es la de shop-plus (7 parámetros; misma
-- base). Según la versión, bloquea con 'Stock insuficiente para ...':
--   · 91/92 de shop-plus (15-16 sept): SIEMPRE, contra la cantidad total e
--     ignorando "No permitir venta sin stock". Una venta con un producto en
--     cero o negativo no se puede guardar ni para cambiarle el cliente.
--   · 97/99 de shop-plus: solo si la edición pide MÁS y el interruptor de
--     "No permitir venta sin stock" está prendido.
--
-- ARREGLO: un interruptor aparte, por negocio y apagado por defecto:
--   app_settings.inv_edit_sale_ignores_stock
-- Prendido, el editor no exige existencias (el stock se descuenta igual y
-- queda en negativo si no alcanzaba). El POS sigue con su propia regla. Los
-- negocios que no lo prendan —incluidos todos los de shop-plus— no cambian.
--
-- CÓMO SE TOCA LA FUNCIÓN: no se copia entera (no se sabe cuál de las
-- versiones está viva, y copiar otra pisaría la de shop-plus). Se lee la
-- definición REAL con `pg_get_functiondef` y se envuelve el único
--   raise exception 'Stock insuficiente para ...';
-- en
--   if not <interruptor del negocio de la venta> then raise ...; end if;
-- Ese raise existe una sola vez en todas las versiones (87 de flutter_shop+;
-- 83, 91, 92, 97 y 99 de shop-plus), así que sirve con cualquiera. Si no
-- aparece exactamente una vez, aborta sin cambiar nada. Firma, permisos,
-- `security definer` y todo lo demás quedan como estaban.
--
-- NO AFECTA LAS MIGRACIONES DE SHOP-PLUS:
--   · No cambia la firma ni el nombre: su `create or replace` (97, 99 o la
--     que venga) sigue entrando igual, sin choques ni sobrecargas.
--   · No quita ni agrega nada de lo que sus diagnósticos (04, 07, 13) y su
--     parche 85 buscan en el texto de la función (`::text = 'none'`,
--     `price_includes_tax`, `restore_product_imeis`, `has_branch_access`,
--     `is_admin`): siguen dando el mismo resultado.
--   · La columna nueva es solo para app_settings y nada de shop-plus la lee.
--
-- ⚠️ Si shop-plus vuelve a crear `edit_sale_transactional` (p. ej. al correr
--    su 97 o su 99), la suya gana y este cambio se pierde: el interruptor
--    deja de tener efecto, no se rompe nada. Volver a correr esta migración
--    después.
--
-- Correr DESPUÉS de la 20261002_95. Idempotente: si la función ya lee el
-- interruptor, no hace nada.
-- ============================================================================

-- ⚠️ NO CORRER (2 oct 2026). Ya se corrió y la reemplazó la 20261002_97: el editor ahora obedece a "No permitir venta sin stock" y este interruptor aparte ya no se usa. Si shop-plus vuelve a crear la función, correr la 97.
-- Este bloque aborta el script antes de tocar nada.
do $$ begin raise exception 'NO CORRER (2 oct 2026). Ya se corrió y la reemplazó la 20261002_97: el editor ahora obedece a "No permitir venta sin stock" y este interruptor aparte ya no se usa. Si shop-plus vuelve a crear la función, correr la 97.'; end $$;

begin;

alter table public.app_settings
  add column if not exists inv_edit_sale_ignores_stock boolean not null default false;

do $$
declare
  v_fn regprocedure := to_regprocedure(
    'public.edit_sale_transactional(uuid, jsonb, uuid, boolean, text, boolean, boolean)'
  );
  -- La sentencia raise completa: no lleva ';' por dentro, termina en el suyo.
  v_raise constant text := 'raise exception ''Stock insuficiente para[^;]*;';
  -- `\&` es la sentencia raise encontrada, tal cual.
  v_guard constant text := $g$if not coalesce((
        select s.inv_edit_sale_ignores_stock
          from public.app_settings s
          join public.branches b on b.company_id = s.company_id
         where b.id = v_branch_id
         limit 1), false) then
      \&
      end if;$g$;
  v_def text;
  v_hits integer;
begin
  if v_fn is null then
    raise exception
      'No existe edit_sale_transactional de 7 parámetros (shop-plus). No se cambia nada.';
  end if;

  v_def := pg_get_functiondef(v_fn);

  if position('inv_edit_sale_ignores_stock' in v_def) > 0 then
    raise notice 'edit_sale_transactional ya lee inv_edit_sale_ignores_stock: nada que hacer.';
    return;
  end if;

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

  execute regexp_replace(v_def, v_raise, v_guard);
end $$;

commit;

notify pgrst, 'reload schema';

-- Verificación (debe devolver true):
--   select position('inv_edit_sale_ignores_stock' in pg_get_functiondef(
--     'public.edit_sale_transactional(uuid, jsonb, uuid, boolean, text, boolean, boolean)'::regprocedure
--   )) > 0 as editor_lee_interruptor;
--
-- Prender el interruptor para un negocio sin esperar al despliegue (cambiar
-- el nombre; también se puede desde Configuración → Inventario):
--   update public.app_settings
--      set inv_edit_sale_ignores_stock = true
--    where company_id in (
--      select id from public.companies where name ilike 'BEBEDIZO%'
--    );
