-- Activar Supabase Realtime para las tablas operativas core.
--
-- Después de esta migration, INSERT/UPDATE/DELETE en estas tablas se
-- emiten al canal `supabase_realtime`. El cliente Flutter se suscribe
-- vía RealtimeInvalidator (lib/core/realtime/realtime_invalidator.dart)
-- y al recibir un evento invalida el provider correspondiente.
--
-- Tablas incluidas (MVP):
--   - sales            → invalida salesHistory, dashboard, cobros
--   - payments         → invalida cobros, cash_register
--   - cash_sessions    → invalida cash_register, dashboard
--   - cash_register_movements → invalida cash_register
--   - clients          → invalida clientsList, cobros
--   - returns          → invalida sales, dashboard
--
-- products y product_categories ya están en realtime desde migration 24.
--
-- Idempotente: cada ALTER PUBLICATION captura duplicate_object.

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

do $$ begin alter publication supabase_realtime add table public.sales;
  exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.payments;
  exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.cash_sessions;
  exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.cash_register_movements;
  exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.clients;
  exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.returns;
  exception when duplicate_object then null; end $$;
