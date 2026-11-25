-- ============================================================================
-- Migración 109 — Factura A4 "Clásica" e ITBIS Norma 07-2007 por producto
-- ============================================================================
-- Pedido del dueño para GeotecnicaMQ (12 nov 2026), que factura servicios de
-- construcción.
--
-- ITBIS Norma 07-2007: el 18% se cobra sobre el 10% del monto del servicio,
-- o sea un 1.8% efectivo (44,400.00 → ITBIS 799.20, no 7,992.00). Cada
-- producto o servicio elige "regular" o "norma_07_2007".
--
-- Cómo se cobra sin tocar las RPC compartidas con shop-plus:
--   checkout/hold/edit_sale_transactional, convert_quotation_to_sale,
--   update_quotation_document y process_return calculan el ITBIS con
--   `products.tax_rate`. Un producto en norma guarda su tasa EFECTIVA (1.80)
--   y el disparador de abajo la mantiene pegada al modo, venga el cambio de
--   donde venga (formulario, Excel, alta rápida en el POS, shop-plus). El
--   modo se copia a cada línea vendida (`sale_items.itbis_mode`) para que la
--   factura diga "ITBIS 18% (Norma 07-2007)" aunque el producto cambie
--   después. El 607 recibe el ITBIS correcto porque `sales.tax_amount` ya
--   sale bien.
--
-- Qué hace:
--   1. app_settings: `company_tagline` (giro bajo el nombre en la factura),
--      `invoice_a4_style` ('standard' | 'classic') e
--      `inv_default_itbis_mode` (con qué tipo de ITBIS arranca un producto
--      nuevo).
--   2. products.itbis_mode: vacío al insertar → el default de la empresa.
--      En norma: tax_rate = 1.80 y no exento. Al salir de la norma con la
--      tasa en 1.80 → vuelve a 18.00.
--   3. sale_items.itbis_mode: lo toma del producto al insertar la línea.
--   4. sales: invoice_project, invoice_location e invoice_concept (Proyecto,
--      Localización y Concepto de la factura clásica). La app los escribe
--      después del cobro y en Editar venta; la RLS `sales_update` ya lo
--      permite a quien opera el POS.
--
-- Idempotente. Solo agrega columnas, restricciones y dos disparadores. Sin
-- productos en norma (todas las empresas de hoy) el comportamiento no cambia.
-- Correr en cada base que use este frontend ANTES de desplegar la app: la
-- app lee estas columnas.
-- ============================================================================

begin;

-- 1. Configuración por empresa ------------------------------------------------
alter table public.app_settings
  add column if not exists company_tagline text,
  add column if not exists invoice_a4_style text not null default 'standard',
  add column if not exists inv_default_itbis_mode text not null default 'regular';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'app_settings_invoice_a4_style_check'
  ) then
    alter table public.app_settings
      add constraint app_settings_invoice_a4_style_check
      check (invoice_a4_style in ('standard', 'classic'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'app_settings_inv_default_itbis_mode_check'
  ) then
    alter table public.app_settings
      add constraint app_settings_inv_default_itbis_mode_check
      check (inv_default_itbis_mode in ('regular', 'norma_07_2007'));
  end if;
end $$;

-- 2. Tipo de ITBIS del producto ----------------------------------------------
alter table public.products add column if not exists itbis_mode text;
update public.products set itbis_mode = 'regular' where itbis_mode is null;
-- Sin default a propósito: el disparador pone el de la empresa cuando el
-- INSERT no lo trae (NOT NULL se revisa después de los BEFORE).
alter table public.products alter column itbis_mode drop default;
alter table public.products alter column itbis_mode set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_itbis_mode_check'
  ) then
    alter table public.products
      add constraint products_itbis_mode_check
      check (itbis_mode in ('regular', 'norma_07_2007'));
  end if;
end $$;

create or replace function public.tg_products_itbis_mode()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_default text;
begin
  if new.itbis_mode is null then
    select s.inv_default_itbis_mode
      into v_default
      from public.branches b
      join public.app_settings s on s.company_id = b.company_id
     where b.id = new.branch_id
     limit 1;
    new.itbis_mode := coalesce(v_default, 'regular');
  end if;

  if new.itbis_mode = 'norma_07_2007' then
    -- 18% sobre el 10% del monto.
    new.tax_rate := 1.80;
    new.is_tax_exempt := false;
  elsif tg_op = 'UPDATE'
        and old.itbis_mode = 'norma_07_2007'
        and new.tax_rate = 1.80 then
    new.tax_rate := 18.00;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_products_itbis_mode on public.products;
create trigger trg_products_itbis_mode
  before insert or update on public.products
  for each row execute function public.tg_products_itbis_mode();

-- 3. Tipo de ITBIS de cada línea vendida -------------------------------------
alter table public.sale_items
  add column if not exists itbis_mode text not null default 'regular';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'sale_items_itbis_mode_check'
  ) then
    alter table public.sale_items
      add constraint sale_items_itbis_mode_check
      check (itbis_mode in ('regular', 'norma_07_2007'));
  end if;
end $$;

create or replace function public.tg_sale_items_itbis_mode()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text;
begin
  select p.itbis_mode into v_mode
    from public.products p
   where p.id = new.product_id;
  new.itbis_mode := coalesce(v_mode, new.itbis_mode, 'regular');
  return new;
end;
$$;

drop trigger if exists trg_sale_items_itbis_mode on public.sale_items;
create trigger trg_sale_items_itbis_mode
  before insert or update of product_id on public.sale_items
  for each row execute function public.tg_sale_items_itbis_mode();

-- 4. Datos de la factura clásica ---------------------------------------------
alter table public.sales
  add column if not exists invoice_project text,
  add column if not exists invoice_location text,
  add column if not exists invoice_concept text;

commit;

notify pgrst, 'reload schema';

-- Verificación (solo lectura):
-- select column_name from information_schema.columns
--  where table_schema = 'public'
--    and (table_name, column_name) in (
--      ('app_settings','company_tagline'), ('app_settings','invoice_a4_style'),
--      ('app_settings','inv_default_itbis_mode'), ('products','itbis_mode'),
--      ('sale_items','itbis_mode'), ('sales','invoice_project'),
--      ('sales','invoice_location'), ('sales','invoice_concept'));
