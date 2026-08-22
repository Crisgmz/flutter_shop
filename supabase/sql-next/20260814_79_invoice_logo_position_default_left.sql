-- ============================================================================
-- Migración 79 — El logo de la factura A4 pasa a la izquierda por defecto
-- ============================================================================
-- El encabezado del A4 se rediseñó siguiendo la factura de referencia del
-- cliente: el logo va en una esquina y los datos de la empresa (nombre,
-- dirección, correo, teléfono y RNC) quedan CENTRADOS en la hoja. El número de
-- documento y el bloque fiscal (tipo de comprobante + NCF) bajaron a la fila
-- del cliente, alineados a la derecha.
--
-- `app_settings.invoice_logo_position` sigue siendo configurable desde
-- Ajustes → Compañía, pero ahora el valor por defecto es 'left'.
--
-- Esta migración también mueve las filas existentes que quedaron en 'right'
-- por el default anterior (migración 78), que es el layout que el cliente pidió
-- cambiar. Si alguna empresa prefiere el logo a la derecha, lo vuelve a elegir
-- desde Ajustes — no hace falta tocar SQL.
--
-- Idempotente. Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

begin;

alter table public.app_settings
  alter column invoice_logo_position set default 'left';

update public.app_settings
   set invoice_logo_position = 'left'
 where invoice_logo_position is null
    or invoice_logo_position not in ('left', 'right')
    or invoice_logo_position = 'right';

commit;

notify pgrst, 'reload schema';
