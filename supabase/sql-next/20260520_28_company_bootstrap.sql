-- Fase 2 — Signup público + onboarding atómico.
--
-- Cambios:
--   1) `app_settings.id` deja de ser singleton (id=1). Se convierte en
--      auto-increment vía sequence. La fila legacy mantiene id=1.
--   2) RLS de `app_settings` se endurece: cada usuario solo ve / edita la
--      fila de SU empresa (via `has_company_access`).
--   3) Nuevo RPC `bootstrap_new_company`: crea atómicamente company +
--      sucursal + profile (rol admin) + users_branches + app_settings para
--      el usuario recién registrado. SECURITY DEFINER para saltar las RLS
--      durante el bootstrap.
--
-- Idempotente excepto por el ALTER que cambia el default de `id`.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) app_settings.id: drop singleton constraint, usar sequence.
-- ─────────────────────────────────────────────────────────────────────────

-- Buscar el check constraint que ata id=1 y dropearlo. El nombre depende
-- del momento en que se creó la tabla — Postgres lo nombra automáticamente.
do $$
declare
  v_constraint_name text;
begin
  select conname into v_constraint_name
  from pg_constraint
  where conrelid = 'public.app_settings'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%(id = 1)%';

  if v_constraint_name is not null then
    execute format(
      'alter table public.app_settings drop constraint %I',
      v_constraint_name
    );
  end if;
end $$;

-- Sequence asociada a la columna id.
create sequence if not exists public.app_settings_id_seq
  owned by public.app_settings.id;

-- Avanzar la sequence más allá del máximo actual.
select setval(
  'public.app_settings_id_seq',
  greatest((select coalesce(max(id), 0) from public.app_settings), 1)
);

alter table public.app_settings
  alter column id set default nextval('public.app_settings_id_seq');

-- ─────────────────────────────────────────────────────────────────────────
-- 2) RLS multi-tenant sobre app_settings.
--    Cada empresa ve / edita SOLO su fila. La inserción la hace el RPC
--    bootstrap (SECURITY DEFINER), no necesita policy abierta.
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists app_settings_select on public.app_settings;
create policy app_settings_select on public.app_settings
  for select to authenticated
  using (
    company_id is null
    or public.has_company_access(company_id)
  );

drop policy if exists app_settings_update on public.app_settings;
create policy app_settings_update on public.app_settings
  for update to authenticated
  using (
    public.is_admin()
    and (company_id is null or public.has_company_access(company_id))
  )
  with check (
    public.is_admin()
    and (company_id is null or public.has_company_access(company_id))
  );

-- INSERT: lo hace SOLO el RPC bootstrap (SECURITY DEFINER, bypassa RLS) o
-- los admins legacy. Mantener la policy strict.
drop policy if exists app_settings_insert on public.app_settings;
create policy app_settings_insert on public.app_settings
  for insert to authenticated
  with check (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Bootstrap RPC.
--    Lo invoca el usuario inmediatamente después de hacer signUp (cuando
--    todavía no tiene profile ni nada). Crea TODO atómicamente.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.bootstrap_new_company(
  p_company_name text,
  p_branch_name text default 'Sucursal principal',
  p_full_name text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_company_id uuid;
  v_branch_id uuid;
  v_slug text;
  v_branch_code text;
  v_app_settings_id integer;
begin
  if v_user_id is null then
    raise exception 'No autenticado.'
      using errcode = '28000';
  end if;

  -- Idempotencia: si ya tiene profile, falla con mensaje claro.
  if exists (select 1 from public.profiles where id = v_user_id) then
    raise exception 'Este usuario ya tiene un perfil. Usa /usuarios para invitar empleados.'
      using errcode = '23505';
  end if;

  if coalesce(trim(p_company_name), '') = '' then
    raise exception 'El nombre de la empresa es requerido.'
      using errcode = '22023';
  end if;

  -- Email del usuario autenticado.
  select email::text into v_email
  from auth.users
  where id = v_user_id;

  -- Slug único: nombre normalizado + sufijo aleatorio para evitar colisión.
  v_slug := lower(
    regexp_replace(trim(p_company_name), '[^a-zA-Z0-9]+', '-', 'g')
  ) || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);

  -- 1) Empresa nueva, el usuario actual es owner.
  insert into public.companies (name, slug, owner_id, plan, is_active)
  values (trim(p_company_name), v_slug, v_user_id, 'free', true)
  returning id into v_company_id;

  -- 2) Sucursal principal de la empresa. branches.code es global-unique,
  --    derivamos un código predecible del UUID de la empresa.
  v_branch_code := 'B-' || upper(
    substr(replace(v_company_id::text, '-', ''), 1, 8)
  );

  insert into public.branches (
    code, name, is_main, is_active, company_id, created_by, updated_by
  ) values (
    v_branch_code,
    coalesce(nullif(trim(p_branch_name), ''), 'Sucursal principal'),
    true,
    true,
    v_company_id,
    v_user_id,
    v_user_id
  )
  returning id into v_branch_id;

  -- 3) Profile (admin de su empresa).
  insert into public.profiles (id, email, full_name, role, phone, is_active)
  values (
    v_user_id,
    v_email,
    coalesce(nullif(trim(p_full_name), ''), v_email, ''),
    'admin'::public.app_role,
    p_phone,
    true
  );

  -- 4) Linkear usuario a su sucursal default.
  insert into public.users_branches (
    user_id, branch_id, is_default, is_active, created_by, updated_by
  ) values (
    v_user_id, v_branch_id, true, true, v_user_id, v_user_id
  );

  -- 5) app_settings de la empresa (resto de defaults de la tabla aplican).
  insert into public.app_settings (company_name, company_id)
  values (trim(p_company_name), v_company_id)
  returning id into v_app_settings_id;

  return jsonb_build_object(
    'company_id', v_company_id,
    'branch_id', v_branch_id,
    'user_id', v_user_id,
    'app_settings_id', v_app_settings_id
  );
end;
$$;

grant execute on function public.bootstrap_new_company(text, text, text, text)
  to authenticated;

commit;
