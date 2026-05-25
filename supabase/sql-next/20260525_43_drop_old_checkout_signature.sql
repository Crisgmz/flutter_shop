-- Fix de PGRST203: function overloading sin resolución.
--
-- La migration 42 creó una nueva versión de checkout_sale_transactional
-- con un parámetro extra (p_cash_session_id), pero la versión vieja de
-- 7 parámetros sigue existiendo. Cuando el cliente llama con los 7
-- parámetros base, PostgREST encuentra DOS candidatas y rechaza:
--
--   "Could not choose the best candidate function between:
--    public.checkout_sale_transactional(jsonb, text, boolean, text, uuid, text, integer),
--    public.checkout_sale_transactional(jsonb, text, boolean, text, uuid, text, integer, uuid)"
--
-- Solución: drop explícito de la versión vieja. Solo queda la nueva,
-- en la que p_cash_session_id es nullable y default null — así los
-- clientes viejos siguen funcionando sin pasar el parámetro extra.

begin;

drop function if exists public.checkout_sale_transactional(
  jsonb, text, boolean, text, uuid, text, integer
);

-- Sanity check: que la versión nueva siga existiendo. Si no existe,
-- significa que la migration 42 nunca se aplicó — abortar para que el
-- DBA lo note antes de dejar la app sin RPC.
do $$
begin
  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'checkout_sale_transactional'
       and pg_get_function_identity_arguments(p.oid) =
         'p_items jsonb, p_receipt_type text, p_as_credit boolean, p_payment_method text, p_client_id uuid, p_notes text, p_credit_due_days integer, p_cash_session_id uuid'
  ) then
    raise exception 'Migration 42 no está aplicada: la versión nueva de checkout_sale_transactional con p_cash_session_id no existe. Aplica primero 20260522_42_multiple_open_cash_sessions.sql.';
  end if;
end $$;

-- Force PostgREST schema cache reload.
notify pgrst, 'reload schema';

commit;
