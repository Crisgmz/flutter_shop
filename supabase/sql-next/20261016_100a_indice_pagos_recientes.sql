-- Migración 100, paso 1 de 3. Copiar TODO este archivo, pegarlo solo en el
-- SQL Editor y darle Run. Es una sola sentencia (ver 20261016_100_indices_cobros.sql).
create index concurrently if not exists payments_branch_paid_at_idx
  on public.payments (branch_id, paid_at desc nulls last);
