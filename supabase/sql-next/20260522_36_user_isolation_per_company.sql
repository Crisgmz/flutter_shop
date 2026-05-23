-- Fix: leak de usuarios entre empresas (multi-tenant).
--
-- Síntoma:
--   En /usuarios, el admin de una empresa ve los usuarios (profiles +
--   users_branches) de OTRAS empresas. Los cajeros y demás roles del
--   sistema aparecen mezclados sin importar a qué company pertenecen.
--
-- Causa raíz:
--   El RLS original de `profiles` y `users_branches` permite a CUALQUIER
--   admin ver todas las filas. Era OK en single-tenant, pero rompe el
--   aislamiento en multi-tenant.
--
--   profiles_select:    using (auth.uid() = id or public.is_admin())
--   users_branches_select: using (public.is_admin() or user_id = auth.uid())
--
-- Fix:
--   Endurecer ambas policies. El admin solo ve users / memberships cuyo
--   usuario tenga al menos una sucursal activa de su company.
--
-- Idempotente.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) profiles: el admin solo ve su propio perfil y los de usuarios de su
--    company (vía users_branches → branches → company_id).
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists profiles_select on public.profiles;
create policy profiles_select
on public.profiles
for select
using (
  auth.uid() = id
  or (
    public.is_admin()
    and exists (
      select 1
      from public.users_branches ub
      join public.branches b on b.id = ub.branch_id
      where ub.user_id = public.profiles.id
        and ub.is_active
        and b.company_id = public.current_company_id()
    )
  )
);

-- INSERT / UPDATE / DELETE quedan como están — el admin se valida igual,
-- pero solo puede modificar profiles que ya pasan el SELECT (RLS aplica).
-- Si querés bloquear UPDATE/DELETE explícitamente, descomentar abajo.

drop policy if exists profiles_update on public.profiles;
create policy profiles_update
on public.profiles
for update
to authenticated
using (
  auth.uid() = id
  or (
    public.is_admin()
    and exists (
      select 1
      from public.users_branches ub
      join public.branches b on b.id = ub.branch_id
      where ub.user_id = public.profiles.id
        and ub.is_active
        and b.company_id = public.current_company_id()
    )
  )
)
with check (
  auth.uid() = id
  or (
    public.is_admin()
    and exists (
      select 1
      from public.users_branches ub
      join public.branches b on b.id = ub.branch_id
      where ub.user_id = public.profiles.id
        and ub.is_active
        and b.company_id = public.current_company_id()
    )
  )
);

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete
on public.profiles
for delete
to authenticated
using (
  public.is_admin()
  and exists (
    select 1
    from public.users_branches ub
    join public.branches b on b.id = ub.branch_id
    where ub.user_id = public.profiles.id
      and ub.is_active
      and b.company_id = public.current_company_id()
  )
);

-- ─────────────────────────────────────────────────────────────────────────
-- 2) users_branches: el admin solo ve memberships en branches de su
--    company. El usuario sigue viendo los suyos.
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists users_branches_select on public.users_branches;
create policy users_branches_select
on public.users_branches
for select
to authenticated
using (
  user_id = auth.uid()
  or (
    public.is_admin()
    and exists (
      select 1
      from public.branches b
      where b.id = public.users_branches.branch_id
        and b.company_id = public.current_company_id()
    )
  )
);

drop policy if exists users_branches_write on public.users_branches;
create policy users_branches_write
on public.users_branches
for all
to authenticated
using (
  public.is_admin()
  and exists (
    select 1
    from public.branches b
    where b.id = public.users_branches.branch_id
      and b.company_id = public.current_company_id()
  )
)
with check (
  public.is_admin()
  and exists (
    select 1
    from public.branches b
    where b.id = public.users_branches.branch_id
      and b.company_id = public.current_company_id()
  )
);

commit;
