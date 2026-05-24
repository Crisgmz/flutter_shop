-- Audit consolidado de aislamiento multi-tenant.
--
-- Después de las migrations 34, 36 y 37 (app_settings, profiles+users_branches,
-- branches), quedaban 4 leaks pendientes detectados en review. Esta migration
-- los cierra todos.
--
-- Severidad de cada bug y fix aplicado:
--
-- 1. fiscal_dgii_reports (CRÍTICO)
--    - No tenía company_id. El UNIQUE(report_type, year, month) era global
--      → solo UNA empresa podía generar el 606 de un mes; las demás bloqueadas.
--    - RLS permitía a cualquier admin/accountant ver TODOS los reportes.
--    - Fix: agregar company_id NOT NULL (backfill desde generated_by → branch
--      → company), cambiar UNIQUE a (company_id, type, year, month), RLS por
--      has_company_access.
--
-- 2. custom_reports (ALTO)
--    - No tenía company_id. `is_shared=true` los hacía visibles entre TODAS
--      las empresas.
--    - Fix: agregar company_id, RLS para que is_shared aplique solo dentro
--      de la company.
--
-- 3. user_permissions (ALTO)
--    - RLS permitía a cualquier admin ver permisos de usuarios de otras
--      empresas (mismo patrón que profiles antes de migration 36).
--    - Fix: condicionar `is_admin()` a que el user tenga sucursales activas
--      en la company del admin.
--
-- 4. app_settings_audit (MEDIO)
--    - RLS abierto a cualquier admin. La tabla no tiene company_id, pero
--      cada fila refiere a un campo de app_settings (que sí tiene company).
--    - Fix: limitar el SELECT a admins cuya company sea la dueña del
--      app_settings auditado, vía la columna changed_by.
--
-- Adicional: vista `vw_isolation_audit_anomalies` para detectar manualmente
-- usuarios con users_branches en múltiples companies (anomalía que
-- saltearía has_branch_access).
--
-- Defensiva: cada bloque se salta si la tabla / columna requerida no existe
-- (idempotente y compatible con DBs en distinto estado).
--
-- Aplicar después de 34, 36 y 37.

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) fiscal_dgii_reports
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'fiscal_dgii_reports'
  ) then
    raise notice 'Salteando fiscal_dgii_reports: tabla no existe.';
    return;
  end if;

  -- 1.1: agregar company_id si falta.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fiscal_dgii_reports'
      and column_name = 'company_id'
  ) then
    execute $sql$
      alter table public.fiscal_dgii_reports
        add column company_id uuid references public.companies(id) on delete cascade
    $sql$;
  end if;

  -- 1.2: backfill desde generated_by → users_branches → branches.company_id.
  execute $sql$
    update public.fiscal_dgii_reports r
       set company_id = (
         select b.company_id
           from public.users_branches ub
           join public.branches b on b.id = ub.branch_id
          where ub.user_id = r.generated_by
            and ub.is_active
            and b.is_active
          order by ub.is_default desc, ub.created_at asc
          limit 1
       )
     where company_id is null
       and generated_by is not null
  $sql$;

  -- 1.3: filas sin generated_by o user huérfano → asignar a la company más
  --      antigua con sucursales activas, o borrar si no hay companies.
  execute $sql$
    update public.fiscal_dgii_reports
       set company_id = (
         select c.id
           from public.companies c
          where c.is_active
            and exists (select 1 from public.branches b
                        where b.company_id = c.id and b.is_active)
          order by c.created_at asc
          limit 1
       )
     where company_id is null
  $sql$;

  execute 'delete from public.fiscal_dgii_reports where company_id is null';

  -- 1.4: NOT NULL.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fiscal_dgii_reports'
      and column_name = 'company_id'
      and is_nullable = 'YES'
  ) then
    execute 'alter table public.fiscal_dgii_reports alter column company_id set not null';
  end if;

  -- 1.5: reemplazar UNIQUE global por una que incluya company_id.
  execute 'alter table public.fiscal_dgii_reports drop constraint if exists fiscal_dgii_reports_report_type_period_year_period_month_key';
  execute 'alter table public.fiscal_dgii_reports drop constraint if exists fiscal_dgii_reports_report_type_year_month_key';
  -- Constraint nueva (idempotente vía drop+add)
  begin
    execute $sql$
      alter table public.fiscal_dgii_reports
        add constraint fiscal_dgii_reports_company_period_unique
        unique (company_id, report_type, period_year, period_month)
    $sql$;
  exception when duplicate_object then null;
  end;

  -- 1.6: RLS basada en has_company_access.
  execute 'drop policy if exists fiscal_dgii_reports_select on public.fiscal_dgii_reports';
  execute $sql$
    create policy fiscal_dgii_reports_select on public.fiscal_dgii_reports
      for select to authenticated
      using (
        public.has_company_access(company_id)
        and (
          public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role
        )
      )
  $sql$;

  execute 'drop policy if exists fiscal_dgii_reports_insert on public.fiscal_dgii_reports';
  execute $sql$
    create policy fiscal_dgii_reports_insert on public.fiscal_dgii_reports
      for insert to authenticated
      with check (
        public.has_company_access(company_id)
        and (
          public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role
        )
      )
  $sql$;

  execute 'drop policy if exists fiscal_dgii_reports_update on public.fiscal_dgii_reports';
  execute $sql$
    create policy fiscal_dgii_reports_update on public.fiscal_dgii_reports
      for update to authenticated
      using (
        public.is_admin()
        and public.has_company_access(company_id)
      )
      with check (
        public.is_admin()
        and public.has_company_access(company_id)
      )
  $sql$;

  execute 'drop policy if exists fiscal_dgii_reports_delete on public.fiscal_dgii_reports';
  execute $sql$
    create policy fiscal_dgii_reports_delete on public.fiscal_dgii_reports
      for delete to authenticated
      using (
        public.is_admin()
        and public.has_company_access(company_id)
      )
  $sql$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) custom_reports
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'custom_reports'
  ) then
    raise notice 'Salteando custom_reports: tabla no existe.';
    return;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'custom_reports'
      and column_name = 'company_id'
  ) then
    execute $sql$
      alter table public.custom_reports
        add column company_id uuid references public.companies(id) on delete cascade
    $sql$;
  end if;

  -- Backfill desde created_by.
  execute $sql$
    update public.custom_reports r
       set company_id = (
         select b.company_id
           from public.users_branches ub
           join public.branches b on b.id = ub.branch_id
          where ub.user_id = r.created_by
            and ub.is_active
            and b.is_active
          order by ub.is_default desc, ub.created_at asc
          limit 1
       )
     where company_id is null
  $sql$;

  -- Fallback: primera company activa.
  execute $sql$
    update public.custom_reports
       set company_id = (
         select c.id from public.companies c
          where c.is_active
          order by c.created_at asc
          limit 1
       )
     where company_id is null
  $sql$;

  execute 'delete from public.custom_reports where company_id is null';

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'custom_reports'
      and column_name = 'company_id'
      and is_nullable = 'YES'
  ) then
    execute 'alter table public.custom_reports alter column company_id set not null';
  end if;

  -- RLS: dueño siempre ve el suyo; is_shared aplica SOLO dentro de la company.
  execute 'drop policy if exists custom_reports_select on public.custom_reports';
  execute $sql$
    create policy custom_reports_select on public.custom_reports
      for select to authenticated
      using (
        created_by = auth.uid()
        or (is_shared = true and public.has_company_access(company_id))
        or (public.is_admin() and public.has_company_access(company_id))
      )
  $sql$;

  execute 'drop policy if exists custom_reports_insert on public.custom_reports';
  execute $sql$
    create policy custom_reports_insert on public.custom_reports
      for insert to authenticated
      with check (
        created_by = auth.uid()
        and public.has_company_access(company_id)
      )
  $sql$;

  execute 'drop policy if exists custom_reports_update on public.custom_reports';
  execute $sql$
    create policy custom_reports_update on public.custom_reports
      for update to authenticated
      using (
        (created_by = auth.uid() or public.is_admin())
        and public.has_company_access(company_id)
      )
      with check (
        (created_by = auth.uid() or public.is_admin())
        and public.has_company_access(company_id)
      )
  $sql$;

  execute 'drop policy if exists custom_reports_delete on public.custom_reports';
  execute $sql$
    create policy custom_reports_delete on public.custom_reports
      for delete to authenticated
      using (
        (created_by = auth.uid() or public.is_admin())
        and public.has_company_access(company_id)
      )
  $sql$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) user_permissions
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'user_permissions'
  ) then
    raise notice 'Salteando user_permissions: tabla no existe.';
    return;
  end if;

  execute 'drop policy if exists user_permissions_select on public.user_permissions';
  execute $sql$
    create policy user_permissions_select on public.user_permissions
      for select to authenticated
      using (
        user_id = auth.uid()
        or (
          public.is_admin()
          and exists (
            select 1
              from public.users_branches ub
              join public.branches b on b.id = ub.branch_id
             where ub.user_id = public.user_permissions.user_id
               and ub.is_active
               and b.company_id = public.current_company_id()
          )
        )
      )
  $sql$;

  execute 'drop policy if exists user_permissions_write on public.user_permissions';
  execute $sql$
    create policy user_permissions_write on public.user_permissions
      for all to authenticated
      using (
        public.is_admin()
        and exists (
          select 1
            from public.users_branches ub
            join public.branches b on b.id = ub.branch_id
           where ub.user_id = public.user_permissions.user_id
             and ub.is_active
             and b.company_id = public.current_company_id()
        )
      )
      with check (
        public.is_admin()
        and exists (
          select 1
            from public.users_branches ub
            join public.branches b on b.id = ub.branch_id
           where ub.user_id = public.user_permissions.user_id
             and ub.is_active
             and b.company_id = public.current_company_id()
        )
      )
  $sql$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) app_settings_audit
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'app_settings_audit'
  ) then
    raise notice 'Salteando app_settings_audit: tabla no existe.';
    return;
  end if;

  -- La tabla no tiene company_id directo, pero changed_by sí relaciona a un
  -- user → company vía users_branches. Eso filtra correctamente.
  execute 'drop policy if exists app_settings_audit_select on public.app_settings_audit';
  execute $sql$
    create policy app_settings_audit_select on public.app_settings_audit
      for select to authenticated
      using (
        public.is_admin()
        and (
          -- Cambios hechos por usuarios de mi company.
          exists (
            select 1
              from public.users_branches ub
              join public.branches b on b.id = ub.branch_id
             where ub.user_id = public.app_settings_audit.changed_by
               and ub.is_active
               and b.company_id = public.current_company_id()
          )
          -- O cambios hechos por el admin actual.
          or changed_by = auth.uid()
        )
      )
  $sql$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) Vista de diagnóstico: detectar anomalías cross-company.
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Un usuario "limpio" tiene users_branches en branches de UNA sola company.
-- Si por bug histórico quedó con membership en branches de varias companies,
-- esta vista lo lista para que el admin lo limpie a mano.
--
-- Si la vista devuelve 0 filas, el sistema está limpio.

create or replace view public.vw_isolation_audit_anomalies
with (security_invoker = true)
as
select
  ub.user_id,
  p.email,
  p.full_name,
  count(distinct b.company_id) as companies_count,
  array_agg(distinct b.company_id) as company_ids
from public.users_branches ub
join public.branches b on b.id = ub.branch_id
left join public.profiles p on p.id = ub.user_id
where ub.is_active
  and b.is_active
  and b.company_id is not null
group by ub.user_id, p.email, p.full_name
having count(distinct b.company_id) > 1;

comment on view public.vw_isolation_audit_anomalies is
  'Usuarios con membresía activa en sucursales de múltiples empresas. '
  'Cero filas = aislamiento OK.';

grant select on public.vw_isolation_audit_anomalies to authenticated;

commit;
