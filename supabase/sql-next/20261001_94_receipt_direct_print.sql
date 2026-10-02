-- ============================================================================
-- Migración 94 — Impresión directa (sin vista previa)
-- ============================================================================
-- PEDIDO (1 oct 2026): que la última parte de imprimir sea opcional en
-- Configuración; una vez configurada la impresora, que imprima directo.
--
-- `app_settings.receipt_direct_print` (Configuración → Ventas y recibo →
-- "Impresión directa"). Prendido, las facturas y recibos que antes abrían el
-- cuadro "Vista previa" (venta a crédito, reimprimir desde el historial,
-- cobros, compras, gastos, cotizaciones) se mandan a imprimir de una vez. Si la
-- impresión no llega a abrir, la app cae al cuadro de siempre.
--
-- La ventana de impresión del NAVEGADOR no la controla la página: para que
-- Chrome tampoco la muestre, cada caja abre el sistema con `--kiosk-printing`
-- (los pasos están en la misma pantalla de Configuración).
--
-- Apagado por defecto: nadie cambia de comportamiento hasta prenderlo.
--
-- Idempotente. Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

begin;

alter table public.app_settings
  add column if not exists receipt_direct_print boolean not null default false;

commit;

notify pgrst, 'reload schema';
