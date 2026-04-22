-- Shop+ RD
-- Helper para cambiar sucursal actual por usuario autenticado.
-- Ejecutar despues de 01_schema.sql y 03_reports_views.sql.

begin;

create or replace function public.set_current_branch(target_branch_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.';
  end if;

  if not exists (
    select 1
    from public.users_branches ub
    where ub.user_id = v_user_id
      and ub.branch_id = target_branch_id
      and ub.is_active
  ) then
    raise exception 'La sucursal no está asignada al usuario.';
  end if;

  update public.users_branches
  set is_default = false
  where user_id = v_user_id
    and is_active
    and is_default;

  update public.users_branches
  set is_default = true
  where user_id = v_user_id
    and branch_id = target_branch_id
    and is_active;

  return target_branch_id;
end;
$$;

grant execute on function public.set_current_branch(uuid) to authenticated;

commit;
