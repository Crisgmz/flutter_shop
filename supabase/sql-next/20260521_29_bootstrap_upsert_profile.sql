-- Fix: bootstrap_new_company choca con el trigger on_auth_user_created.
--
-- Problema:
--   El trigger handle_auth_user_upsert() inserta un profile con role='cashier'
--   apenas se crea la fila en auth.users. Cuando el flujo de signup público
--   después llama a bootstrap_new_company, el RPC encontraba ese profile y
--   abortaba con "Este usuario ya tiene un perfil".
--
-- Solución:
--   El RPC ahora hace UPSERT del profile: si ya existe (creado por el trigger),
--   lo PROMUEVE a 'admin' y completa el resto del bootstrap (company, sucursal,
--   users_branches, app_settings). Solo aborta si el usuario ya tiene company
--   asignada en users_branches (señal real de que ya completó el bootstrap).

begin;

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

  if coalesce(trim(p_company_name), '') = '' then
    raise exception 'El nombre de la empresa es requerido.'
      using errcode = '22023';
  end if;

  -- Idempotencia real: si ya tiene users_branches activos, ya completó el
  -- bootstrap antes. El profile solo (creado por el trigger del signup) NO
  -- cuenta como bootstrap completado.
  if exists (
    select 1
    from public.users_branches ub
    join public.branches b on b.id = ub.branch_id
    where ub.user_id = v_user_id
      and ub.is_active
      and b.company_id is not null
  ) then
    raise exception 'Este usuario ya pertenece a una empresa. Usa /usuarios para invitar empleados.'
      using errcode = '23505';
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

  -- 3) Profile: UPSERT para convivir con el trigger handle_auth_user_upsert().
  --    Si el trigger ya creó la fila con role='cashier', la promovemos a admin.
  insert into public.profiles (id, email, full_name, role, phone, is_active)
  values (
    v_user_id,
    v_email,
    coalesce(nullif(trim(p_full_name), ''), v_email, ''),
    'admin'::public.app_role,
    p_phone,
    true
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    role = 'admin'::public.app_role,
    phone = coalesce(excluded.phone, public.profiles.phone),
    is_active = true;

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
