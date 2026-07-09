-- ============================================================================
-- Migración 61 — NCF de comprobante de compra (campo dedicado en purchases)
-- ============================================================================
-- Decisión del dueño: en el formulario de compra debe existir la opción
-- "Asignar NCF comprobante de compra" con un campo "No." donde se escribe el
-- NCF a mano. Hasta hoy el reporte DGII 606 leía el NCF desde
-- `purchases.invoice_number`, mezclando la factura del proveedor con el NCF.
--
-- Esta migración separa ambos conceptos:
--   - `invoice_number` → número de factura del proveedor (informativo).
--   - `ncf`            → comprobante fiscal para el 606 (nuevo, dedicado).
--
-- El 606 pasa a usar coalesce(nullif(trim(ncf),''), invoice_number) para que
-- las compras viejas (que guardaban el NCF en invoice_number) sigan reportando
-- igual, y las nuevas usen el campo `ncf`.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la migración 60.
-- Idempotente (ADD COLUMN IF NOT EXISTS + CREATE OR REPLACE).
-- ============================================================================

begin;

-- 1) Campo dedicado para el NCF de la compra.
alter table public.purchases add column if not exists ncf text;

comment on column public.purchases.ncf is
  'NCF del comprobante de compra (para reporte DGII 606). Separado de invoice_number.';

-- 2) Reporte 606: usar el NCF dedicado con fallback al invoice_number histórico.
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
          'ncf', effective_ncf,
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
          'invoice_number', effective_ncf,
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
      -- NCF efectivo: campo dedicado, con fallback al invoice_number histórico.
      coalesce(nullif(trim(p.ncf), ''), p.invoice_number) as effective_ncf,
      p.subtotal,
      p.tax_amount,
      p.total_amount,
      p.receipt_type,
      s.rnc as supplier_rnc,
      s.legal_name as supplier_name,
      -- Clasificación inline (sobre el NCF efectivo):
      (coalesce(nullif(trim(p.ncf), ''), p.invoice_number) is not null
       and public.is_valid_ncf(coalesce(nullif(trim(p.ncf), ''), p.invoice_number))
       and s.rnc is not null
       and s.rnc <> '') as is_valid,
      case
        when coalesce(nullif(trim(p.ncf), ''), p.invoice_number) is null then 'NCF faltante'
        when not public.is_valid_ncf(coalesce(nullif(trim(p.ncf), ''), p.invoice_number)) then 'NCF inválido'
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

commit;
