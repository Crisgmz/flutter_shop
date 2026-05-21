-- Fix: `dgii_606_data` y `dgii_607_data` lanzaban
--   "relation \"invalid_rows\" does not exist (42P01)"
-- porque el segundo SELECT (... into v_inconsistencies) intentaba usar la
-- CTE `invalid_rows` definida en la cadena WITH del primer SELECT — y las
-- CTEs solo viven dentro de la query a la que están asociadas.
--
-- Solución: cada función produce filas, inconsistencias y conteo en UNA sola
-- query usando `jsonb_agg(...) FILTER (WHERE ...)` sobre una subquery con la
-- clasificación pre-calculada. Más eficiente además (un solo scan).
--
-- Sin cambios funcionales: el JSON resultante tiene la misma forma.
--
-- Ejecutar después de 20260509_14_dgii_reports.sql. Idempotente.

begin;

-- =====================================================
-- dgii_606_data — Compras del mes con NCF (FIX)
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

  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  -- Una sola query: clasifica cada compra y agrega filas válidas /
  -- inconsistencias en paralelo usando FILTER.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
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
        ) order by purchase_date
      ) filter (where is_valid),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'purchase_id', id,
          'purchase_date', purchase_date,
          'supplier_name', supplier_name,
          'invoice_number', invoice_number,
          'reason', reason
        )
      ) filter (where not is_valid),
      '[]'::jsonb
    ),
    count(*) filter (where is_valid)
  into v_rows, v_inconsistencies, v_total_count
  from (
    select
      p.id,
      p.branch_id,
      p.purchase_date,
      p.invoice_number,
      p.subtotal,
      p.tax_amount,
      p.total_amount,
      p.receipt_type,
      s.rnc as supplier_rnc,
      s.legal_name as supplier_name,
      -- Clasificación inline:
      (p.invoice_number is not null
       and public.is_valid_ncf(p.invoice_number)
       and s.rnc is not null
       and s.rnc <> '') as is_valid,
      case
        when p.invoice_number is null then 'NCF faltante'
        when not public.is_valid_ncf(p.invoice_number) then 'NCF inválido'
        when s.rnc is null or s.rnc = '' then 'RNC de proveedor faltante'
        else 'Otra inconsistencia'
      end as reason
    from public.purchases p
    join public.suppliers s
      on s.id = p.supplier_id and s.branch_id = p.branch_id
    where p.branch_id = v_branch_id
      and p.status in ('posted'::public.purchase_status,
                       'received'::public.purchase_status)
      and extract(year from p.purchase_date) = p_year
      and extract(month from p.purchase_date) = p_month
  ) classified;

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
-- dgii_607_data — Ventas del mes con NCF (FIX)
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

  -- Una sola query: clasifica cada venta y agrega filas válidas /
  -- inconsistencias en paralelo usando FILTER.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rnc_cliente', client_doc,
          'tipo_id', case
                       when length(coalesce(client_doc, '')) >= 11 then '2'
                       when length(coalesce(client_doc, '')) >= 9 then '1'
                       else '3'
                     end,
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
        ) order by sale_date
      ) filter (where is_valid),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'sale_id', id,
          'sale_date', sale_date,
          'sale_number', sale_number,
          'client_name', client_name,
          'ncf', ncf,
          'reason', reason
        )
      ) filter (where not is_valid),
      '[]'::jsonb
    ),
    count(*) filter (where is_valid)
  into v_rows, v_inconsistencies, v_total_count
  from (
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
      case s.receipt_type
        when 'consumer_final' then '02'
        when 'fiscal_credit'  then '01'
        when 'governmental'   then '06'
        when 'special'        then '03'
        when 'export'         then '04'
        else '02'
      end as tipo_ingreso,
      -- Clasificación inline:
      (s.ncf is not null
       and public.is_valid_ncf(s.ncf)
       and (s.receipt_type <> 'fiscal_credit'::public.receipt_type
            or (c.document_number is not null
                and c.document_number <> ''))) as is_valid,
      case
        when s.ncf is null then 'NCF faltante'
        when not public.is_valid_ncf(coalesce(s.ncf, '')) then 'NCF inválido'
        when s.receipt_type = 'fiscal_credit'::public.receipt_type
             and (c.document_number is null or c.document_number = '')
          then 'Crédito fiscal sin documento de cliente'
        else 'Otra inconsistencia'
      end as reason
    from public.sales s
    left join public.clients c
      on c.id = s.client_id and c.branch_id = s.branch_id
    where s.branch_id = v_branch_id
      and s.status in ('completed'::public.sale_status,
                       'credit'::public.sale_status)
      and extract(year from s.sale_date) = p_year
      and extract(month from s.sale_date) = p_month
  ) classified;

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

commit;
