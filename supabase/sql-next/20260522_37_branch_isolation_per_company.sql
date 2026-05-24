-- Fix: leak de sucursales entre empresas (multi-tenant).
--
-- Síntoma:
--   El admin de una empresa ve sucursales (branches) de otras empresas en
--   /sucursales y en los selectores de "Asignar sucursal" al editar
--   usuarios. Mismo tipo de bug que tuvimos con profiles y users_branches
--   (migration 36), pero esta vez en la tabla branches.
--
-- Causa raíz:
--   El RLS original de `branches_select` permite al admin ver TODAS las
--   filas:
--     using (public.is_admin() or public.has_branch_access(id))
--
--   En multi-tenant, eso filtra sucursales entre empresas porque
--   `is_admin()` no chequea company.
--
-- Fix:
--   Endurecer las policies SELECT y WRITE para que el admin solo
--   alcance branches cuya company_id coincida con su current_company_id().
--   El usuario regular sigue viendo solo las branches a las que está
--   asignado (has_branch_access).
--
-- Idempotente.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) branches: el admin solo ve / edita branches de su company.
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists branches_select on public.branches;
create policy branches_select
on public.branches
for select
to authenticated
using (
  public.has_branch_access(id)
  or (
    public.is_admin()
    and company_id = public.current_company_id()
  )
);

drop policy if exists branches_write on public.branches;
create policy branches_write
on public.branches
for all
to authenticated
using (
  public.is_admin()
  and company_id = public.current_company_id()
)
with check (
  public.is_admin()
  and company_id = public.current_company_id()
);

commit;
