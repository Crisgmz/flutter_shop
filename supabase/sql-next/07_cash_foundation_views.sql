-- =============================================================================
-- Shop+ RD - Cash foundation derived views
-- Fecha: 2026-04-10
-- =============================================================================

begin;

create or replace view public.cash_location_balances
with (security_invoker = true)
as
select
  l.id as location_id,
  l.branch_id,
  l.code,
  l.name,
  l.location_type,
  l.status,
  l.allows_sessions,
  l.parent_location_id,
  coalesce(sum(
    case m.entry_direction
      when 'in' then m.amount
      when 'out' then -m.amount
      else 0
    end
  ), 0)::numeric(14,2) as current_balance,
  max(m.effective_at) as last_movement_at
from public.cash_locations l
left join public.cash_movements m
  on m.location_id = l.id
 and m.branch_id = l.branch_id
group by
  l.id,
  l.branch_id,
  l.code,
  l.name,
  l.location_type,
  l.status,
  l.allows_sessions,
  l.parent_location_id;

comment on view public.cash_location_balances is
  'Current derived operational balance per cash location based on cash_movements.';

grant select on public.cash_location_balances to authenticated;

commit;
