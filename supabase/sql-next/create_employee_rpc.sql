-- RPC para crear empleados directamente en auth.users sin Edge Function.
-- Requiere pgcrypto (ya instalado en Supabase).
-- Ejecutar en Supabase SQL Editor.

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
  -- Verificar permisos del llamador
  select role::text into v_caller_role
    from public.profiles
   where id = v_caller_id;

  if v_caller_role not in ('admin', 'supervisor') then
    raise exception 'Sin permisos para crear usuarios.'
      using errcode = '42501';
  end if;

  -- Obtener sucursal activa del llamador
  select branch_id into v_branch_id
    from public.users_branches
   where user_id   = v_caller_id
     and is_default = true
     and is_active  = true
   limit 1;

  if v_branch_id is null then
    raise exception 'No hay sucursal activa asignada al administrador.'
      using errcode = '22023';
  end if;

  -- Validaciones básicas
  if v_email is null or v_email = '' then
    raise exception 'El email es requerido.' using errcode = '22023';
  end if;
  if p_password is null or length(p_password) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres.' using errcode = '22023';
  end if;
  if p_full_name is null or trim(p_full_name) = '' then
    raise exception 'El nombre completo es requerido.' using errcode = '22023';
  end if;
  if p_role not in ('admin', 'supervisor', 'cashier', 'accountant') then
    raise exception 'Rol no válido: %', p_role using errcode = '22023';
  end if;

  -- Verificar email único
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Ya existe un usuario con ese email.' using errcode = '23505';
  end if;

  -- Insertar en auth.users (login inmediato, sin verificación de email)
  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_user_meta_data,
    raw_app_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    is_sso_user
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
  -- Actualizamos los campos extra que el trigger no cubre.
  update public.profiles set
    full_name     = trim(p_full_name),
    role          = p_role::public.app_role,
    phone         = nullif(trim(coalesce(p_phone, '')), ''),
    employee_code = nullif(trim(coalesce(p_employee_code, '')), ''),
    job_title     = nullif(trim(coalesce(p_job_title, '')), ''),
    is_active     = true
  where id = v_user_id;

  -- Asignar a la sucursal del administrador
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

  return v_user_id;
end;
$$;

grant execute on function public.create_employee_user(text, text, text, text, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';
