-- Migración 100, paso 2 de 3. Copiar TODO este archivo, pegarlo solo en el
-- SQL Editor y darle Run. Es una sola sentencia (ver 20261016_100_indices_cobros.sql).
create index concurrently if not exists sales_open_balance_idx
  on public.sales (branch_id, due_date)
  where balance_due > 0;
