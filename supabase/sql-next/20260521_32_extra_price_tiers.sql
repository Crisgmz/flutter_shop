-- Extiende los tiers de precio de productos de 3 a 10.
--
-- Antes había solo price_tier_1, price_tier_2, price_tier_3. Ahora se
-- agregan price_tier_4..price_tier_10 para soportar negocios con más
-- niveles (p. ej. mayorista, distribuidor, VIP, online, B2B, etc.).
--
-- Las etiquetas de los tiers viven en app_settings.sale_price_types
-- (jsonb) — esa tabla no necesita cambios porque ya es flexible.
--
-- Todos los nuevos columns son nullable: si no se asigna precio en ese
-- tier, el código cae al `price` base.
--
-- Idempotente.

begin;

alter table public.products
  add column if not exists price_tier_4  numeric(14,2),
  add column if not exists price_tier_5  numeric(14,2),
  add column if not exists price_tier_6  numeric(14,2),
  add column if not exists price_tier_7  numeric(14,2),
  add column if not exists price_tier_8  numeric(14,2),
  add column if not exists price_tier_9  numeric(14,2),
  add column if not exists price_tier_10 numeric(14,2);

commit;
