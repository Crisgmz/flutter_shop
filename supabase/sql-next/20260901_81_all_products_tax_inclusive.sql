-- ============================================================================
-- Migración 81 — Catálogo con ITBIS INCLUIDO para UN solo negocio
-- ============================================================================
-- Empresa afectada: ae7e0f64-34cf-43f4-9fc7-e879fbe51aee
-- Ningún otro negocio de esta base se toca. El id está fijo en `v_id` abajo;
-- si algún día hay que correrla para otro negocio, se cambia ESE valor.
--
-- La migración 66 (`20260717_66_tax_inclusive_pricing.sql`) ya dejó lista la
-- columna `products.price_includes_tax` y toda la matemática de los RPC de
-- venta. Esta migración NO agrega estructura: solo cambia el DATO del negocio.
--
-- Qué hace:
--   1) `products.price_includes_tax = true` en todos los productos de ese
--      negocio, en todas sus sucursales.
--   2) `app_settings.tax_default_price_includes_tax = true` en la fila de ESE
--      negocio (`app_settings.company_id`), para que los artículos nuevos
--      nazcan igual.
--
-- Lo que NO hace: NO toca `products.price`. El precio se queda con el mismo
-- número y ese número pasa a ser el precio final que paga el cliente.
--
--   ANTES (ITBIS aparte)        DESPUÉS (ITBIS incluido)
--   precio      200.00          precio      200.00
--   + ITBIS 18%  36.00          base        169.49
--   = cobra     236.00          ITBIS 18%    30.51
--                               = cobra     200.00
--
-- Los productos con `tax_rate = 0` (exentos) no cambian en nada: sin tasa no
-- hay impuesto que extraer ni que sumar.
--
-- Ventas ya emitidas: intactas. `sale_items` guarda subtotal/tax/total ya
-- calculados; esto solo afecta las ventas FUTURAS.
--
-- Reversible: para volver atrás, el mismo UPDATE con `false`.
-- Idempotente: correrla dos veces no cambia nada la segunda vez.
--
-- ⚠️ PENDIENTE ANTES DE CORRERLA — COTIZACIONES
-- El módulo de cotizaciones NO respeta `price_includes_tax`: siempre calcula
-- `line_tax = line_subtotal × tasa/100` y `line_total = subtotal + tax`
-- (`lib/features/quotations/data/quotations_models.dart`, QuoteDraftLine y
-- QuoteCreateItem). Hoy eso afecta solo a los artículos ya marcados como
-- incluido; después de esta migración afecta a TODOS los de tasa 18%. Como
-- `convert_quote_paid` copia `line_subtotal/line_tax/line_total` tal cual a la
-- venta, una cotización convertida cobraría un 18% por encima de lo que cobra
-- el POS por el mismo carrito. Corregir el módulo de cotizaciones antes de
-- correr esto, o no emitir cotizaciones hasta corregirlo.
--
-- Ejecutar en el SQL Editor de Supabase, después de la 80.
-- ============================================================================


-- ── PASO 0 (opcional, solo lectura): confirmar el negocio y el impacto ──────
-- Córrelo aparte ANTES de la migración. Debe devolver el nombre de tu negocio
-- y cuántos artículos cambian.
--
--   select c.name                                   as negocio,
--          count(distinct b.id)                     as sucursales,
--          count(p.id)                              as productos,
--          count(p.id) filter (where p.tax_rate > 0
--                              and not p.price_includes_tax) as cambian_de_verdad,
--          count(p.id) filter (where p.tax_rate = 0)         as tasa_cero_sin_efecto,
--          count(p.id) filter (where p.price_includes_tax)   as ya_incluido
--     from public.companies c
--     join public.branches b on b.company_id = c.id
--     left join public.products p on p.branch_id = b.id
--    where c.id = 'ae7e0f64-34cf-43f4-9fc7-e879fbe51aee'
--    group by c.name;


begin;

do $$
declare
  -- Negocio a migrar. Acepta el id de la empresa o el de una de sus sucursales.
  v_id           uuid := 'ae7e0f64-34cf-43f4-9fc7-e879fbe51aee';

  v_company_id   uuid;
  v_company_name text;
  v_branches     int;
  v_products     int;
  v_settings     int;
begin
  -- ¿El id es una empresa?
  select c.id, c.name into v_company_id, v_company_name
    from public.companies c
   where c.id = v_id;

  -- Si no, ¿es una sucursal? Entonces se usa la empresa dueña de esa sucursal,
  -- porque el cambio va a todas las sucursales del negocio.
  if v_company_id is null then
    select b.company_id into v_company_id
      from public.branches b
     where b.id = v_id;

    if v_company_id is not null then
      select c.name into v_company_name
        from public.companies c
       where c.id = v_company_id;
      raise notice
        'El id % es una SUCURSAL. Se migra su empresa completa: % (%).',
        v_id, v_company_name, v_company_id;
    end if;
  end if;

  if v_company_id is null then
    raise exception
      'El id % no existe en public.companies ni en public.branches. '
      'Nada fue modificado.', v_id;
  end if;

  select count(*) into v_branches
    from public.branches
   where company_id = v_company_id;

  -- 1) Catálogo del negocio: precio con ITBIS adentro.
  update public.products p
     set price_includes_tax = true
   where p.price_includes_tax is distinct from true
     and p.branch_id in (
       select b.id from public.branches b where b.company_id = v_company_id
     );
  get diagnostics v_products = row_count;

  -- 2) Default para artículos nuevos, SOLO en la fila de este negocio.
  --    (`app_settings` es por empresa: el repo de la app filtra por
  --    `company_id = current_company_id()`.) Nunca se toca la fila legacy
  --    `id = 1` con `company_id null`: en esta base compartida podría ser de
  --    otro negocio.
  update public.app_settings
     set tax_default_price_includes_tax = true
   where company_id = v_company_id
     and tax_default_price_includes_tax is distinct from true;
  get diagnostics v_settings = row_count;

  if not exists (
    select 1 from public.app_settings where company_id = v_company_id
  ) then
    raise warning
      'La empresa % no tiene fila en app_settings. El catálogo quedó migrado, '
      'pero el default de artículos NUEVOS no se pudo activar: hazlo desde '
      'Ajustes → Impuestos y Moneda.', v_company_id;
  end if;

  raise notice
    'Negocio "%" (%): % sucursal(es), % producto(s) pasados a ITBIS incluido, '
    '% fila(s) de ajustes actualizada(s).',
    v_company_name, v_company_id, v_branches, v_products, v_settings;
end;
$$;

commit;

-- ── Verificación ────────────────────────────────────────────────────────────
-- Todo el catálogo del negocio debe quedar en price_includes_tax = true:
--
--   select p.price_includes_tax,
--          count(*) filter (where p.tax_rate > 0) as con_itbis,
--          count(*) filter (where p.tax_rate = 0) as sin_itbis,
--          count(*)                               as total
--     from public.products p
--     join public.branches b on b.id = p.branch_id
--    where b.company_id = 'ae7e0f64-34cf-43f4-9fc7-e879fbe51aee'
--    group by 1;
--
-- Y el default de artículos nuevos:
--
--   select tax_default_price_includes_tax
--     from public.app_settings
--    where company_id = 'ae7e0f64-34cf-43f4-9fc7-e879fbe51aee';
