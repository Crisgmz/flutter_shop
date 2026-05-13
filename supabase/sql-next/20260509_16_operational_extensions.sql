-- 20260509_16_operational_extensions.sql
-- Shop+ RD - Sprint Facturación 2026-05.
--
-- Esta migración prepara backend para:
--   F3 — Adición de efectivo a la caja activa (cash_register_movements).
--   F8 — Módulo de caja chica (petty_cash_*).
--   F9 — Precio por cliente (helper de tier — todas las columnas ya
--        existen en migración 20260421).
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_15_realtime_report_views.sql

begin;

-- =====================================================
-- 1) Enums
-- =====================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'cash_movement_type') then
    create type public.cash_movement_type as enum (
      'deposit',      -- inyección de efectivo a la caja
      'withdrawal',   -- sangría / retiro
      'adjustment',   -- ajuste manual (sobrante/faltante)
      'opening_top_up' -- agregar al monto de apertura
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'petty_cash_session_status') then
    create type public.petty_cash_session_status as enum ('open', 'closed');
  end if;

  if not exists (select 1 from pg_type where typname = 'petty_cash_movement_type') then
    create type public.petty_cash_movement_type as enum (
      'income',          -- ingreso (reposición o caja recibida)
      'expense',         -- gasto
      'replenishment',   -- reposición desde caja principal
      'adjustment'       -- ajuste de arqueo
    );
  end if;
end $$;

-- =====================================================
-- 2) F3 — Cash register movements (inyección/retiro a la sesión activa)
-- =====================================================

create table if not exists public.cash_register_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  cash_session_id uuid not null,
  movement_type public.cash_movement_type not null,
  amount numeric(14,2) not null check (amount > 0),
  reason text,
  reference_type text,
  reference_id uuid,
  performed_by uuid references auth.users(id),
  occurred_at timestamptz not null default timezone('utc', now()),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint cash_register_movements_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete cascade
);

create index if not exists cash_register_movements_session_idx
  on public.cash_register_movements (cash_session_id, occurred_at desc);
create index if not exists cash_register_movements_branch_idx
  on public.cash_register_movements (branch_id, occurred_at desc);

comment on table public.cash_register_movements is
  'Movimientos manuales de efectivo dentro de una sesión de caja '
  '(inyecciones, sangrías, ajustes). Cada inserción ajusta '
  'cash_sessions.expected_amount.';

-- Trigger: ajustar expected_amount al insertar/borrar el movimiento
create or replace function public.apply_cash_register_movement()
returns trigger
language plpgsql
as $$
declare
  v_delta numeric(14,2);
begin
  if tg_op = 'INSERT' then
    v_delta := case new.movement_type
      when 'deposit'        then  new.amount
      when 'opening_top_up' then  new.amount
      when 'adjustment'     then  new.amount  -- signed positive = sobrante
      when 'withdrawal'     then -new.amount
      else 0
    end;
    update public.cash_sessions
       set expected_amount = coalesce(expected_amount, 0) + v_delta
     where id = new.cash_session_id
       and branch_id = new.branch_id;
    return new;
  end if;
  if tg_op = 'DELETE' then
    v_delta := case old.movement_type
      when 'deposit'        then  old.amount
      when 'opening_top_up' then  old.amount
      when 'adjustment'     then  old.amount
      when 'withdrawal'     then -old.amount
      else 0
    end;
    update public.cash_sessions
       set expected_amount = coalesce(expected_amount, 0) - v_delta
     where id = old.cash_session_id
       and branch_id = old.branch_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_cash_register_movements_apply on public.cash_register_movements;
create trigger trg_cash_register_movements_apply
after insert or delete on public.cash_register_movements
for each row execute function public.apply_cash_register_movement();

drop trigger if exists trg_cash_register_movements_updated_at on public.cash_register_movements;
create trigger trg_cash_register_movements_updated_at
before update on public.cash_register_movements
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_register_movements_audit on public.cash_register_movements;
create trigger trg_cash_register_movements_audit
before insert or update on public.cash_register_movements
for each row execute function public.set_audit_fields();

alter table public.cash_register_movements enable row level security;

drop policy if exists cash_register_movements_select on public.cash_register_movements;
create policy cash_register_movements_select
on public.cash_register_movements
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_register_movements_insert on public.cash_register_movements;
create policy cash_register_movements_insert
on public.cash_register_movements
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_register_movements_update on public.cash_register_movements;
create policy cash_register_movements_update
on public.cash_register_movements
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_register_movements_delete on public.cash_register_movements;
create policy cash_register_movements_delete
on public.cash_register_movements
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- =====================================================
-- 3) F8 — Caja chica
-- =====================================================

create table if not exists public.petty_cash_categories (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  name text not null,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

-- UNIQUE en expresión `lower(name)` requiere índice (no se puede inline).
create unique index if not exists petty_cash_categories_branch_name_unique
  on public.petty_cash_categories (branch_id, lower(name));

create table if not exists public.petty_cash_sessions (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  opened_by uuid not null references auth.users(id),
  closed_by uuid references auth.users(id),
  status public.petty_cash_session_status not null default 'open',
  opened_at timestamptz not null default timezone('utc', now()),
  closed_at timestamptz,
  opening_amount numeric(14,2) not null default 0 check (opening_amount >= 0),
  expected_amount numeric(14,2) not null default 0,
  closing_amount numeric(14,2),
  difference_amount numeric(14,2),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id)
);

-- Solo una sesión abierta de caja chica por sucursal a la vez
create unique index if not exists petty_cash_sessions_open_unique
  on public.petty_cash_sessions (branch_id)
  where status = 'open';

create table if not exists public.petty_cash_movements (
  id uuid primary key default gen_random_uuid(),
  petty_cash_session_id uuid not null,
  branch_id uuid not null,
  movement_type public.petty_cash_movement_type not null,
  category_id uuid references public.petty_cash_categories(id) on delete set null,
  amount numeric(14,2) not null check (amount > 0),
  description text,
  payee text,
  receipt_reference text,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint petty_cash_movements_session_fk
    foreign key (petty_cash_session_id, branch_id)
    references public.petty_cash_sessions(id, branch_id)
    on delete cascade
);

create index if not exists petty_cash_movements_session_idx
  on public.petty_cash_movements (petty_cash_session_id, occurred_at desc);
create index if not exists petty_cash_movements_category_idx
  on public.petty_cash_movements (category_id);
create index if not exists petty_cash_movements_branch_idx
  on public.petty_cash_movements (branch_id, occurred_at desc);

-- Trigger: ajustar expected_amount de la sesión por cada movimiento
create or replace function public.apply_petty_cash_movement()
returns trigger
language plpgsql
as $$
declare
  v_delta numeric(14,2);
begin
  if tg_op = 'INSERT' then
    v_delta := case new.movement_type
      when 'income'        then  new.amount
      when 'replenishment' then  new.amount
      when 'adjustment'    then  new.amount  -- positivo = sobrante; usar valor negativo en `amount` no se permite por CHECK; usar 'expense' para faltante
      when 'expense'       then -new.amount
      else 0
    end;
    update public.petty_cash_sessions
       set expected_amount = coalesce(expected_amount, 0) + v_delta
     where id = new.petty_cash_session_id
       and branch_id = new.branch_id;
    return new;
  end if;
  if tg_op = 'DELETE' then
    v_delta := case old.movement_type
      when 'income'        then  old.amount
      when 'replenishment' then  old.amount
      when 'adjustment'    then  old.amount
      when 'expense'       then -old.amount
      else 0
    end;
    update public.petty_cash_sessions
       set expected_amount = coalesce(expected_amount, 0) - v_delta
     where id = old.petty_cash_session_id
       and branch_id = old.branch_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_petty_cash_movements_apply on public.petty_cash_movements;
create trigger trg_petty_cash_movements_apply
after insert or delete on public.petty_cash_movements
for each row execute function public.apply_petty_cash_movement();

drop trigger if exists trg_petty_cash_sessions_updated_at on public.petty_cash_sessions;
create trigger trg_petty_cash_sessions_updated_at
before update on public.petty_cash_sessions
for each row execute function public.set_updated_at();

drop trigger if exists trg_petty_cash_sessions_audit on public.petty_cash_sessions;
create trigger trg_petty_cash_sessions_audit
before insert or update on public.petty_cash_sessions
for each row execute function public.set_audit_fields();

drop trigger if exists trg_petty_cash_movements_updated_at on public.petty_cash_movements;
create trigger trg_petty_cash_movements_updated_at
before update on public.petty_cash_movements
for each row execute function public.set_updated_at();

drop trigger if exists trg_petty_cash_movements_audit on public.petty_cash_movements;
create trigger trg_petty_cash_movements_audit
before insert or update on public.petty_cash_movements
for each row execute function public.set_audit_fields();

drop trigger if exists trg_petty_cash_categories_updated_at on public.petty_cash_categories;
create trigger trg_petty_cash_categories_updated_at
before update on public.petty_cash_categories
for each row execute function public.set_updated_at();

drop trigger if exists trg_petty_cash_categories_audit on public.petty_cash_categories;
create trigger trg_petty_cash_categories_audit
before insert or update on public.petty_cash_categories
for each row execute function public.set_audit_fields();

-- RLS petty_cash_categories
alter table public.petty_cash_categories enable row level security;

drop policy if exists petty_cash_categories_select on public.petty_cash_categories;
create policy petty_cash_categories_select
on public.petty_cash_categories
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists petty_cash_categories_write on public.petty_cash_categories;
create policy petty_cash_categories_write
on public.petty_cash_categories
for all
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

-- RLS petty_cash_sessions
alter table public.petty_cash_sessions enable row level security;

drop policy if exists petty_cash_sessions_select on public.petty_cash_sessions;
create policy petty_cash_sessions_select
on public.petty_cash_sessions
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists petty_cash_sessions_insert on public.petty_cash_sessions;
create policy petty_cash_sessions_insert
on public.petty_cash_sessions
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists petty_cash_sessions_update on public.petty_cash_sessions;
create policy petty_cash_sessions_update
on public.petty_cash_sessions
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists petty_cash_sessions_delete on public.petty_cash_sessions;
create policy petty_cash_sessions_delete
on public.petty_cash_sessions
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- RLS petty_cash_movements
alter table public.petty_cash_movements enable row level security;

drop policy if exists petty_cash_movements_select on public.petty_cash_movements;
create policy petty_cash_movements_select
on public.petty_cash_movements
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists petty_cash_movements_insert on public.petty_cash_movements;
create policy petty_cash_movements_insert
on public.petty_cash_movements
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists petty_cash_movements_update on public.petty_cash_movements;
create policy petty_cash_movements_update
on public.petty_cash_movements
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists petty_cash_movements_delete on public.petty_cash_movements;
create policy petty_cash_movements_delete
on public.petty_cash_movements
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- Seed: categorías default por sucursal. Idempotente vía el índice único
-- `petty_cash_categories_branch_name_unique`.
insert into public.petty_cash_categories (branch_id, name, description, sort_order)
select b.id, x.name, x.description, x.sort_order
  from public.branches b
  cross join (values
    ('Transporte',   'Combustible, taxi, peajes',                10),
    ('Papelería',    'Material de oficina, impresiones',          20),
    ('Limpieza',     'Productos de limpieza, mantenimiento',      30),
    ('Comida',       'Almuerzos, refrigerios para el personal',   40),
    ('Servicios',    'Pagos puntuales (mensajería, plomero…)',    50),
    ('Otros',        'Gastos varios sin categoría',               99)
  ) as x(name, description, sort_order)
on conflict (branch_id, lower(name)) do nothing;

-- =====================================================
-- 4) F9 — Helper para resolver precio por cliente
-- =====================================================
--
-- products tiene: price (base), price_tier_1, price_tier_2, price_tier_3.
-- clients tiene:  price_tier ('retail' | 'tier_1' | 'tier_2' | 'tier_3').
-- Esta función devuelve el precio efectivo dado un producto y opcional
-- cliente. Útil para POS y reportes.

create or replace function public.resolve_product_price(
  p_product_id uuid,
  p_client_id uuid default null
)
returns numeric(14,2)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_tier text;
  v_price numeric(14,2);
  v_tier_1 numeric(14,2);
  v_tier_2 numeric(14,2);
  v_tier_3 numeric(14,2);
begin
  select branch_id, price, price_tier_1, price_tier_2, price_tier_3
    into v_branch_id, v_price, v_tier_1, v_tier_2, v_tier_3
    from public.products
   where id = p_product_id;

  if v_branch_id is null then
    return null;
  end if;

  if p_client_id is null then
    return v_price;
  end if;

  select coalesce(price_tier, 'retail') into v_tier
    from public.clients
   where id = p_client_id and branch_id = v_branch_id;

  return case lower(coalesce(v_tier, 'retail'))
    when 'tier_1' then coalesce(v_tier_1, v_price)
    when 'tier_2' then coalesce(v_tier_2, v_price)
    when 'tier_3' then coalesce(v_tier_3, v_price)
    else v_price
  end;
end;
$$;

grant execute on function public.resolve_product_price(uuid, uuid) to authenticated;

-- Etiquetas legibles para los tiers (consumido por la UI; se pueden
-- personalizar editando app_settings.sale_price_types).
comment on function public.resolve_product_price(uuid, uuid) is
  'Devuelve el precio efectivo para (producto, cliente) según el tier '
  'del cliente. Si el cliente no tiene tier o el producto no tiene el '
  'tier configurado, cae al precio base.';

-- =====================================================
-- 5) Grants
-- =====================================================

grant select, insert, update, delete on public.cash_register_movements to authenticated;
grant select, insert, update, delete on public.petty_cash_sessions to authenticated;
grant select, insert, update, delete on public.petty_cash_movements to authenticated;
grant select, insert, update, delete on public.petty_cash_categories to authenticated;

commit;
