-- Cajas físicas/lógicas con asignación de usuarios.
--
-- Antes: cada cajero abría su propia sesión (cash_sessions). El sistema
-- asumía que cajero = caja. No había concepto de "caja con nombre".
--
-- Ahora: la sucursal tiene N cajas configurables (cash_registers). Cada
-- caja puede tener usuarios asignados (cash_register_users). Para abrir
-- una sesión sobre una caja, el usuario tiene que estar asignado.
--
-- Backwards-compat: cash_sessions.cash_register_id es NULLABLE. Sesiones
-- viejas no tienen caja asignada (vacío). El cliente puede mostrar
-- "Caja sin asignar" para esos casos. El nuevo openSession RPC requiere
-- cash_register_id.
--
-- Idempotente: todas las creaciones usan `if not exists`; las policies
-- se dropean primero.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Tabla cash_registers (catálogo de cajas por sucursal)
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.cash_registers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

create unique index if not exists cash_registers_name_per_branch
  on public.cash_registers (branch_id, lower(name))
  where is_active;

-- Trigger de updated_at + audit (set_updated_at y set_audit_fields ya existen).
drop trigger if exists trg_cash_registers_updated_at on public.cash_registers;
create trigger trg_cash_registers_updated_at
before update on public.cash_registers
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_registers_audit_fields on public.cash_registers;
create trigger trg_cash_registers_audit_fields
before insert or update on public.cash_registers
for each row execute function public.set_audit_fields();

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Tabla cash_register_users (asignación de usuarios a cajas)
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.cash_register_users (
  cash_register_id uuid not null references public.cash_registers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (cash_register_id, user_id)
);

-- ─────────────────────────────────────────────────────────────────────────
-- 3) cash_sessions.cash_register_id (relación 1:N)
-- ─────────────────────────────────────────────────────────────────────────

alter table public.cash_sessions
  add column if not exists cash_register_id uuid
    references public.cash_registers(id);

-- ─────────────────────────────────────────────────────────────────────────
-- 4) RLS
-- ─────────────────────────────────────────────────────────────────────────

alter table public.cash_registers enable row level security;
alter table public.cash_register_users enable row level security;

-- cash_registers: SELECT a todos los del branch, INSERT/UPDATE/DELETE solo admin/supervisor.
drop policy if exists cash_registers_select on public.cash_registers;
create policy cash_registers_select on public.cash_registers
  for select to authenticated
  using (public.has_branch_access(branch_id));

drop policy if exists cash_registers_insert on public.cash_registers;
create policy cash_registers_insert on public.cash_registers
  for insert to authenticated
  with check (
    public.has_branch_access(branch_id)
    and (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
  );

drop policy if exists cash_registers_update on public.cash_registers;
create policy cash_registers_update on public.cash_registers
  for update to authenticated
  using (
    public.has_branch_access(branch_id)
    and (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
  )
  with check (
    public.has_branch_access(branch_id)
    and (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
  );

drop policy if exists cash_registers_delete on public.cash_registers;
create policy cash_registers_delete on public.cash_registers
  for delete to authenticated
  using (
    public.has_branch_access(branch_id)
    and (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
  );

-- cash_register_users: SELECT a los del branch, INSERT/DELETE solo admin/supervisor del branch.
drop policy if exists cash_register_users_select on public.cash_register_users;
create policy cash_register_users_select on public.cash_register_users
  for select to authenticated
  using (
    exists (
      select 1 from public.cash_registers cr
      where cr.id = cash_register_id
        and public.has_branch_access(cr.branch_id)
    )
  );

drop policy if exists cash_register_users_insert on public.cash_register_users;
create policy cash_register_users_insert on public.cash_register_users
  for insert to authenticated
  with check (
    (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
    and exists (
      select 1 from public.cash_registers cr
      where cr.id = cash_register_id
        and public.has_branch_access(cr.branch_id)
    )
  );

drop policy if exists cash_register_users_delete on public.cash_register_users;
create policy cash_register_users_delete on public.cash_register_users
  for delete to authenticated
  using (
    (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
    and exists (
      select 1 from public.cash_registers cr
      where cr.id = cash_register_id
        and public.has_branch_access(cr.branch_id)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────
-- 5) RPC open_cash_session_for_register
--
--    Crea una cash_session apuntando a cash_register_id, validando que el
--    usuario actual esté asignado a esa caja. El cliente lo invoca en
--    lugar del INSERT directo cuando hay cajas configuradas.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.open_cash_session_for_register(
  p_cash_register_id uuid,
  p_opening_amount numeric,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid;
  v_session_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida.' using errcode = '28000';
  end if;
  if p_cash_register_id is null then
    raise exception 'p_cash_register_id es requerido.' using errcode = '22023';
  end if;
  if p_opening_amount is null or p_opening_amount < 0 then
    raise exception 'Monto de apertura inválido.' using errcode = '22023';
  end if;

  -- La caja existe + el usuario tiene acceso a la sucursal.
  select branch_id into v_branch_id
  from public.cash_registers
  where id = p_cash_register_id and is_active;

  if v_branch_id is null then
    raise exception 'Caja no encontrada o inactiva.' using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esta sucursal.' using errcode = '42501';
  end if;

  -- El usuario está asignado a la caja.
  if not exists (
    select 1 from public.cash_register_users
    where cash_register_id = p_cash_register_id
      and user_id = v_user_id
      and is_active
  ) then
    raise exception 'No tenés acceso a esta caja.' using errcode = '42501';
  end if;

  -- No abrir otra sesión si el usuario ya tiene una abierta en esta sucursal
  -- (regla del migration 26: una sesión abierta por (branch_id, opened_by)).
  if exists (
    select 1 from public.cash_sessions
    where branch_id = v_branch_id
      and opened_by = v_user_id
      and status = 'open'
  ) then
    raise exception 'Ya tenés una sesión de caja abierta en esta sucursal.'
      using errcode = '23505';
  end if;

  insert into public.cash_sessions (
    branch_id, opened_by, status, opened_at,
    opening_amount, expected_amount, notes, cash_register_id
  ) values (
    v_branch_id, v_user_id, 'open', timezone('utc', now()),
    round(p_opening_amount::numeric, 2), round(p_opening_amount::numeric, 2),
    nullif(trim(coalesce(p_notes, '')), ''), p_cash_register_id
  )
  returning id into v_session_id;

  return v_session_id;
end;
$$;

grant execute on function public.open_cash_session_for_register(uuid, numeric, text)
  to authenticated;

commit;
