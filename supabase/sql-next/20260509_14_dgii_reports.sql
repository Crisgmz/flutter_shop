-- 20260509_14_dgii_reports.sql
-- Shop+ RD - PRD 07 Round 3: Reportes Fiscales DGII.
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_09_reports_schema.sql (fiscal_dgii_reports
--     y fiscal_z_closures tablas ya creadas)
--   supabase/sql-next/20260509_13_reports_round2_views.sql
--
-- Diseño:
--   - 3 RPCs SECURITY DEFINER que devuelven la data lista para serializar
--     a TXT en el cliente Flutter:
--       * `dgii_606_data(p_year, p_month)` — compras del mes con NCF
--         (formato 606).
--       * `dgii_607_data(p_year, p_month)` — ventas del mes con NCF
--         (formato 607).
--       * `dgii_it1_summary(p_year, p_month)` — resumen IT-1.
--   - 1 view + 1 RPC para "Impuestos" (desglose ITBIS por período).
--   - Cada RPC reporta inconsistencias (NCF inválido, RNC faltante en
--     crédito fiscal, etc.) para que el cliente decida.
--   - RLS: sólo admin/accountant ejecutan (policy en
--     `fiscal_dgii_reports` lo refuerza también).

begin;

-- =====================================================
-- 1) Helper: detectar NCF válido (formato fiscal RD)
-- =====================================================

create or replace function public.is_valid_ncf(p_ncf text)
returns boolean
language sql
immutable
as $$
  -- Formato moderno B01-NNNNNNNN o legacy A0100000001 (12 chars)
  select p_ncf ~ '^[BAE][0-9]{2}-?[0-9]{8,10}$';
$$;

-- =====================================================
-- 2) RPC: dgii_606_data — Compras del mes con NCF
-- =====================================================

create or replace function public.dgii_606_data(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_rows jsonb;
  v_inconsistencies jsonb;
  v_total_count integer;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  -- RNC del negocio desde app_settings
  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  with month_purchases as (
    select
      p.id,
      p.branch_id,
      p.purchase_date,
      p.invoice_number,
      p.subtotal,
      p.tax_amount,
      p.total_amount,
      p.supplier_document_type,
      p.supplier_document_number,
      p.receipt_type,
      s.rnc as supplier_rnc,
      s.legal_name as supplier_name
    from public.purchases p
    join public.suppliers s on s.id = p.supplier_id and s.branch_id = p.branch_id
    where p.branch_id = v_branch_id
      and p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
      and extract(year from p.purchase_date) = p_year
      and extract(month from p.purchase_date) = p_month
  ),
  valid_rows as (
    select * from month_purchases
    where invoice_number is not null
      and public.is_valid_ncf(invoice_number)
      and supplier_rnc is not null
      and supplier_rnc <> ''
  ),
  invalid_rows as (
    select *,
      case
        when invoice_number is null then 'NCF faltante'
        when not public.is_valid_ncf(invoice_number) then 'NCF inválido'
        when supplier_rnc is null or supplier_rnc = '' then 'RNC de proveedor faltante'
        else 'Otra inconsistencia'
      end as reason
    from month_purchases
    where invoice_number is null
       or not public.is_valid_ncf(invoice_number)
       or supplier_rnc is null
       or supplier_rnc = ''
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'rnc_proveedor', supplier_rnc,
      'tipo_id', case when length(coalesce(supplier_rnc, '')) >= 11 then '2' else '1' end,
      'tipo_bien_servicio', '09',
      'ncf', invoice_number,
      'ncf_modificado', null,
      'fecha_comprobante', to_char(purchase_date, 'YYYYMMDD'),
      'fecha_pago', to_char(purchase_date, 'YYYYMMDD'),
      'monto_facturado', subtotal,
      'itbis_facturado', tax_amount,
      'monto_total', total_amount,
      'supplier_name', supplier_name
    ) order by purchase_date), '[]'::jsonb)
    into v_rows
    from valid_rows;

  select coalesce(jsonb_agg(jsonb_build_object(
    'purchase_id', id,
    'purchase_date', purchase_date,
    'supplier_name', supplier_name,
    'invoice_number', invoice_number,
    'reason', reason
  )), '[]'::jsonb)
  into v_inconsistencies
  from invalid_rows;

  select count(*) into v_total_count from valid_rows;

  return jsonb_build_object(
    'report_type', '606',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'records_count', v_total_count,
    'rows', v_rows,
    'inconsistencies', v_inconsistencies,
    'inconsistencies_count', jsonb_array_length(v_inconsistencies)
  );
end;
$$;

grant execute on function public.dgii_606_data(integer, integer, uuid) to authenticated;

-- =====================================================
-- 3) RPC: dgii_607_data — Ventas del mes con NCF
-- =====================================================

create or replace function public.dgii_607_data(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_rows jsonb;
  v_inconsistencies jsonb;
  v_total_count integer;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  with month_sales as (
    select
      s.id,
      s.branch_id,
      s.sale_date,
      s.sale_number,
      s.ncf,
      s.receipt_type,
      s.client_id,
      s.subtotal,
      s.tax_amount,
      s.total_amount,
      s.paid_amount,
      s.balance_due,
      s.status,
      c.document_number as client_doc,
      c.document_type as client_doc_type,
      c.full_name as client_name,
      -- Tipo de ingreso DGII (regla simplificada por receipt_type)
      case s.receipt_type
        when 'consumer_final' then '02'   -- Operaciones a consumidores finales
        when 'fiscal_credit'  then '01'   -- Ventas a contribuyentes
        when 'governmental'   then '06'   -- Operaciones gubernamentales
        when 'special'        then '03'   -- Régimen especial
        when 'export'         then '04'   -- Exportaciones
        else '02'
      end as tipo_ingreso
    from public.sales s
    left join public.clients c on c.id = s.client_id and c.branch_id = s.branch_id
    where s.branch_id = v_branch_id
      and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
      and extract(year from s.sale_date) = p_year
      and extract(month from s.sale_date) = p_month
  ),
  valid_rows as (
    select * from month_sales
    where ncf is not null
      and public.is_valid_ncf(ncf)
      -- Crédito fiscal exige cliente con documento
      and (receipt_type <> 'fiscal_credit'::public.receipt_type
           or (client_doc is not null and client_doc <> ''))
  ),
  invalid_rows as (
    select *,
      case
        when ncf is null then 'NCF faltante'
        when not public.is_valid_ncf(coalesce(ncf, '')) then 'NCF inválido'
        when receipt_type = 'fiscal_credit'::public.receipt_type
             and (client_doc is null or client_doc = '')
          then 'Crédito fiscal sin documento de cliente'
        else 'Otra inconsistencia'
      end as reason
    from month_sales
    where ncf is null
       or not public.is_valid_ncf(coalesce(ncf, ''))
       or (receipt_type = 'fiscal_credit'::public.receipt_type
           and (client_doc is null or client_doc = ''))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'rnc_cliente', client_doc,
    'tipo_id', case when length(coalesce(client_doc, '')) >= 11 then '2'
                    when length(coalesce(client_doc, '')) >= 9 then '1'
                    else '3' end,
    'ncf', ncf,
    'ncf_modificado', null,
    'tipo_ingreso', tipo_ingreso,
    'fecha_comprobante', to_char(sale_date, 'YYYYMMDD'),
    'monto_facturado', subtotal,
    'itbis_facturado', tax_amount,
    'monto_total', total_amount,
    'efectivo', case when status = 'completed' then paid_amount else 0 end,
    'credito', case when status = 'credit' then total_amount else balance_due end,
    'client_name', client_name
  ) order by sale_date), '[]'::jsonb)
  into v_rows
  from valid_rows;

  select coalesce(jsonb_agg(jsonb_build_object(
    'sale_id', id,
    'sale_date', sale_date,
    'sale_number', sale_number,
    'client_name', client_name,
    'ncf', ncf,
    'reason', reason
  )), '[]'::jsonb)
  into v_inconsistencies
  from invalid_rows;

  select count(*) into v_total_count from valid_rows;

  return jsonb_build_object(
    'report_type', '607',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'records_count', v_total_count,
    'rows', v_rows,
    'inconsistencies', v_inconsistencies,
    'inconsistencies_count', jsonb_array_length(v_inconsistencies)
  );
end;
$$;

grant execute on function public.dgii_607_data(integer, integer, uuid) to authenticated;

-- =====================================================
-- 4) RPC: dgii_it1_summary — Resumen IT-1 (ITBIS mensual)
-- =====================================================

create or replace function public.dgii_it1_summary(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_sales_total numeric(14,2) := 0;
  v_sales_taxable numeric(14,2) := 0;
  v_sales_exempt numeric(14,2) := 0;
  v_itbis_received numeric(14,2) := 0;
  v_purchases_total numeric(14,2) := 0;
  v_itbis_paid numeric(14,2) := 0;
  v_returns_total numeric(14,2) := 0;
  v_returns_itbis numeric(14,2) := 0;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  -- Ventas + ITBIS recibido
  select
    coalesce(sum(total_amount), 0),
    coalesce(sum(taxable_amount), 0),
    coalesce(sum(exempt_amount), 0),
    coalesce(sum(tax_amount), 0)
  into v_sales_total, v_sales_taxable, v_sales_exempt, v_itbis_received
  from public.sales
  where branch_id = v_branch_id
    and status in ('completed'::public.sale_status, 'credit'::public.sale_status)
    and extract(year from sale_date) = p_year
    and extract(month from sale_date) = p_month;

  -- Compras + ITBIS pagado
  select
    coalesce(sum(total_amount), 0),
    coalesce(sum(tax_amount), 0)
  into v_purchases_total, v_itbis_paid
  from public.purchases
  where branch_id = v_branch_id
    and status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
    and extract(year from purchase_date) = p_year
    and extract(month from purchase_date) = p_month;

  -- Devoluciones del período
  select
    coalesce(sum(total_amount), 0),
    coalesce(sum(tax_amount), 0)
  into v_returns_total, v_returns_itbis
  from public.returns
  where branch_id = v_branch_id
    and extract(year from return_date) = p_year
    and extract(month from return_date) = p_month;

  return jsonb_build_object(
    'report_type', 'IT1',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'sales_total', v_sales_total,
    'sales_taxable', v_sales_taxable,
    'sales_exempt', v_sales_exempt,
    'itbis_received', v_itbis_received,
    'purchases_total', v_purchases_total,
    'itbis_paid', v_itbis_paid,
    'returns_total', v_returns_total,
    'returns_itbis', v_returns_itbis,
    'itbis_balance', v_itbis_received - v_itbis_paid - v_returns_itbis,
    'balance_direction',
      case
        when (v_itbis_received - v_itbis_paid - v_returns_itbis) > 0 then 'pagar'
        when (v_itbis_received - v_itbis_paid - v_returns_itbis) < 0 then 'favor'
        else 'cero' end
  );
end;
$$;

grant execute on function public.dgii_it1_summary(integer, integer, uuid) to authenticated;

-- =====================================================
-- 5) Impuestos — vista de desglose por tasa
-- =====================================================

create or replace view public.report_tax_breakdown_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  si.tax_rate,
  count(distinct si.sale_id)::bigint as sales_count,
  sum(si.quantity)::numeric(14,3) as items_count,
  sum(si.line_subtotal)::numeric(14,2) as taxable_base,
  sum(si.line_tax)::numeric(14,2) as tax_amount,
  sum(si.line_total)::numeric(14,2) as total_with_tax
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(si.branch_id)
group by si.branch_id, date(s.sale_date at time zone 'America/Santo_Domingo'), si.tax_rate;

grant select on public.report_tax_breakdown_view to authenticated;

-- =====================================================
-- 6) Helper: registrar un reporte DGII generado (audit)
-- =====================================================

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
begin
  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant';
  end if;

  insert into public.fiscal_dgii_reports (
    report_type, period_year, period_month, generated_by,
    records_count, inconsistencies_count, inconsistencies,
    txt_file_url, pdf_file_url, storage_path, status
  ) values (
    p_report_type::public.fiscal_dgii_report_type,
    p_year, p_month, auth.uid(),
    p_records_count, p_inconsistencies_count, p_inconsistencies,
    p_txt_url, p_pdf_url, p_storage_path, 'generated'
  )
  on conflict (report_type, period_year, period_month) do update set
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

grant execute on function public.record_dgii_report(text, integer, integer, integer, integer, text, text, text, jsonb) to authenticated;

commit;
