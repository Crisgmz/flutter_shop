-- ============================================================================
-- Diagnóstico — productos duplicados por la importación de inventario
-- ============================================================================
-- SOLO LECTURA: no cambia nada. Correr en el SQL Editor de Supabase.
--
-- Hasta el arreglo de la importación (22 sept 2026), subir de nuevo el
-- archivo exportado creaba otra vez todo producto que no tuviera SKU. Esto
-- lista las copias para decidir con cuál quedarse antes de limpiar.
--
-- Por cada copia muestra si tiene ventas o compras: una copia con historial
-- no se puede borrar sin reasignar ese historial al producto que se conserva.
-- ============================================================================

-- ── 1) Resumen: cuántos productos repetidos hay por sucursal ────────────────
with keyed as (
  select
    p.branch_id,
    lower(regexp_replace(trim(p.name), '\s+', ' ', 'g')) as name_key
  from public.products p
),
dup as (
  select branch_id, name_key, count(*) as copias
  from keyed
  group by branch_id, name_key
  having count(*) > 1
)
select
  b.name as sucursal,
  count(*) as productos_repetidos,
  sum(d.copias) - count(*) as copias_de_mas
from dup d
join public.branches b on b.id = d.branch_id
group by b.name
order by copias_de_mas desc;

-- ── 2) Detalle: cada copia con su stock, precio e historial ─────────────────
with keyed as (
  select
    p.*,
    lower(regexp_replace(trim(p.name), '\s+', ' ', 'g')) as name_key
  from public.products p
),
dup as (
  select branch_id, name_key
  from keyed
  group by branch_id, name_key
  having count(*) > 1
)
select
  b.name as sucursal,
  k.name as producto,
  k.id,
  k.sku,
  k.barcode,
  k.stock,
  k.price as precio,
  k.cost as costo,
  k.is_active as activo,
  k.created_at as creado,
  (select count(*) from public.sale_items si where si.product_id = k.id)
    as lineas_de_venta,
  (select count(*) from public.purchase_items pi where pi.product_id = k.id)
    as lineas_de_compra,
  row_number() over (
    partition by k.branch_id, k.name_key order by k.created_at
  ) as copia_n
from keyed k
join dup d on d.branch_id = k.branch_id and d.name_key = k.name_key
join public.branches b on b.id = k.branch_id
order by b.name, k.name_key, k.created_at;
