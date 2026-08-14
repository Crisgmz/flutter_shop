-- ============================================================================
-- Migración 67 — Permiso "Ver ganancia" (reports.profit)
-- ============================================================================
-- Hoy la ganancia/utilidad (precio − costo) se muestra a cualquiera que pueda
-- ver el historial de ventas o el cierre del día. En la práctica el dueño no
-- quiere que el cajero vea el margen de cada producto.
--
-- Esta migración agrega el permiso granular `reports.profit` y lo concede por
-- defecto a admin, supervisor y accountant. El rol `cashier` queda FUERA a
-- propósito: el cajero no ve ganancia salvo que se le active el override
-- por usuario (public.user_permissions), que es justamente el switch que la
-- pantalla de empleados expone.
--
-- Ejecutar después de:
--   supabase/sql-next/20260421_structural_backoffice_foundation.sql
--   supabase/sql-next/20260422_fix_permissions_final.sql
--
-- Idempotente: se puede correr varias veces sin efectos secundarios.
-- ============================================================================

begin;

-- ── 1) Catálogo de permisos ─────────────────────────────────────────────────
-- sort_order 72 lo deja al lado de reports.view (70) y reports.export (71).
-- No es un valor único en la tabla (reports.fiscal también usa 72); sort_order
-- solo ordena la lista en la UI de permisos.
insert into public.permissions (
  code, name, module, action_type, description, sort_order
)
values
  (
    'reports.profit',
    'Ver ganancia',
    'reports',
    'view',
    'Ver ganancia/utilidad en historial de ventas, cierre del día y reportes',
    72
  )
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

-- ── 2) Asignaciones por rol ─────────────────────────────────────────────────
-- OJO: `cashier` NO está en la lista. Es intencional.
-- `do nothing` en vez de `do update`: si un admin revocó el permiso a mano
-- (allowed = false), volver a correr esta migración no debe re-otorgarlo.
insert into public.role_permissions (role_key, permission_id, allowed)
select grant_map.role_key, p.id, true
from public.permissions p
join (
  values
    ('admin', 'reports.profit'),
    ('supervisor', 'reports.profit'),
    ('accountant', 'reports.profit')
) as grant_map(role_key, permission_code)
  on p.code = grant_map.permission_code
on conflict (role_key, permission_id) do nothing;

commit;

notify pgrst, 'reload schema';
