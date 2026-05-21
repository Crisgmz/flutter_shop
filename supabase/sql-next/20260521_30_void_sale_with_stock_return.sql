-- RPC: void_sale_with_stock_return
--
-- Anula una venta atómicamente:
--   1) Borra sale_items → el trigger trg_sale_items_stock devuelve el stock.
--   2) Borra payments asociados (revierte cobros).
--   3) Marca sales.status = 'voided'.
--
-- No toca NCFs (el módulo de comprobantes fiscales tiene su propio flujo de
-- anulación contra DGII). Si la venta tenía NCF, el comprobante queda
-- huérfano apuntando a una venta voided — eso es esperado.
--
-- Seguridad: SECURITY DEFINER pero valida has_branch_access(branch_id) de
-- la venta antes de hacer nada.

begin;

create or replace function public.void_sale_with_stock_return(
  p_sale_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_status public.sale_status;
begin
  if p_sale_id is null then
    raise exception 'p_sale_id es requerido.'
      using errcode = '22023';
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
    raise exception 'La venta ya está anulada.'
      using errcode = '23505';
  end if;

  -- 1) Borrar sale_items. El trigger trg_sale_items_stock corre por cada
  --    fila y devuelve el stock al producto.
  delete from public.sale_items
  where sale_id = p_sale_id;

  -- 2) Borrar pagos vinculados (no quedan apuntando a una venta anulada).
  delete from public.payments
  where sale_id = p_sale_id;

  -- 3) Marcar la venta como anulada.
  update public.sales
    set status = 'voided'::public.sale_status,
        updated_at = timezone('utc', now())
  where id = p_sale_id;
end;
$$;

grant execute on function public.void_sale_with_stock_return(uuid)
  to authenticated;

commit;
