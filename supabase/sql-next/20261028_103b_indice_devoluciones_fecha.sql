-- Migración 103, paso 2 de 2. Copiar TODO este archivo, pegarlo solo en el
-- SQL Editor y darle Run. Es una sola sentencia (ver 20261028_103_indice_historial_ventas.sql).
create index concurrently if not exists returns_branch_date_nulls_last_idx
  on public.returns (branch_id, return_date desc nulls last);
