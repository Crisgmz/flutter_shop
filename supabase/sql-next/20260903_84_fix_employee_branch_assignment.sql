-- ============================================================================
-- Migración 84 — Empleados que se crean pero no aparecen en el listado
-- ============================================================================
-- Síntoma reportado: se crea un usuario nuevo, el proceso termina bien, pero
-- el "Listado de usuarios" se queda en los mismos de siempre. Parece un tope
-- de 5 usuarios; no lo es.
--
-- Causa:
--   El RLS de `profiles` (ver el bloque de aislamiento multi-empresa) solo deja
--   ver un perfil si tiene una fila en `users_branches` con `is_active = true`
--   cuya sucursal pertenezca a `current_company_id()`. Un empleado sin esa
--   membership existe en la base pero es INVISIBLE para el admin — no se puede
--   listar, ni editar, ni desactivar, ni asignar.
--
--   `create_employee_user` asignaba la sucursal `is_default` DEL ADMIN QUE
--   CREA, ignorando en cuál está trabajando. En un admin con varias sucursales
--   (o varias empresas) el empleado nuevo caía en la sucursal equivocada y,
--   si esa era de otra empresa, desaparecía del listado al instante.
--
-- Qué hace esta migración:
--   1. `create_employee_user` asigna la sucursal ACTIVA (`current_branch_id()`)
--      y solo cae a la default del creador si no hay sucursal activa.
--   2. Agrega `list_orphan_employees()` para encontrar los empleados que ya
--      quedaron huérfanos, y `attach_employee_to_branch()` para repararlos.
--      Ambas son SECURITY DEFINER y solo para admin/supervisor: son la única
--      forma de rescatar un perfil que el RLS esconde.
--
-- Idempotente.
-- ============================================================================

begin;

-- ── 1) create_employee_user: usar la sucursal activa ────────────────────────
create or replace function public.create_employee_user(
  p_email         text,
  p_password      text,
  p_full_name     text,
  p_role          text,
  p_phone         text default null,
  p_employee_code text default null,
  p_job_title     text default null,
  p_notes         text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_caller_id   uuid := auth.uid();
  v_caller_role text;
  v_branch_id   uuid;
  v_user_id     uuid := gen_random_uuid();
  v_email       text := lower(trim(p_email));
begin
  select role::text into v_caller_role
    from public.profiles
   where id = v_caller_id;

  if v_caller_role not in ('admin', 'supervisor') then
    raise exception 'Sin permisos para crear usuarios.'
      using errcode = '42501';
  end if;

  -- La sucursal en la que el admin está trabajando AHORA. Es la que ve en
  -- pantalla, así que es donde espera que aparezca el empleado nuevo.
  v_branch_id := public.current_branch_id();

  -- Sin sucursal activa (sesión recién abierta, contexto no seteado) se cae a
  -- la default del creador, que es el comportamiento anterior.
  if v_branch_id is null then
    select branch_id into v_branch_id
      from public.users_branches
     where user_id   = v_caller_id
       and is_default = true
       and is_active  = true
     limit 1;
  end if;

  -- Último recurso: cualquier sucursal activa suya.
  if v_branch_id is null then
    select branch_id into v_branch_id
      from public.users_branches
     where user_id  = v_caller_id
       and is_active = true
     order by created_at
     limit 1;
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal activa asignada al administrador.'
      using errcode = '22023';
  end if;

  -- El creador tiene que poder ver la sucursal donde va a meter al empleado.
  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a la sucursal de destino.'
      using errcode = '42501';
  end if;

  if v_email is null or v_email = '' then
    raise exception 'El email es requerido.' using errcode = '22023';
  end if;
  if p_password is null or length(p_password) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres.'
      using errcode = '22023';
  end if;
  if p_full_name is null or trim(p_full_name) = '' then
    raise exception 'El nombre completo es requerido.' using errcode = '22023';
  end if;
  if p_role not in ('admin', 'supervisor', 'cashier', 'accountant') then
    raise exception 'Rol no válido: %', p_role using errcode = '22023';
  end if;

  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Ya existe un usuario con ese email.'
      using errcode = '23505';
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, raw_app_meta_data,
    is_super_admin, created_at, updated_at, confirmation_token,
    recovery_token, email_change_token_new, email_change, is_sso_user
  ) values (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    jsonb_build_object('full_name', trim(p_full_name), 'role', p_role),
    '{"provider":"email","providers":["email"]}'::jsonb,
    false,
    now(),
    now(),
    '', '', '', '',
    false
  );

  -- El trigger on_auth_user_created crea el perfil automáticamente.
  update public.profiles set
    full_name     = trim(p_full_name),
    role          = p_role::public.app_role,
    phone         = nullif(trim(coalesce(p_phone, '')), ''),
    employee_code = nullif(trim(coalesce(p_employee_code, '')), ''),
    job_title     = nullif(trim(coalesce(p_job_title, '')), ''),
    notes         = nullif(trim(coalesce(p_notes, '')), ''),
    is_active     = true
  where id = v_user_id;

  insert into public.users_branches (
    user_id, branch_id, role_override,
    is_default, is_active, created_by, updated_by
  ) values (
    v_user_id, v_branch_id, p_role::public.app_role,
    true, true, v_caller_id, v_caller_id
  )
  on conflict (user_id, branch_id) do update set
    role_override = excluded.role_override,
    is_default    = true,
    is_active     = true,
    updated_by    = v_caller_id;

  -- Si la membership no quedó, el empleado sería invisible por RLS: mejor
  -- fallar acá y revertir que dejar un usuario fantasma.
  if not exists (
    select 1 from public.users_branches
     where user_id = v_user_id and branch_id = v_branch_id and is_active
  ) then
    raise exception 'No se pudo asignar el empleado a la sucursal.'
      using errcode = '23514';
  end if;

  return v_user_id;
end;
$$;

grant execute on function public.create_employee_user(
  text, text, text, text, text, text, text, text
) to authenticated;

-- ── 2) Diagnóstico: empleados huérfanos ─────────────────────────────────────
-- Perfiles sin ninguna membership activa en una sucursal de la empresa actual.
-- Son exactamente los que "se crearon pero no salen en el listado". SECURITY
-- DEFINER porque el RLS de `profiles` es justamente lo que los esconde.
create or replace function public.list_orphan_employees()
returns table (
  id            uuid,
  full_name     text,
  email         text,
  role          text,
  is_active     boolean,
  created_at    timestamptz,
  memberships   integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin()
     and public.current_user_role() <> 'supervisor'::public.app_role then
    raise exception 'Solo admin o supervisor pueden ver empleados sin sucursal.'
      using errcode = '42501';
  end if;

  return query
  select
    p.id,
    p.full_name,
    p.email,
    p.role::text,
    p.is_active,
    p.created_at,
    (select count(*)::integer
       from public.users_branches ub
      where ub.user_id = p.id)
  from public.profiles p
  where not exists (
    select 1
    from public.users_branches ub
    join public.branches b on b.id = ub.branch_id
    where ub.user_id = p.id
      and ub.is_active
      and b.company_id = public.current_company_id()
  )
  -- Un perfil de OTRA empresa tampoco debe salir acá: solo los que no tienen
  -- ninguna sucursal en absoluto (los verdaderamente huérfanos).
  and not exists (
    select 1
    from public.users_branches ub
    where ub.user_id = p.id
      and ub.is_active
  )
  order by p.created_at desc;
end;
$$;

grant execute on function public.list_orphan_employees() to authenticated;

-- ── 3) Reparación: adjuntar un empleado huérfano a una sucursal ─────────────
create or replace function public.attach_employee_to_branch(
  p_user_id   uuid,
  p_branch_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_branch_id uuid := coalesce(p_branch_id, public.current_branch_id());
  v_role      public.app_role;
begin
  if not public.is_admin()
     and public.current_user_role() <> 'supervisor'::public.app_role then
    raise exception 'Solo admin o supervisor pueden asignar sucursales.'
      using errcode = '42501';
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal de destino.' using errcode = '22023';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esa sucursal.' using errcode = '42501';
  end if;

  select role into v_role from public.profiles where id = p_user_id;
  if v_role is null then
    raise exception 'Empleado no encontrado.' using errcode = 'P0002';
  end if;

  -- Solo se rescatan huérfanos: un empleado que ya tiene sucursal activa
  -- pertenece a alguna empresa y moverlo desde acá sería robárselo.
  if exists (
    select 1 from public.users_branches
     where user_id = p_user_id and is_active
  ) then
    raise exception 'Ese empleado ya está asignado a una sucursal.'
      using errcode = '22023';
  end if;

  insert into public.users_branches (
    user_id, branch_id, role_override,
    is_default, is_active, created_by, updated_by
  ) values (
    p_user_id, v_branch_id, v_role,
    true, true, v_caller_id, v_caller_id
  )
  on conflict (user_id, branch_id) do update set
    is_default = true,
    is_active  = true,
    updated_by = v_caller_id;
end;
$$;

grant execute on function public.attach_employee_to_branch(uuid, uuid)
  to authenticated;

commit;

notify pgrst, 'reload schema';
