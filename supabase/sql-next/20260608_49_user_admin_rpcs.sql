-- ============================================================================
-- RPCs de administración de usuarios (cambiar correo, contraseña y eliminar)
-- ============================================================================
-- Igual que create_employee_user, estos manipulan auth.users directamente con
-- security definer porque la clave anónima del cliente no puede tocar auth.
-- Cada función verifica que el llamador sea admin/supervisor y que comparta
-- empresa (al menos una sucursal) con el usuario objetivo.
--
-- Ejecutar en el SQL Editor de Supabase.
-- Requiere pgcrypto (ya instalado en Supabase).
-- ============================================================================

-- Guard: ¿puede el llamador gestionar a p_user_id?
-- Admin/supervisor + comparten al menos una sucursal (misma empresa).
create or replace function public.can_manage_employee(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select
    exists (
      select 1 from public.profiles
       where id = auth.uid()
         and role in ('admin', 'supervisor')
    )
    and exists (
      select 1
        from public.users_branches ub_target
        join public.users_branches ub_caller
          on ub_caller.branch_id = ub_target.branch_id
       where ub_target.user_id = p_user_id
         and ub_caller.user_id = auth.uid()
    );
$$;

-- ----------------------------------------------------------------------------
-- 1) Cambiar el correo de un empleado
-- ----------------------------------------------------------------------------
create or replace function public.update_employee_email(
  p_user_id uuid,
  p_email   text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_email text := lower(trim(p_email));
begin
  if not public.can_manage_employee(p_user_id) then
    raise exception 'Sin permisos para modificar este usuario.'
      using errcode = '42501';
  end if;

  if v_email is null or v_email = '' or position('@' in v_email) = 0 then
    raise exception 'El correo no es válido.' using errcode = '22023';
  end if;

  if exists (
    select 1 from auth.users
     where email = v_email and id <> p_user_id
  ) then
    raise exception 'Ya existe un usuario con ese correo.'
      using errcode = '23505';
  end if;

  update auth.users set
    email                  = v_email,
    email_confirmed_at     = coalesce(email_confirmed_at, now()),
    email_change           = '',
    email_change_token_new = '',
    updated_at             = now()
  where id = p_user_id;

  if not found then
    raise exception 'Usuario no encontrado.' using errcode = 'P0002';
  end if;

  update public.profiles set email = v_email where id = p_user_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2) Cambiar la contraseña de un empleado
-- ----------------------------------------------------------------------------
create or replace function public.set_employee_password(
  p_user_id  uuid,
  p_password text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  if not public.can_manage_employee(p_user_id) then
    raise exception 'Sin permisos para modificar este usuario.'
      using errcode = '42501';
  end if;

  if p_password is null or length(p_password) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres.'
      using errcode = '22023';
  end if;

  update auth.users set
    encrypted_password = crypt(p_password, gen_salt('bf')),
    updated_at         = now()
  where id = p_user_id;

  if not found then
    raise exception 'Usuario no encontrado.' using errcode = 'P0002';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) Eliminar un empleado
-- ----------------------------------------------------------------------------
-- Borra de auth.users; el ON DELETE CASCADE elimina su profile y sus
-- users_branches. No permite que el usuario se borre a sí mismo.
create or replace function public.delete_employee_user(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.can_manage_employee(p_user_id) then
    raise exception 'Sin permisos para eliminar este usuario.'
      using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'No puedes eliminar tu propio usuario.'
      using errcode = '22023';
  end if;

  delete from auth.users where id = p_user_id;

  if not found then
    raise exception 'Usuario no encontrado.' using errcode = 'P0002';
  end if;
end;
$$;

grant execute on function public.can_manage_employee(uuid) to authenticated;
grant execute on function public.update_employee_email(uuid, text) to authenticated;
grant execute on function public.set_employee_password(uuid, text) to authenticated;
grant execute on function public.delete_employee_user(uuid) to authenticated;

notify pgrst, 'reload schema';
