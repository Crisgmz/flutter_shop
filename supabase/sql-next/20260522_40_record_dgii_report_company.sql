-- Fix: record_dgii_report no pasaba company_id (rompía post-migration 38).
--
-- Después de la migration 38, fiscal_dgii_reports tiene:
--   - company_id NOT NULL
--   - UNIQUE (company_id, report_type, period_year, period_month)
--     (antes era UNIQUE solo por (report_type, year, month))
--
-- El RPC record_dgii_report quedó desactualizado:
--   1. Insertaba sin company_id → NOT NULL violation.
--   2. on conflict (report_type, year, month) ya no matchea el UNIQUE
--      nuevo → la UPSERT falla.
--
-- Fix: pasar company_id = current_company_id() y actualizar el on conflict.
-- Idempotente.

begin;

create or replace function public.record_dgii_report(
  p_report_type text,
  p_year integer,
  p_month integer,
  p_records_count integer,
  p_inconsistencies_count integer,
  p_storage_path text default null,
  p_txt_url text default null,
  p_pdf_url text default null,
  p_inconsistencies jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_company_id uuid;
begin
  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant'
      using errcode = '42501';
  end if;

  v_company_id := public.current_company_id();
  if v_company_id is null then
    raise exception 'No hay empresa asignada al usuario actual.'
      using errcode = '22023';
  end if;

  insert into public.fiscal_dgii_reports (
    company_id, report_type, period_year, period_month, generated_by,
    records_count, inconsistencies_count, inconsistencies,
    txt_file_url, pdf_file_url, storage_path, status
  ) values (
    v_company_id,
    p_report_type::public.fiscal_dgii_report_type,
    p_year, p_month, auth.uid(),
    p_records_count, p_inconsistencies_count, p_inconsistencies,
    p_txt_url, p_pdf_url, p_storage_path, 'generated'
  )
  on conflict (company_id, report_type, period_year, period_month) do update set
    generated_at = timezone('utc', now()),
    generated_by = auth.uid(),
    records_count = excluded.records_count,
    inconsistencies_count = excluded.inconsistencies_count,
    inconsistencies = excluded.inconsistencies,
    txt_file_url = coalesce(excluded.txt_file_url, public.fiscal_dgii_reports.txt_file_url),
    pdf_file_url = coalesce(excluded.pdf_file_url, public.fiscal_dgii_reports.pdf_file_url),
    storage_path = coalesce(excluded.storage_path, public.fiscal_dgii_reports.storage_path)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.record_dgii_report(
  text, integer, integer, integer, integer, text, text, text, jsonb
) to authenticated;

commit;
