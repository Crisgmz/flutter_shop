-- =============================================================================
-- Shop+ RD - Cash foundation core (phase-safe, additive)
-- Fecha: 2026-04-10
--
-- Purpose:
--   Introduce cash_locations, cash_transfers, cash_movements, and extend
--   cash_sessions with location-aware fields without breaking current runtime.
--
-- Compatibility rules:
--   - Keep existing public.cash_sessions_open_unique on (branch_id) untouched.
--   - Do not require location_id on cash_sessions yet.
--   - Do not change current payments/expenses/sales write paths yet.
-- =============================================================================

begin;

-- =============================================================================
-- 1) ENUMS
-- =============================================================================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'cash_location_type') then
    create type public.cash_location_type as enum (
      'register_drawer',
      'safe',
      'petty_cash',
      'bank_account',
      'mobile_wallet',
      'in_transit',
      'virtual'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_location_status') then
    create type public.cash_location_status as enum (
      'active',
      'inactive',
      'archived'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_entry_direction') then
    create type public.cash_entry_direction as enum (
      'in',
      'out'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_movement_type') then
    create type public.cash_movement_type as enum (
      'opening_float',
      'sale_cash_in',
      'customer_payment',
      'expense_cash_out',
      'supplier_payment',
      'deposit',
      'withdrawal',
      'adjustment',
      'transfer_out',
      'transfer_in',
      'close_reconciliation',
      'refund',
      'change_given'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_transfer_status') then
    create type public.cash_transfer_status as enum (
      'draft',
      'pending_approval',
      'approved',
      'in_transit',
      'received',
      'cancelled'
    );
  end if;
end
$$;

-- =============================================================================
-- 2) CASH LOCATIONS
-- =============================================================================
create table if not exists public.cash_locations (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  parent_location_id uuid,
  code text not null,
  name text not null,
  location_type public.cash_location_type not null,
  status public.cash_location_status not null default 'active',
  description text,
  allows_sessions boolean not null default false,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  unique (branch_id, code),
  constraint cash_locations_parent_fk
    foreign key (parent_location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict,
  constraint cash_locations_code_not_blank
    check (btrim(code) <> ''),
  constraint cash_locations_name_not_blank
    check (btrim(name) <> '')
);

comment on table public.cash_locations is
  'Physical or logical places where operational balances are held: drawer, safe, petty cash, bank, wallet, in transit.';

comment on column public.cash_locations.allows_sessions is
  'Whether an operational cash session may be opened against this location in future app flows.';

create index if not exists cash_locations_branch_status_idx
  on public.cash_locations (branch_id, status, sort_order, name);

create index if not exists cash_locations_parent_idx
  on public.cash_locations (parent_location_id)
  where parent_location_id is not null;

-- =============================================================================
-- 3) CASH TRANSFERS
-- =============================================================================
create table if not exists public.cash_transfers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  from_location_id uuid not null,
  to_location_id uuid not null,
  status public.cash_transfer_status not null default 'draft',
  amount numeric(14,2) not null,
  requested_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  received_by uuid references auth.users(id),
  requested_at timestamptz not null default timezone('utc', now()),
  approved_at timestamptz,
  sent_at timestamptz,
  received_at timestamptz,
  cancelled_at timestamptz,
  reference_number text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint cash_transfers_from_location_fk
    foreign key (from_location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict,
  constraint cash_transfers_to_location_fk
    foreign key (to_location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict,
  constraint cash_transfers_amount_positive
    check (amount > 0),
  constraint cash_transfers_distinct_locations
    check (from_location_id <> to_location_id)
);

comment on table public.cash_transfers is
  'Operational transfer document between two cash locations inside the same branch.';

create index if not exists cash_transfers_branch_status_idx
  on public.cash_transfers (branch_id, status, requested_at desc);

create index if not exists cash_transfers_from_idx
  on public.cash_transfers (from_location_id, requested_at desc);

create index if not exists cash_transfers_to_idx
  on public.cash_transfers (to_location_id, requested_at desc);

-- =============================================================================
-- 4) CASH MOVEMENTS
-- =============================================================================
create table if not exists public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  location_id uuid not null,
  cash_session_id uuid,
  transfer_id uuid,
  sale_id uuid,
  payment_id uuid,
  expense_id uuid,
  entry_direction public.cash_entry_direction not null,
  movement_type public.cash_movement_type not null,
  amount numeric(14,2) not null,
  effective_at timestamptz not null default timezone('utc', now()),
  reference_number text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint cash_movements_location_fk
    foreign key (location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict,
  constraint cash_movements_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete restrict,
  constraint cash_movements_transfer_fk
    foreign key (transfer_id, branch_id)
    references public.cash_transfers(id, branch_id)
    on delete restrict,
  constraint cash_movements_sale_fk
    foreign key (sale_id, branch_id)
    references public.sales(id, branch_id)
    on delete restrict,
  constraint cash_movements_payment_fk
    foreign key (payment_id)
    references public.payments(id)
    on delete restrict,
  constraint cash_movements_expense_fk
    foreign key (expense_id)
    references public.expenses(id)
    on delete restrict,
  constraint cash_movements_amount_positive
    check (amount > 0),
  constraint cash_movements_transfer_pairing_check
    check (
      (movement_type in ('transfer_out', 'transfer_in') and transfer_id is not null)
      or (movement_type not in ('transfer_out', 'transfer_in'))
    )
);

comment on table public.cash_movements is
  'Operational cash ledger. One row impacts one location with an in/out direction.';

comment on column public.cash_movements.entry_direction is
  'in increases available balance for the location; out decreases it.';

create index if not exists cash_movements_location_effective_idx
  on public.cash_movements (location_id, effective_at desc, created_at desc);

create index if not exists cash_movements_branch_effective_idx
  on public.cash_movements (branch_id, effective_at desc, created_at desc);

create index if not exists cash_movements_session_idx
  on public.cash_movements (cash_session_id)
  where cash_session_id is not null;

create index if not exists cash_movements_transfer_idx
  on public.cash_movements (transfer_id)
  where transfer_id is not null;

create index if not exists cash_movements_payment_idx
  on public.cash_movements (payment_id)
  where payment_id is not null;

create index if not exists cash_movements_expense_idx
  on public.cash_movements (expense_id)
  where expense_id is not null;

-- =============================================================================
-- 5) EVOLVE CASH SESSIONS INTO LOCATION-AWARE SESSIONS
-- =============================================================================
alter table public.cash_sessions
  add column if not exists location_id uuid,
  add column if not exists device_id text,
  add column if not exists device_name text,
  add column if not exists session_label text;

alter table public.cash_sessions
  drop constraint if exists cash_sessions_location_fk;

alter table public.cash_sessions
  add constraint cash_sessions_location_fk
    foreign key (location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict;

comment on column public.cash_sessions.location_id is
  'Nullable compatibility-phase location pointer. Future flows should open sessions against a cash location.';

comment on column public.cash_sessions.device_id is
  'Optional client/device identifier reserved for future session uniqueness rules.';

comment on column public.cash_sessions.device_name is
  'Optional human-readable terminal/device name.';

comment on column public.cash_sessions.session_label is
  'Optional human-readable session label.';

create index if not exists cash_sessions_location_idx
  on public.cash_sessions (location_id)
  where location_id is not null;

create unique index if not exists cash_sessions_open_location_unique
  on public.cash_sessions (location_id)
  where status = 'open' and location_id is not null;

-- Existing branch-wide open-session uniqueness remains in place by design.

-- =============================================================================
-- 6) TRIGGERS
-- =============================================================================
drop trigger if exists trg_cash_locations_updated_at on public.cash_locations;
create trigger trg_cash_locations_updated_at
before update on public.cash_locations
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_transfers_updated_at on public.cash_transfers;
create trigger trg_cash_transfers_updated_at
before update on public.cash_transfers
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_movements_updated_at on public.cash_movements;
create trigger trg_cash_movements_updated_at
before update on public.cash_movements
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_locations_audit_fields on public.cash_locations;
create trigger trg_cash_locations_audit_fields
before insert or update on public.cash_locations
for each row execute function public.set_audit_fields();

drop trigger if exists trg_cash_transfers_audit_fields on public.cash_transfers;
create trigger trg_cash_transfers_audit_fields
before insert or update on public.cash_transfers
for each row execute function public.set_audit_fields();

drop trigger if exists trg_cash_movements_audit_fields on public.cash_movements;
create trigger trg_cash_movements_audit_fields
before insert or update on public.cash_movements
for each row execute function public.set_audit_fields();

-- =============================================================================
-- 7) RLS + POLICIES
-- =============================================================================
alter table public.cash_locations enable row level security;
alter table public.cash_transfers enable row level security;
alter table public.cash_movements enable row level security;

drop policy if exists cash_locations_select on public.cash_locations;
create policy cash_locations_select
on public.cash_locations
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_locations_insert on public.cash_locations;
create policy cash_locations_insert
on public.cash_locations
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_locations_update on public.cash_locations;
create policy cash_locations_update
on public.cash_locations
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_locations_delete on public.cash_locations;
create policy cash_locations_delete
on public.cash_locations
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_transfers_select on public.cash_transfers;
create policy cash_transfers_select
on public.cash_transfers
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_transfers_insert on public.cash_transfers;
create policy cash_transfers_insert
on public.cash_transfers
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_transfers_update on public.cash_transfers;
create policy cash_transfers_update
on public.cash_transfers
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_transfers_delete on public.cash_transfers;
create policy cash_transfers_delete
on public.cash_transfers
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_movements_select on public.cash_movements;
create policy cash_movements_select
on public.cash_movements
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_movements_insert on public.cash_movements;
create policy cash_movements_insert
on public.cash_movements
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_movements_update on public.cash_movements;
create policy cash_movements_update
on public.cash_movements
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_movements_delete on public.cash_movements;
create policy cash_movements_delete
on public.cash_movements
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

-- =============================================================================
-- 8) GRANTS
-- =============================================================================
grant select, insert, update, delete on public.cash_locations to authenticated;
grant select, insert, update, delete on public.cash_transfers to authenticated;
grant select, insert, update, delete on public.cash_movements to authenticated;

commit;
