-- ============================================================================
-- 20261101_104_bloquear_autodesactivacion.sql
--
-- Problema (1 nov 2026, dos negocios distintos):
--   Un admin entró a Usuarios (o Sucursales) y, sin querer, desactivó su
--   PROPIA asignación a su única sucursal. Quedó en "Sin sucursal" y ya no
--   pudo reactivarse: la RLS de `users_branches` exige
--   `current_company_id()`, que sale de `current_branch_id()`, que solo mira
--   asignaciones activas. Hubo que reactivarlo a mano en el SQL Editor.
--   El botón rojo "Desactivar usuario" sobre su propia fila deja fuera al
--   admin de la misma forma (profiles.is_active = false).
--
-- Fix:
--   Disparadores que impiden que el usuario conectado se deje sin acceso:
--     1) desactivar su ÚLTIMA asignación activa en `users_branches`;
--     2) desactivar su propio perfil en `profiles`.
--   Solo actúan cuando el cambio lo hace el mismo usuario (auth.uid()).
--   Desactivar a OTROS usuarios sigue igual. Desde el SQL Editor
--   (auth.uid() es null) tampoco bloquean, para poder corregir a mano.
--
-- La base es compartida con shop-plus: la protección aplica a las dos apps.
-- No cambia RPC, policies ni datos. No hace falta publicar otra versión de
-- la app (la versión nueva solo muestra el mensaje más limpio).
--
-- Idempotente. Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

begin;

-- 1) users_branches: no quitarse la última sucursal activa propia.
create or replace function public.prevent_self_branch_lockout()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and old.user_id = auth.uid()
     and old.is_active
     and not new.is_active
     and not exists (
       select 1
       from public.users_branches ub
       where ub.user_id = old.user_id
         and ub.id <> old.id
         and ub.is_active
     )
  then
    raise exception
      'No puedes desactivar tu única sucursal activa: perderías el acceso. '
      'Pide a otro administrador que lo haga o asígnate otra sucursal primero.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_users_branches_prevent_self_lockout
  on public.users_branches;
create trigger trg_users_branches_prevent_self_lockout
before update of is_active on public.users_branches
for each row execute function public.prevent_self_branch_lockout();

-- 2) profiles: no desactivar el propio usuario.
create or replace function public.prevent_self_profile_deactivation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and old.id = auth.uid()
     and old.is_active
     and not new.is_active
  then
    raise exception
      'No puedes desactivar tu propio usuario: perderías el acceso. '
      'Pide a otro administrador que lo haga.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_prevent_self_deactivation
  on public.profiles;
create trigger trg_profiles_prevent_self_deactivation
before update of is_active on public.profiles
for each row execute function public.prevent_self_profile_deactivation();

commit;

-- ----------------------------------------------------------------------------
-- VERIFICACIÓN (solo lectura): deben salir las dos filas.
-- ----------------------------------------------------------------------------
-- select tgname, tgrelid::regclass
-- from pg_trigger
-- where tgname in (
--   'trg_users_branches_prevent_self_lockout',
--   'trg_profiles_prevent_self_deactivation'
-- );
