-- RPC: update_sale_payment_method
--
-- Cambia el método de pago de TODAS las filas de payments asociadas a una
-- venta. Pensado para corregir errores del cajero (ej. registró efectivo
-- pero el cliente pagó por transferencia).
--
-- No cambia montos ni crea pagos nuevos — solo el `payment_method`. Si la
-- venta tiene varios pagos (split payment), todos pasan al mismo método.
-- Para split-payment con métodos distintos, usar el editor de pagos
-- avanzado (no implementado todavía).
--
-- Seguridad: SECURITY DEFINER + has_branch_access + solo admin/supervisor.

begin;

create or replace function public.update_sale_payment_method(
  p_sale_id uuid,
  p_payment_method public.payment_method
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_status public.sale_status;
  v_updated integer;
begin
  if p_sale_id is null then
    raise exception 'p_sale_id es requerido.'
      using errcode = '22023';
  end if;
  if p_payment_method is null then
    raise exception 'p_payment_method es requerido.'
      using errcode = '22023';
  end if;

  if not public.is_admin()
     and public.current_user_role() <> 'supervisor'::public.app_role then
    raise exception 'Solo admin o supervisor pueden cambiar el método de pago.'
      using errcode = '42501';
  end if;

  select branch_id, status into v_branch_id, v_status
  from public.sales
  where id = p_sale_id;

  if v_branch_id is null then
    raise exception 'Venta no encontrada.'
      using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esta venta.'
      using errcode = '42501';
  end if;

  if v_status = 'voided'::public.sale_status then
    raise exception 'No se puede modificar una venta anulada.'
      using errcode = '22023';
  end if;

  update public.payments
    set payment_method = p_payment_method,
        updated_at = timezone('utc', now())
  where sale_id = p_sale_id
    and branch_id = v_branch_id;

  get diagnostics v_updated = row_count;

  return v_updated;
end;
$$;

grant execute on function public.update_sale_payment_method(
  uuid, public.payment_method
) to authenticated;

commit;
