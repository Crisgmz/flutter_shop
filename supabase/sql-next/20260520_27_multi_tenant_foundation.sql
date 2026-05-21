-- Fase 1 — Multi-tenant foundation.
--
-- Objetivo: pasar el sistema de single-tenant (un solo negocio implícito) a
-- multi-tenant con aislamiento lógico vía RLS. ESTA fase NO cambia el
-- código Dart todavía — el negocio existente queda como "company legacy" y
-- todo lo demás sigue funcionando exactamente igual.
--
-- Pasos:
--   1) Nueva tabla `companies`.
--   2) Backfill: una "company legacy" con los datos actuales de
--      `app_settings` (nombre, RNC). UUID fijo para que sea predecible.
--   3) `branches.company_id` NOT NULL → FK a companies.
--   4) `app_settings.company_id` con UNIQUE (una fila por empresa).
--   5) Helpers `current_company_id()` y `has_company_access(uuid)`.
--   6) RLS sobre `companies` (SELECT/INSERT/UPDATE/DELETE).
--
-- Aislamiento futuro: como TODAS las tablas operativas (sales, products,
-- payments, etc.) ya filtran por sucursal vía `has_branch_access`, y cada
-- sucursal pertenece a UNA company, el aislamiento entre empresas queda
-- garantizado siempre y cuando los nuevos usuarios solo se asignen a
-- sucursales de SU empresa (cosa que la Fase 2 — onboarding — va a hacer
-- atómicamente).
--
-- Reversibilidad: hacer BACKUP antes de correr. `company_id NOT NULL` es
-- difícil de revertir limpiamente. Idempotente, pero no idempotente al
-- 100% (la marca NOT NULL solo se aplica si la columna no la tiene).

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Tabla companies
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tax_id text,
  slug text unique,
  owner_id uuid references auth.users(id) on delete set null,
  plan text not null default 'free',
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_companies_owner on public.companies(owner_id);
create index if not exists idx_companies_active
  on public.companies(is_active) where is_active;

-- Trigger updated_at — reutiliza la convención existente.
drop trigger if exists trg_companies_updated_at on public.companies;
create trigger trg_companies_updated_at
before update on public.companies
for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Legacy company (negocio que ya existe)
--    UUID fijo y predecible para que los scripts y debug sean fáciles.
-- ─────────────────────────────────────────────────────────────────────────

insert into public.companies (id, name, tax_id, slug, plan, is_active)
select
  '00000000-0000-0000-0000-000000000001'::uuid,
  coalesce(nullif(trim(s.company_name), ''), 'Mi Negocio'),
  s.company_tax_id,
  'legacy',
  'legacy',
  true
from public.app_settings s
where s.id = 1
on conflict (id) do nothing;

-- Si no había fila en app_settings (DB nueva), crear company default igual.
insert into public.companies (id, name, slug, plan)
values (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'Mi Negocio',
  'legacy',
  'legacy'
)
on conflict (id) do nothing;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) branches.company_id
-- ─────────────────────────────────────────────────────────────────────────

alter table public.branches
  add column if not exists company_id uuid
  references public.companies(id) on delete restrict;

-- Backfill: todas las sucursales existentes → company legacy.
update public.branches
set company_id = '00000000-0000-0000-0000-000000000001'::uuid
where company_id is null;

-- NOT NULL (si la columna ya estaba NOT NULL, no falla porque ya cumple).
alter table public.branches
  alter column company_id set not null;

create index if not exists idx_branches_company on public.branches(company_id);

-- ─────────────────────────────────────────────────────────────────────────
-- 4) app_settings.company_id
--    PK existente es `id` (singleton id=1). Agregamos company_id con
--    UNIQUE para que cada empresa tenga UNA fila de settings.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.app_settings
  add column if not exists company_id uuid
  references public.companies(id) on delete cascade;

update public.app_settings
set company_id = '00000000-0000-0000-0000-000000000001'::uuid
where id = 1 and company_id is null;

-- UNIQUE: una fila por empresa (cuando company_id no es null).
create unique index if not exists app_settings_company_unique
  on public.app_settings(company_id)
  where company_id is not null;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) Helpers RLS
-- ─────────────────────────────────────────────────────────────────────────

-- current_company_id(): empresa de la sucursal activa del usuario.
create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select b.company_id
  from public.branches b
  where b.id = public.current_branch_id()
  limit 1;
$$;

grant execute on function public.current_company_id() to authenticated;

-- has_company_access(uuid): el usuario tiene alguna sucursal activa de esa
-- empresa O es owner de la empresa.
create or replace function public.has_company_access(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users_branches ub
    join public.branches b on b.id = ub.branch_id
    join public.profiles p on p.id = ub.user_id
    where ub.user_id = auth.uid()
      and ub.is_active
      and p.is_active
      and b.company_id = p_company_id
  ) or exists (
    select 1 from public.companies c
    where c.id = p_company_id and c.owner_id = auth.uid()
  );
$$;

grant execute on function public.has_company_access(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 6) RLS sobre companies
-- ─────────────────────────────────────────────────────────────────────────

alter table public.companies enable row level security;

-- SELECT: el usuario ve la(s) empresa(s) a las que pertenece.
drop policy if exists companies_select on public.companies;
create policy companies_select on public.companies
  for select to authenticated
  using (public.has_company_access(id));

-- INSERT: cualquier usuario autenticado puede crear UNA empresa de la cual
-- es owner. Lo usa el flujo de onboarding (Fase 2).
drop policy if exists companies_insert on public.companies;
create policy companies_insert on public.companies
  for insert to authenticated
  with check (owner_id = auth.uid());

-- UPDATE: el owner puede modificar su empresa. Admins del sistema también.
drop policy if exists companies_update on public.companies;
create policy companies_update on public.companies
  for update to authenticated
  using (owner_id = auth.uid() or public.is_admin())
  with check (owner_id = auth.uid() or public.is_admin());

-- DELETE: solo owner. Cuidado: cascada elimina app_settings (intencional)
-- pero `branches` es ON DELETE RESTRICT — no se puede borrar empresa con
-- sucursales adentro. El owner debe borrar sucursales primero.
drop policy if exists companies_delete on public.companies;
create policy companies_delete on public.companies
  for delete to authenticated
  using (owner_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────
-- 7) Asignar owner_id a la company legacy
--    Toma el primer admin existente como owner. Si no hay, queda null
--    (un super-admin futuro lo seteará manualmente).
-- ─────────────────────────────────────────────────────────────────────────

update public.companies
set owner_id = (
  select p.id from public.profiles p
  where p.role = 'admin'::public.app_role
    and p.is_active
  order by p.created_at asc
  limit 1
)
where id = '00000000-0000-0000-0000-000000000001'::uuid
  and owner_id is null;

commit;
