-- ============================================================================
-- IMEI por producto (para negocios que venden celulares/dispositivos)
-- ============================================================================
-- Guarda una lista de IMEIs en el producto. El usuario puede agregar uno o
-- varios (ej. 20 teléfonos, uno por cada equipo) desde el formulario de
-- producto. Es un arreglo de texto; vacío por defecto.
--
-- Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

alter table public.products
  add column if not exists imeis text[] not null default '{}';

-- Toggle global: activar el modo IMEI/serie (Configuración › Inventario).
alter table public.app_settings
  add column if not exists inv_imei_mode boolean not null default false;

notify pgrst, 'reload schema';
