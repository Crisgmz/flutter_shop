-- ============================================================================
-- Migración 99 — Stock e IMEI bloqueados en "Editar producto"
-- ============================================================================
-- PEDIDO (6 oct 2026): el campo Stock y el de IMEI del formulario del
-- producto vienen BLOQUEADOS de fábrica. Cualquiera con acceso a Inventario
-- podía cambiar el stock sin dejar rastro o meter IMEIs a mano; lo correcto es
-- que el stock cambie con Compras o "Ajustar stock" (queda en el historial
-- con usuario y motivo) y que los IMEIs entren por Compras.
--
-- Solo el dueño (Configuración → Inventario, admin) los desbloquea. La app ya
-- los trata como apagados si estas columnas no existen: esta migración solo
-- hace falta para poder PRENDERLOS.
--
-- No afecta shop-plus: dos columnas nuevas con default false que no lee.
-- Idempotente.
-- ============================================================================

alter table public.app_settings
  add column if not exists inv_allow_product_stock_edit boolean not null default false;

alter table public.app_settings
  add column if not exists inv_allow_product_imei_edit boolean not null default false;

comment on column public.app_settings.inv_allow_product_stock_edit is
  'Permite escribir el stock en Editar producto (el cambio entra como ajuste). Default false.';
comment on column public.app_settings.inv_allow_product_imei_edit is
  'Permite escribir IMEIs en Editar producto (lo normal es por Compras). Default false.';

notify pgrst, 'reload schema';
