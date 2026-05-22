-- Fix: bug del signup multi-tenant.
--
-- Síntoma:
--   Al registrar un negocio nuevo, /configuración muestra los datos del
--   negocio viejo. Los cambios guardados en /configuración del negocio
--   nuevo terminan en la fila legacy y los ven todos los usuarios.
--
-- Causa raíz:
--   1) La fila legacy `app_settings` (id=1, anterior al migration multi-tenant
--      #27) quedó con `company_id IS NULL`.
--   2) El RLS de `app_settings` permite ver / editar filas con
--      `company_id IS NULL` a TODOS los usuarios autenticados:
--          using (company_id is null or has_company_access(company_id))
--      Era una puerta trasera para mantener compatibilidad legacy.
--   3) El cliente hace `select().limit(1)` sin filtro. Postgres devuelve la
--      primera fila visible — normalmente la legacy id=1.
--   4) Bootstrap crea la fila correcta con company_id, pero el cliente la
--      ignora y sigue usando la legacy.
--
-- Fix:
--   1) Asignar la fila legacy a una empresa real (la más antigua que tenga
--      sucursales). Si no hay empresas, borrar la fila.
--   2) Endurecer el RLS: ya NO se permite `company_id IS NULL`. Cada
--      empresa ve y edita SOLO su propia fila.
--   3) Garantizar que toda app_settings tiene company_id (NOT NULL).
--
-- Defensiva: si las tablas requeridas (app_settings, companies) o el helper
-- has_company_access() no existen, la migration se salta toda con un NOTICE.
-- Eso permite correrla en cualquier estado de la DB; si una migration previa
-- no se ha corrido, primero hay que correr esa.
--
-- Idempotente.

begin;

do $$
declare
  v_legacy_count integer;
  v_target_company uuid;
  v_collision_count integer;
begin
  -- ── Pre-flight: dependencias ──────────────────────────────────────────
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'app_settings'
  ) then
    raise notice
      'Salteando: app_settings no existe. Corre primero 20260509_08_app_settings.sql';
    return;
  end if;

  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'companies'
  ) then
    raise notice
      'Salteando: companies no existe. Corre primero 20260520_27_multi_tenant_foundation.sql';
    return;
  end if;

  if not exists (
    select 1 from information_schema.routines
    where routine_schema = 'public' and routine_name = 'has_company_access'
  ) then
    raise notice
      'Salteando: has_company_access() no existe. Corre primero 20260520_27_multi_tenant_foundation.sql';
    return;
  end if;

  -- ── 1) Reparar la fila legacy app_settings (company_id NULL) ──────────
  execute 'select count(*) from public.app_settings where company_id is null'
    into v_legacy_count;

  if v_legacy_count > 0 then
    -- Empresa "principal": la más antigua con al menos una sucursal activa.
    select c.id into v_target_company
    from public.companies c
    where c.is_active
      and exists (
        select 1 from public.branches b
        where b.company_id = c.id and b.is_active
      )
    order by c.created_at asc
    limit 1;

    if v_target_company is null then
      -- No hay empresas reales todavía: la fila legacy no sirve, borrarla.
      execute 'delete from public.app_settings where company_id is null';
    else
      -- ¿La empresa elegida ya tiene su propia app_settings (vía bootstrap)?
      execute 'select count(*) from public.app_settings where company_id = $1'
        into v_collision_count
        using v_target_company;

      if v_collision_count > 0 then
        -- Sí, hay colisión: borrar la legacy para no duplicar.
        execute 'delete from public.app_settings where company_id is null';
      else
        -- No, re-etiquetar la legacy con la empresa elegida.
        execute 'update public.app_settings set company_id = $1 where company_id is null'
          using v_target_company;
      end if;
    end if;

    -- Cualquier otra empresa que aún no tenga app_settings necesita su
    -- propia fila para que el RLS post-fix no la deje sin configuración.
    execute $sql$
      insert into public.app_settings (company_name, company_id)
      select c.name, c.id
        from public.companies c
       where c.is_active
         and not exists (
           select 1 from public.app_settings s where s.company_id = c.id
         )
    $sql$;
  end if;

  -- ── 2) NOT NULL en company_id para prevenir nuevas filas huérfanas ────
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'app_settings'
      and column_name = 'company_id'
      and is_nullable = 'YES'
  ) then
    execute 'alter table public.app_settings alter column company_id set not null';
  end if;

  -- ── 3) RLS endurecida: cada empresa ve y edita SOLO su fila ───────────
  execute 'drop policy if exists app_settings_select on public.app_settings';
  execute $sql$
    create policy app_settings_select on public.app_settings
      for select to authenticated
      using (public.has_company_access(company_id))
  $sql$;

  execute 'drop policy if exists app_settings_update on public.app_settings';
  execute $sql$
    create policy app_settings_update on public.app_settings
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
end $$;

commit;
