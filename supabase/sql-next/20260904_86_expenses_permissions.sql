-- ============================================================================
-- Migración 86 — Permisos del módulo Gastos (expenses.*)
-- ============================================================================
-- Hoy "Gastos" no existe para el cajero y tampoco existe en la pantalla de
-- permisos del empleado: el módulo se filtraba solo por `allowedRoles` en el
-- menú (admin, supervisor, accountant) y el catálogo `public.permissions`
-- nunca tuvo un módulo `expenses`. Resultado: el dueño no puede dárselo a su
-- cajero ni aunque quiera, porque no hay switch que activar.
--
-- Pero en la práctica el gasto lo hace quien está en la caja: el cajero paga
-- el motoconcho, la fundita, el agua, el almuerzo — y ese dinero sale de la
-- caja que él mismo cuadra. Por eso el cajero, POR DEFECTO, sí puede ver y
-- registrar gastos.
--
-- Lo que NO puede por defecto es corregir un gasto ya registrado
-- (`expenses.edit`) ni borrarlo (`expenses.delete`): eso es control, no
-- operación, y sigue siendo de admin/supervisor. Nótese que `expenses.delete`
-- además está respaldado por la RLS de la tabla (`can_manage_branch_data()`),
-- así que darle el override a un cajero le muestra el botón pero el borrado
-- lo sigue rechazando la base de datos.
--
-- Todo esto es configurable por negocio con el override por usuario
-- (public.user_permissions) desde la pantalla de empleados, igual que
-- `reports.profit` (migración 67) y `cash.reconciliation` (migración 83).
--
-- Idempotente: se puede correr varias veces sin efectos secundarios.
-- ============================================================================

begin;

-- ── 1) Catálogo de permisos ─────────────────────────────────────────────────
-- sort_order 110+ deja el módulo después de ncf (100-102), al final del menú
-- de permisos, que es donde el dueño espera ver un módulo nuevo.
insert into public.permissions (
  code, name, module, action_type, description, sort_order
)
values
  (
    'expenses.view',
    'Ver Gastos',
    'expenses',
    'view',
    'Entrar al módulo de Gastos y ver los egresos registrados en la sucursal.',
    110
  ),
  (
    'expenses.create',
    'Registrar Gastos',
    'expenses',
    'create',
    'Registrar un gasto nuevo (compra menor, transporte, servicios) que sale '
    'de la caja del día.',
    111
  ),
  (
    'expenses.edit',
    'Editar Gastos',
    'expenses',
    'edit',
    'Corregir un gasto ya registrado: monto, categoría, proveedor o fecha.',
    112
  ),
  (
    'expenses.delete',
    'Eliminar Gastos',
    'expenses',
    'delete',
    'Borrar un gasto registrado. La base de datos además solo lo permite a '
    'admin y supervisor.',
    113
  )
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

-- ── 2) Asignaciones por rol ─────────────────────────────────────────────────
-- `cashier` tiene view + create: es el punto de la migración.
-- `do nothing` en vez de `do update`: si un admin revocó un permiso a mano,
-- volver a correr esto no debe re-otorgarlo.
insert into public.role_permissions (role_key, permission_id, allowed)
select grant_map.role_key, p.id, true
from public.permissions p
join (
  values
    ('admin', 'expenses.view'),
    ('admin', 'expenses.create'),
    ('admin', 'expenses.edit'),
    ('admin', 'expenses.delete'),
    ('supervisor', 'expenses.view'),
    ('supervisor', 'expenses.create'),
    ('supervisor', 'expenses.edit'),
    ('supervisor', 'expenses.delete'),
    ('accountant', 'expenses.view'),
    ('accountant', 'expenses.create'),
    ('accountant', 'expenses.edit'),
    ('cashier', 'expenses.view'),
    ('cashier', 'expenses.create')
) as grant_map(role_key, permission_code)
  on p.code = grant_map.permission_code
on conflict (role_key, permission_id) do nothing;

commit;

notify pgrst, 'reload schema';
