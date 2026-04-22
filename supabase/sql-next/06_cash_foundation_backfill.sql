-- =============================================================================
-- Shop+ RD - Cash foundation backfill (safe + idempotent)
-- Fecha: 2026-04-10
--
-- Purpose:
--   Seed one default session-capable location per branch and attach historical
--   cash_sessions to it. This keeps current runtime intact while preparing
--   location-aware migration.
-- =============================================================================

begin;

insert into public.cash_locations (
  branch_id,
  code,
  name,
  location_type,
  status,
  description,
  allows_sessions,
  sort_order,
  metadata
)
select
  b.id,
  'MAIN_DRAWER',
  'Caja principal',
  'register_drawer',
  'active',
  'Ubicación por defecto para compatibilidad inicial de sesiones de caja.',
  true,
  0,
  jsonb_build_object(
    'seeded_by', '06_cash_foundation_backfill.sql',
    'compatibility_default', true
  )
from public.branches b
where not exists (
  select 1
  from public.cash_locations l
  where l.branch_id = b.id
    and l.code = 'MAIN_DRAWER'
);

update public.cash_sessions s
set location_id = l.id
from public.cash_locations l
where l.branch_id = s.branch_id
  and l.code = 'MAIN_DRAWER'
  and s.location_id is null;

commit;
