-- ============================================================================
-- Migración 92 — Historial de precios: el % de cambio ya no rompe el UPDATE
-- ============================================================================
-- Reporte (2026-10-01): al importar inventario, tres productos fallaron con
--
--   numeric field overflow (22003): A field with precision 7, scale 2 must
--   round to an absolute value less than 10^5.
--
-- No es el importador. Es el trigger `trg_products_log_price_change` de la
-- migración 19: en cada cambio de precio o costo guarda el % de cambio en
-- `product_price_history.price_pct_change` / `cost_pct_change`, que son
-- `numeric(7,2)` — tope ±99,999.99 %. Esos productos tenían precio de relleno
-- (RD$ 1.00) y el Excel les puso el real: de 1.00 a 21,000.00 es +2,099,900 %,
-- no cabe, y como el trigger corre dentro del mismo UPDATE, Postgres rechaza
-- el cambio del producto entero. Lo mismo pasa editando el producto a mano.
--
-- Arreglo: el % pasa a `numeric` sin tope (se sigue redondeando a 2
-- decimales en el trigger). Cualquier precio que quepa en `products` (que es
-- numeric(14,2)) produce un % que ahora también cabe.
--
-- La vista `vw_product_price_history_recent` lee esas columnas, y Postgres no
-- deja cambiar el tipo de una columna que usa una vista: se suelta y se
-- recrea igual que en la migración 19. `fetch_product_price_history` ya
-- devolvía `numeric` y no se toca.
--
-- Idempotente: se puede correr varias veces sin efectos secundarios.
-- ============================================================================

begin;

-- ── 1) Columnas sin tope ────────────────────────────────────────────────────
drop view if exists public.vw_product_price_history_recent;

alter table public.product_price_history
  alter column price_pct_change type numeric,
  alter column cost_pct_change type numeric;

-- ── 2) Trigger: las variables también sin tope ──────────────────────────────
-- Copia de la versión de la migración 19; solo cambia el tipo de v_*_pct.
create or replace function public.tg_products_log_price_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_price_changed boolean := (new.price is distinct from old.price);
  v_cost_changed  boolean := (new.cost is distinct from old.cost);
  v_price_pct numeric;
  v_cost_pct  numeric;
begin
  if not v_price_changed and not v_cost_changed then
    return new;
  end if;

  -- Calcular % de cambio (NULL si valor anterior es 0 o NULL)
  if v_price_changed and old.price is not null and old.price <> 0 then
    v_price_pct := round((((new.price - old.price) / old.price) * 100)::numeric, 2);
  end if;
  if v_cost_changed and old.cost is not null and old.cost <> 0 then
    v_cost_pct := round((((new.cost - old.cost) / old.cost) * 100)::numeric, 2);
  end if;

  insert into public.product_price_history (
    branch_id, product_id, changed_by,
    old_price, new_price, old_cost, new_cost,
    price_delta, cost_delta,
    price_pct_change, cost_pct_change,
    source
  )
  values (
    new.branch_id, new.id, auth.uid(),
    old.price, new.price, old.cost, new.cost,
    case when v_price_changed then new.price - old.price end,
    case when v_cost_changed then new.cost - old.cost end,
    v_price_pct, v_cost_pct,
    'manual'
  );

  return new;
end;
$$;

-- ── 3) Vista: igual que en la migración 19 ──────────────────────────────────
create or replace view public.vw_product_price_history_recent
with (security_invoker = true)
as
select
  h.id,
  h.branch_id,
  h.product_id,
  p.name as product_name,
  p.sku as product_sku,
  h.changed_at,
  h.changed_by,
  prof.full_name as changed_by_name,
  h.old_price,
  h.new_price,
  h.old_cost,
  h.new_cost,
  h.price_delta,
  h.cost_delta,
  h.price_pct_change,
  h.cost_pct_change,
  h.change_reason,
  h.source
from public.product_price_history h
join public.products p
  on p.id = h.product_id and p.branch_id = h.branch_id
left join public.profiles prof
  on prof.id = h.changed_by
where h.changed_at >= timezone('utc', now()) - interval '365 days';

grant select on public.vw_product_price_history_recent to authenticated;

comment on view public.vw_product_price_history_recent is
  'Últimos 365 días de cambios de precio/costo por producto, con nombre del usuario.';

commit;

notify pgrst, 'reload schema';
