-- ============================================================================
-- Migración 83 — Permiso "Ver cuadre de caja" (cash.reconciliation)
-- ============================================================================
-- Hoy cualquiera que entre a Cierre de Caja ve el cuadre completo: apertura,
-- total vendido, ingreso en efectivo, transferencias, tarjeta, crédito,
-- gastos, sangrías y sobre todo el ESPERADO EN CAJA y la diferencia contra lo
-- contado.
--
-- El dueño no quiere que el cajero vea eso: si sabe cuánto debería haber,
-- sabe también cuánto sobra, y puede tomarlo. El cajero debe poder cerrar su
-- caja a ciegas — contar el efectivo por denominación, declararlo e imprimir
-- su desglose — sin conocer el esperado ni la diferencia.
--
-- Pero no todos los negocios operan igual: algunos sí quieren que su cajero
-- vea el cuadre. Por eso es un permiso y no una regla fija — se concede con el
-- override por usuario (public.user_permissions) desde la pantalla de
-- empleados, igual que `reports.profit`.
--
-- Por defecto: admin, supervisor y accountant SÍ; `cashier` NO.
--
-- Idempotente: se puede correr varias veces sin efectos secundarios.
-- ============================================================================

begin;

-- ── 1) Catálogo de permisos ─────────────────────────────────────────────────
-- sort_order 63 lo deja después de cash.open (60), cash.close (61) y
-- cash.manage (62).
insert into public.permissions (
  code, name, module, action_type, description, sort_order
)
values
  (
    'cash.reconciliation',
    'Ver cuadre de caja',
    'cash',
    'view',
    'Ver el esperado en caja, la diferencia y los totales por método de pago '
    'al cerrar. Sin este permiso el cierre es a ciegas: solo se declara el '
    'efectivo contado.',
    63
  )
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

-- ── 2) Asignaciones por rol ─────────────────────────────────────────────────
-- OJO: `cashier` NO está en la lista. Es el punto de la migración.
-- `do nothing` en vez de `do update`: si un admin revocó el permiso a mano,
-- volver a correr esto no debe re-otorgarlo.
insert into public.role_permissions (role_key, permission_id, allowed)
select grant_map.role_key, p.id, true
from public.permissions p
join (
  values
    ('admin', 'cash.reconciliation'),
    ('supervisor', 'cash.reconciliation'),
    ('accountant', 'cash.reconciliation')
) as grant_map(role_key, permission_code)
  on p.code = grant_map.permission_code
on conflict (role_key, permission_id) do nothing;

commit;

notify pgrst, 'reload schema';
