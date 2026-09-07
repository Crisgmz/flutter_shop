-- ============================================================================
-- Migración 89 — Permiso "Editar precio en la venta" (sales.edit_price)
-- ============================================================================
-- En el POS, cada línea del carrito trae el precio en un campo escribible: el
-- cajero puede sobrescribir el precio de venta de cualquier producto y cobrar
-- lo que quiera. `RoleAccess.canEditPrices` ya decía que eso es cosa de
-- admin/supervisor, pero nadie consultaba ese helper en el carrito, así que el
-- campo estaba abierto para todos.
--
-- A partir de esta migración el precio de la línea es de admin y supervisor.
-- El cajero lo ve, pero no lo toca: vende al precio del catálogo (o al del
-- nivel de precio que le corresponda al cliente).
--
-- Configurable por negocio: el dueño que sí quiera dejar a un cajero de
-- confianza cambiar precios le activa el override desde Usuarios → Ventas,
-- igual que `reports.profit` (67), `cash.reconciliation` (83) y los permisos
-- de gastos (86).
--
-- Nota: el descuento por línea sigue abierto — es un permiso aparte que hoy no
-- existe en el catálogo.
--
-- Idempotente: se puede correr varias veces sin efectos secundarios.
-- ============================================================================

begin;

-- ── 1) Catálogo de permisos ─────────────────────────────────────────────────
-- sort_order 10 lo deja dentro del bloque de Ventas, junto a los demás
-- permisos del módulo `sales`.
insert into public.permissions (
  code, name, module, action_type, description, sort_order
)
values
  (
    'sales.edit_price',
    'Editar precio en la venta',
    'sales',
    'update',
    'Cambiar a mano el precio unitario de una línea del carrito en el punto '
    'de venta. Sin este permiso el precio queda fijo en el del catálogo.',
    10
  )
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

-- ── 2) Asignaciones por rol ─────────────────────────────────────────────────
-- Solo admin y supervisor. El cajero queda fuera a propósito: es el punto de
-- la migración. `do nothing` para no re-otorgar un permiso revocado a mano.
insert into public.role_permissions (role_key, permission_id, allowed)
select grant_map.role_key, p.id, true
from public.permissions p
join (
  values
    ('admin', 'sales.edit_price'),
    ('supervisor', 'sales.edit_price')
) as grant_map(role_key, permission_code)
  on p.code = grant_map.permission_code
on conflict (role_key, permission_id) do nothing;

commit;

notify pgrst, 'reload schema';
