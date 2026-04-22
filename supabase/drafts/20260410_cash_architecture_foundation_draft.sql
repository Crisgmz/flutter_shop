-- =============================================================================
-- DRAFT ONLY - DO NOT APPLY BLINDLY IN PRODUCTION
-- Shop+ RD - cash architecture foundation
-- Fecha: 2026-04-10
--
-- Purpose:
--   Add the first serious cash-architecture foundation without breaking current
--   app runtime. This draft is intentionally additive and staged.
--
-- Important compatibility rule:
--   The existing unique index on public.cash_sessions(branch_id) for open
--   sessions is NOT dropped here. Current app flows depend on it implicitly.
--   A future migration can replace it once the app opens sessions by location.
--
-- Existing context:
--   - public.cash_sessions currently models branch-wide opening/closing.
--   - public.payments and public.expenses optionally point to cash_session_id.
--   - Branch isolation + RLS already exist in 01_schema.sql.
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
  'Physical or logical places where cash/balances are held: drawer, safe, petty cash, bank, wallet, in transit.';

comment on column public.cash_locations.allows_sessions is
  'Whether an operational cash session may be opened against this location.';

create index if not exists cash_locations_branch_status_idx
  on public.cash_locations (branch_id, status, sort_order, name);

create index if not exists cash_locations_parent_idx
  on public.cash_locations (parent_location_id)
  where parent_location_id is not null;

-- =============================================================================
-- 3) TRANSFERS
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
-- 4) MOVEMENTS LEDGER
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
  'Branch-scoped operational cash ledger. One row impacts one location with in/out direction.';

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
-- 5) EVOLVE cash_sessions INTO LOCATION-AWARE SESSIONS
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
  'Future location-aware session target. Nullable during compatibility phase.';

comment on column public.cash_sessions.device_id is
  'Optional client/device identifier, reserved for future per-device session rules.';

comment on column public.cash_sessions.device_name is
  'Optional human-readable terminal/device name.';

comment on column public.cash_sessions.session_label is
  'Optional human-readable operational label for the session.';

create index if not exists cash_sessions_location_idx
  on public.cash_sessions (location_id)
  where location_id is not null;

create unique index if not exists cash_sessions_open_location_unique
  on public.cash_sessions (location_id)
  where status = 'open' and location_id is not null;

-- NOTE:
-- Keep existing cash_sessions_open_unique on (branch_id) untouched for now.
-- That means current behavior remains exactly the same until the app and data
-- migration intentionally move to per-location opening rules.

-- =============================================================================
-- 6) OPTIONAL VIEW - CURRENT LOCATION BALANCES
-- =============================================================================
create or replace view public.cash_location_balances as
select
  l.id as location_id,
  l.branch_id,
  l.code,
  l.name,
  l.location_type,
  l.status,
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
  l.status;

comment on view public.cash_location_balances is
  'Derived operational balance per cash location based on cash_movements.';

-- =============================================================================
-- 7) RLS DRAFT (aligned with current branch helpers)
-- =============================================================================
-- The main schema already defines helper functions like:
--   public.has_branch_access(uuid)
--   public.can_manage_branch_data()
--   public.can_operate_pos()
--
-- Draft policy shape:
--
-- alter table public.cash_locations enable row level security;
-- alter table public.cash_transfers enable row level security;
-- alter table public.cash_movements enable row level security;
--
-- create policy cash_locations_select
-- on public.cash_locations
-- for select
-- using (public.has_branch_access(branch_id));
--
-- create policy cash_locations_write
-- on public.cash_locations
-- for all
-- using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
-- with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());
--
-- create policy cash_transfers_select
-- on public.cash_transfers
-- for select
-- using (public.has_branch_access(branch_id));
--
-- create policy cash_transfers_write
-- on public.cash_transfers
-- for all
-- using (public.has_branch_access(branch_id) and public.can_operate_pos())
-- with check (public.has_branch_access(branch_id) and public.can_operate_pos());
--
-- create policy cash_movements_select
-- on public.cash_movements
-- for select
-- using (public.has_branch_access(branch_id));
--
-- create policy cash_movements_write
-- on public.cash_movements
-- for all
-- using (public.has_branch_access(branch_id) and public.can_operate_pos())
-- with check (public.has_branch_access(branch_id) and public.can_operate_pos());

-- =============================================================================
-- 8) BACKFILL PLAN (COMMENTED - MANUAL EXECUTION ONLY)
-- =============================================================================
-- A safe rollout should backfill locations first and sessions second.
-- Suggested sequence:
--
-- 1) Create one default location per branch.
--
-- insert into public.cash_locations (
--   branch_id,
--   code,
--   name,
--   location_type,
--   status,
--   allows_sessions
-- )
-- select
--   b.id,
--   'MAIN_DRAWER',
--   'Caja principal',
--   'register_drawer',
--   'active',
--   true
-- from public.branches b
-- where not exists (
--   select 1
--   from public.cash_locations l
--   where l.branch_id = b.id
--     and l.code = 'MAIN_DRAWER'
-- );
--
-- 2) Attach historical sessions to branch default location.
--
-- update public.cash_sessions s
-- set location_id = l.id
-- from public.cash_locations l
-- where l.branch_id = s.branch_id
--   and l.code = 'MAIN_DRAWER'
--   and s.location_id is null;
--
-- 3) DO NOT drop the branch-wide open-session unique index yet.
--
-- 4) Once the app opens sessions by location, evaluate replacing:
--      cash_sessions_open_unique(branch_id)
--    with one of:
--      - open per location
--      - open per location + user
--      - open per location + device

commit;
