-- ============================================================================
-- Migración 91 — Permisos de precio en el POS: nivel de precio y precio mínimo
-- ============================================================================
-- Dos pedidos del mismo día (2026-09-27), los dos sobre lo que el cajero puede
-- cobrar:
--
--   1) sales.price_tier — "Elegir nivel de precio en la venta".
--      El selector de nivel del carrito (mayorista, pago efectivo, …; paso 9)
--      estaba abierto para todos: cualquier cajero le daba precio al por mayor
--      a cualquier cliente. Sin este permiso el selector no aparece y el cajero
--      vende al precio base o al nivel que tenga asignado el cliente.
--
--   2) sales.below_min_price — "Vender por debajo del precio mínimo".
--      El mínimo de un producto es el más bajo entre su precio base y sus
--      niveles cargados. Ej.: base 600, nivel 1 550, nivel 2 500 → 500. Sin
--      este permiso ninguna línea puede quedar por debajo de ese mínimo, ni
--      cambiando el precio ni con descuento (se mira el precio ya descontado).
--
-- Los dos quedan para admin y supervisor, igual que sales.edit_price (89). El
-- dueño se los da a un cajero de confianza desde Usuarios → Ventas.
--
-- El control vive en la app (como sales.edit_price): el RPC de la venta no
-- conoce los niveles de precio del producto.
--
-- Idempotente: se puede correr varias veces sin efectos secundarios.
-- ============================================================================

begin;

-- ── 1) Catálogo de permisos ─────────────────────────────────────────────────
-- sort_order 11 y 12: justo después de sales.edit_price (10).
insert into public.permissions (
  code, name, module, action_type, description, sort_order
)
values
  (
    'sales.price_tier',
    'Elegir nivel de precio en la venta',
    'sales',
    'update',
    'Elegir a mano el nivel de precio del carrito (mayorista, etc.) en el '
    'punto de venta. Sin este permiso se vende al precio base o al nivel '
    'asignado al cliente.',
    11
  ),
  (
    'sales.below_min_price',
    'Vender por debajo del precio mínimo',
    'sales',
    'update',
    'Vender un producto por debajo de su precio más bajo (el menor entre el '
    'precio base y sus niveles), ya sea cambiando el precio o con descuento.',
    12
  )
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

-- ── 2) Asignaciones por rol ─────────────────────────────────────────────────
-- Solo admin y supervisor. `do nothing` para no re-otorgar un permiso que el
-- dueño haya revocado a mano.
insert into public.role_permissions (role_key, permission_id, allowed)
select grant_map.role_key, p.id, true
from public.permissions p
join (
  values
    ('admin', 'sales.price_tier'),
    ('supervisor', 'sales.price_tier'),
    ('admin', 'sales.below_min_price'),
    ('supervisor', 'sales.below_min_price')
) as grant_map(role_key, permission_code)
  on p.code = grant_map.permission_code
on conflict (role_key, permission_id) do nothing;

commit;

notify pgrst, 'reload schema';
