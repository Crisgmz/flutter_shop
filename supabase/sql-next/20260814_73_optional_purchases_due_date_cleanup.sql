-- ============================================================================
-- Migración 73 — OPCIONAL — Saneo de cuentas por pagar (due_date fantasma)
-- ============================================================================
-- ⚠️ ESTE ARCHIVO ES OPCIONAL Y ES UN SANEO DE DATOS, NO UN CAMBIO DE ESQUEMA.
-- Nada del código Dart depende de él. Córrelo solo si el módulo de Cuentas por
-- pagar muestra compras "vencidas" que nunca tuvieron plazo pactado.
--
-- Qué pasó: la app calculaba due_date = purchase_date + payment_terms_days.
-- Cuando el proveedor no tenía plazo pactado, payment_terms_days era 0 (el
-- default de la columna), así que la compra quedó con due_date = purchase_date,
-- es decir "vence hoy mismo" → aparece vencida desde el día uno.
--
-- HEURÍSTICA (y su límite): limpiamos due_date solo en compras donde se dan
-- las TRES condiciones a la vez:
--   · el proveedor tiene payment_terms_days = 0 (sin plazo pactado),
--   · due_date es exactamente igual a purchase_date,
--   · todavía hay saldo (balance_due > 0).
--
-- El riesgo: si alguna compra vencía LEGÍTIMAMENTE el mismo día de la compra
-- (contado con fecha límite ese día) contra un proveedor sin plazo pactado,
-- esta consulta le borra la fecha de vencimiento. No hay forma de distinguir
-- ese caso del bug mirando solo los datos. Si eso te importa, revisa primero
-- con el SELECT de diagnóstico de abajo antes de correr el UPDATE.
--
-- Diagnóstico (correr suelto, fuera de la transacción, para ver qué se afecta):
--   select p.id, p.purchase_date, p.due_date, p.balance_due,
--          coalesce(s.trade_name, s.legal_name) as proveedor
--     from public.purchases p
--     join public.suppliers s
--       on s.id = p.supplier_id and s.branch_id = p.branch_id
--    where coalesce(s.payment_terms_days, 0) = 0
--      and p.due_date = p.purchase_date
--      and p.balance_due > 0;
--
-- Idempotente: tras correrlo, due_date queda null y la condición ya no matchea.
-- ============================================================================

begin;

update public.purchases p
   set due_date = null
  from public.suppliers s
 where s.id = p.supplier_id
   and s.branch_id = p.branch_id
   and coalesce(s.payment_terms_days, 0) = 0
   and p.due_date = p.purchase_date
   and p.balance_due > 0;

commit;

notify pgrst, 'reload schema';
