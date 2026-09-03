-- ============================================================================
-- Migración 85 — Guardar el desglose del efectivo contado al cerrar caja
-- ============================================================================
-- El cajero cuenta su efectivo por denominación (45 de 2000, 13 de 1000, …) y
-- ese conteo es el comprobante que firma al entregar el turno. Hasta ahora
-- solo se guardaba el TOTAL (`closing_amount`), así que el desglose se podía
-- imprimir una única vez, en el momento del cierre: si el cajero perdía el
-- papel o el dueño quería revisarlo después, ya no existía.
--
-- Con esta columna el comprobante de EFECTIVO CONTADO se puede reimprimir
-- desde el detalle del cierre, que es lo que el dueño necesita para verificar
-- un turno viejo.
--
-- Formato: {"2000": 45, "1000": 13, "500": 6, ...} — denominación → cantidad.
--
-- Idempotente.
-- ============================================================================

begin;

alter table public.cash_sessions
  add column if not exists closing_breakdown jsonb;

comment on column public.cash_sessions.closing_breakdown is
  'Conteo del cierre por denominación: {"2000": 45, "1000": 13, ...}. '
  'Permite reimprimir el comprobante de efectivo contado que firma el cajero.';

commit;

notify pgrst, 'reload schema';
