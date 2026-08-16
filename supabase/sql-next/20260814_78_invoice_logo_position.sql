-- ============================================================================
-- Migración 78 — Posición del logo en la factura/cotización A4
-- ============================================================================
-- El encabezado del A4 tiene el logo, el nombre comercial y el bloque fiscal
-- clavados a la DERECHA, y los datos del emisor (RNC, dirección, teléfono,
-- correo) a la izquierda. No había forma de invertirlo.
--
-- `app_settings.invoice_logo_position` deja elegir de qué lado va el bloque de
-- marca. Valores: 'right' (por defecto, el comportamiento de siempre) o 'left'.
-- Cuando es 'left', el logo y el bloque fiscal pasan a la izquierda y los datos
-- del emisor se van a la derecha, alineados a ese borde.
--
-- Solo afecta al documento A4 (factura, cotización, orden de compra, recibo de
-- abono y comprobante de gasto, que comparten el mismo builder). El ticket
-- térmico de 58/80mm no cambia: ahí todo va centrado.
--
-- Idempotente. Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

begin;

alter table public.app_settings
  add column if not exists invoice_logo_position text not null default 'right';

-- Constraint en bloque guardado: `add constraint` no admite `if not exists`.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'app_settings_invoice_logo_position_check'
       and conrelid = 'public.app_settings'::regclass
  ) then
    alter table public.app_settings
      add constraint app_settings_invoice_logo_position_check
      check (invoice_logo_position in ('left', 'right'));
  end if;
end $$;

-- Normaliza cualquier fila que hubiera quedado con un valor raro antes de que
-- existiera el check (o por escritura directa).
update public.app_settings
   set invoice_logo_position = 'right'
 where invoice_logo_position is null
    or invoice_logo_position not in ('left', 'right');

commit;

notify pgrst, 'reload schema';
