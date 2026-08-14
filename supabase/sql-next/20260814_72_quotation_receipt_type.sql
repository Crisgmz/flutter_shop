-- ============================================================================
-- Migración 72 — Cotización: tipo de comprobante
-- ============================================================================
-- Al cotizar, el cliente que necesita crédito fiscal quiere ver desde ya que
-- la factura llevará ITBIS y NCF de crédito fiscal. Hoy la cotización no
-- guarda el tipo de comprobante y al convertirla siempre sale como consumidor
-- final.
--
-- `quotations.receipt_type` usa el mismo enum public.receipt_type que
-- public.sales ('consumer_final', 'fiscal_credit', 'governmental', 'special',
-- 'export'), con el mismo default 'consumer_final', para que las cotizaciones
-- ya existentes no cambien de comportamiento.
--
-- ⚠️ DECISIÓN DELIBERADA — NO se agrega columna `ncf` a quotations y la
-- cotización NO consume secuencia NCF.
-- El NCF es un correlativo fiscal ante la DGII: cada número emitido debe
-- corresponder a un comprobante realmente emitido. Si una cotización tomara
-- un NCF y luego nunca se facturara (que es el caso normal: la mayoría de las
-- cotizaciones no se convierten), quedaría un hueco en la correlatividad y el
-- 607 saldría con números faltantes. El NCF se asigna al CONVERTIR la
-- cotización en venta, no antes. La cotización solo declara la INTENCIÓN
-- (qué tipo de comprobante se emitirá).
--
-- Ejecutar después de:
--   supabase/sql-next/20260410_quotations_schema.sql
--
-- Idempotente.
-- ============================================================================

begin;

alter table public.quotations
  add column if not exists receipt_type public.receipt_type
    not null default 'consumer_final';

comment on column public.quotations.receipt_type is
  'Tipo de comprobante que se emitirá al convertir la cotización en venta. No consume NCF: el NCF se asigna al facturar.';

commit;

notify pgrst, 'reload schema';
