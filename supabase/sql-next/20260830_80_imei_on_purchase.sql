-- ============================================================================
-- Migración 80 — IMEI en la compra (por producto)
-- ============================================================================
-- Hasta ahora los IMEIs solo se escribían a mano en el formulario del producto
-- (`products.imeis`, migración 51) y salían al vender (`sale_items.imeis`,
-- migración 53). Faltaba la puerta de entrada: cuando llegan los equipos por
-- una COMPRA.
--
-- Este cambio agrega:
--   1. `products.imei_on_purchase` — interruptor POR PRODUCTO. Si está en
--      true, al agregar ese producto a una compra la app abre el cuadro para
--      escribir los IMEIs que entran. Si está en false, la compra ni pregunta
--      (por eso el default es false: el catálogo de un colmado no cambia).
--   2. `purchase_items.imeis` — los equipos que entraron en esa línea de la
--      compra, igual que `sale_items.imeis` guarda los que salieron.
--
-- La app, al registrar la compra, suma esos IMEIs a `products.imeis` (unión
-- sin repetidos), que es de donde el POS toma los equipos disponibles para
-- vender. El stock sigue subiendo por el trigger normal de `purchase_items`.
--
-- Ejecutar en el SQL Editor de Supabase. Idempotente.
-- ============================================================================

begin;

alter table public.products
  add column if not exists imei_on_purchase boolean not null default false;

comment on column public.products.imei_on_purchase is
  'Si es true, al comprar este producto se piden los IMEIs de los equipos que entran.';

alter table public.purchase_items
  add column if not exists imeis text[] not null default '{}';

comment on column public.purchase_items.imeis is
  'IMEIs que entraron por esta línea de compra. La app los suma a products.imeis.';

-- Búsqueda por IMEI dentro de compras (mismo patrón que sale_items_imeis_gin).
create index if not exists purchase_items_imeis_gin
  on public.purchase_items using gin (imeis);

commit;

notify pgrst, 'reload schema';
