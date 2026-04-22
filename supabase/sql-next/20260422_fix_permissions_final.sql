-- supabase/sql-next/20260422_fix_permissions_final.sql
-- Script de reparación para el sistema de permisos de Shop+ RD

BEGIN;

-- 1. Eliminar la vista para permitir el cambio de nombres de columnas
DROP VIEW IF EXISTS public.employee_effective_permissions_view;

-- 2. Corregir tabla de permisos (Renombrar y añadir columnas faltantes)
DO $$ 
BEGIN
  -- Renombrar module_key a module si existe
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='permissions' AND column_name='module_key') THEN
    ALTER TABLE public.permissions RENAME COLUMN module_key TO module;
  END IF;

  -- Renombrar action_key a action_type si existe
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='permissions' AND column_name='action_key') THEN
    ALTER TABLE public.permissions RENAME COLUMN action_key TO action_type;
  END IF;

  -- Añadir columna name si no existe
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='permissions' AND column_name='name') THEN
    ALTER TABLE public.permissions ADD COLUMN name text;
  END IF;
END $$;

-- Actualizar nombres iniciales (usando descripción o código como fallback)
UPDATE public.permissions 
SET name = COALESCE(description, code) 
WHERE name IS NULL;

-- 3. Corregir tabla de user_permissions (Renombrar allowed a granted)
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='user_permissions' AND column_name='allowed') THEN
    ALTER TABLE public.user_permissions RENAME COLUMN allowed TO granted;
  END IF;
END $$;

-- 4. Actualizar la función has_permission para usar la columna 'granted'
CREATE OR REPLACE FUNCTION public.has_permission(permission_code text, target_branch_id uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH requested_branch AS (
    SELECT COALESCE(target_branch_id, public.current_branch_id()) AS branch_id
  ),
  user_override AS (
    SELECT up.granted
    FROM public.user_permissions up
    JOIN public.permissions p ON p.id = up.permission_id
    JOIN requested_branch rb ON true
    WHERE up.user_id = auth.uid()
      AND up.is_active
      AND p.code = permission_code
      AND (up.branch_id IS NULL OR up.branch_id = rb.branch_id)
    ORDER BY CASE WHEN up.branch_id = rb.branch_id THEN 0 ELSE 1 END, up.created_at DESC
    LIMIT 1
  ),
  role_grant AS (
    SELECT rp.allowed
    FROM public.role_permissions rp
    JOIN public.permissions p ON p.id = rp.permission_id
    JOIN requested_branch rb ON true
    WHERE rp.is_active
      AND p.code = permission_code
      AND rp.role_key = public.current_user_role_key(rb.branch_id)
    ORDER BY rp.created_at DESC
    LIMIT 1
  )
  SELECT CASE
    WHEN public.is_admin() THEN true
    WHEN EXISTS (SELECT 1 FROM user_override) THEN (SELECT granted FROM user_override)
    WHEN EXISTS (SELECT 1 FROM role_grant) THEN (SELECT allowed FROM role_grant)
    ELSE false
  END;
$$;

-- 5. Recrear la vista con el formato esperado por Flutter (incluyendo permission_name)
CREATE OR REPLACE VIEW public.employee_effective_permissions_view
WITH (security_invoker = true)
AS
WITH branch_scope AS (
  SELECT ub.user_id, ub.branch_id, COALESCE(ub.role_override::text, p.role::text) AS role_key
  FROM public.users_branches ub
  JOIN public.profiles p ON p.id = ub.user_id
  WHERE ub.is_active AND p.is_active AND public.has_branch_access(ub.branch_id)
),
role_grants AS (
  SELECT bs.user_id, bs.branch_id, p.code AS permission_code, rp.allowed
  FROM branch_scope bs
  JOIN public.role_permissions rp ON LOWER(rp.role_key) = LOWER(bs.role_key) AND rp.is_active
  JOIN public.permissions p ON p.id = rp.permission_id AND p.is_active
),
user_overrides AS (
  SELECT up.user_id, up.branch_id, p.code AS permission_code, up.granted
  FROM public.user_permissions up
  JOIN public.permissions p ON p.id = up.permission_id AND p.is_active
  WHERE up.is_active
)
SELECT
  bs.user_id,
  bs.branch_id,
  p.code AS permission_code,
  p.name AS permission_name,
  p.module,
  p.action_type,
  COALESCE(
    (SELECT rg.allowed FROM role_grants rg WHERE rg.user_id = bs.user_id AND rg.branch_id = bs.branch_id AND rg.permission_code = p.code LIMIT 1),
    false
  ) AS role_grant,
  (
    SELECT uo.granted
    FROM user_overrides uo
    WHERE uo.user_id = bs.user_id
      AND (uo.branch_id = bs.branch_id OR uo.branch_id IS NULL)
      AND uo.permission_code = p.code
    ORDER BY CASE WHEN uo.branch_id = bs.branch_id THEN 0 ELSE 1 END
    LIMIT 1
  ) AS user_override,
  COALESCE(
    (
      SELECT uo.granted
      FROM user_overrides uo
      WHERE uo.user_id = bs.user_id
        AND (uo.branch_id = bs.branch_id OR uo.branch_id IS NULL)
        AND uo.permission_code = p.code
      ORDER BY CASE WHEN uo.branch_id = bs.branch_id THEN 0 ELSE 1 END
      LIMIT 1
    ),
    (
      SELECT rg.allowed
      FROM role_grants rg
      WHERE rg.user_id = bs.user_id
        AND rg.branch_id = bs.branch_id
        AND rg.permission_code = p.code
      LIMIT 1
    ),
    false
  ) AS effective_grant
FROM branch_scope bs
CROSS JOIN public.permissions p
WHERE p.is_active;

-- 6. Actualizar las inserciones iniciales con nombres descriptivos
INSERT INTO public.permissions (code, name, module, action_type, description, sort_order)
VALUES
  ('dashboard.view', 'Ver Dashboard', 'dashboard', 'view', 'Ver dashboard general', 10),
  ('sales.view', 'Ver Ventas', 'sales', 'view', 'Ver ventas', 20),
  ('sales.create', 'Crear Ventas', 'sales', 'create', 'Crear ventas', 21),
  ('sales.edit', 'Editar Ventas', 'sales', 'edit', 'Editar ventas', 22),
  ('sales.void', 'Anular Ventas', 'sales', 'void', 'Anular ventas', 23),
  ('sales.export', 'Exportar Ventas', 'sales', 'export', 'Exportar ventas', 24),
  ('clients.view', 'Ver Clientes', 'clients', 'view', 'Ver clientes', 30),
  ('clients.create', 'Crear Clientes', 'clients', 'create', 'Crear clientes', 31),
  ('clients.edit', 'Editar Clientes', 'clients', 'edit', 'Editar clientes', 32),
  ('clients.credit', 'Gestionar Crédito', 'clients', 'credit', 'Gestionar crédito de clientes', 33),
  ('inventory.view', 'Ver Inventario', 'inventory', 'view', 'Ver inventario', 40),
  ('inventory.create', 'Crear Productos', 'inventory', 'create', 'Crear productos', 41),
  ('inventory.edit', 'Editar Productos', 'inventory', 'edit', 'Editar productos', 42),
  ('inventory.adjust', 'Ajustar Inventario', 'inventory', 'adjust', 'Ajustar inventario', 43),
  ('inventory.export', 'Exportar Inventario', 'inventory', 'export', 'Exportar inventario', 44),
  ('purchases.view', 'Ver Compras', 'purchases', 'view', 'Ver compras', 50),
  ('purchases.create', 'Crear Compras', 'purchases', 'create', 'Crear compras', 51),
  ('purchases.edit', 'Editar Compras', 'purchases', 'edit', 'Editar compras', 52),
  ('purchases.receive', 'Recibir Compras', 'purchases', 'receive', 'Recibir compras', 53),
  ('cash.open', 'Abrir Caja', 'cash', 'open', 'Abrir caja', 60),
  ('cash.close', 'Cerrar Caja', 'cash', 'close', 'Cerrar caja', 61),
  ('cash.manage', 'Gestionar Caja', 'cash', 'manage', 'Gestionar caja', 62),
  ('reports.view', 'Ver Reportes', 'reports', 'view', 'Ver reportes', 70),
  ('reports.export', 'Exportar Reportes', 'reports', 'export', 'Exportar reportes', 71),
  ('employees.view', 'Ver Empleados', 'employees', 'view', 'Ver empleados', 80),
  ('employees.manage', 'Administrar Personal', 'employees', 'manage', 'Administrar empleados y permisos', 81),
  ('settings.view', 'Ver Configuración', 'settings', 'view', 'Ver configuración', 90),
  ('settings.manage', 'Editar Configuración', 'settings', 'manage', 'Editar configuración', 91),
  ('ncf.view', 'Ver NCF', 'ncf', 'view', 'Ver secuencias fiscales', 100),
  ('ncf.manage', 'Administrar NCF', 'ncf', 'manage', 'Administrar comprobantes fiscales', 101),
  ('ncf.issue', 'Emitir NCF', 'ncf', 'issue', 'Emitir comprobantes fiscales', 102)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  module = EXCLUDED.module,
  action_type = EXCLUDED.action_type,
  updated_at = NOW();

COMMIT;
