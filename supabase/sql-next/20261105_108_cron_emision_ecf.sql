-- ============================================================================
-- Migración 108 — Tarea programada que vacía la cola de e-CF cada minuto
-- ============================================================================
-- La cola `ecf_emit_outbox` solo se vaciaba cuando alguien llamaba a
-- `emit-document` (el POS al cobrar, o "Emitir a DGII" en Comprobantes). Lo
-- que quedaba pendiente —un reintento después de una caída de Alanube, o la
-- nota de crédito E34 que la migración 107 emite sola al anular una e-CF— no
-- salía nunca.
--
-- Esto programa `emit-document` en modo batch cada minuto (pg_cron + pg_net,
-- incluidos en el Postgres de Supabase). En batch, emit-document:
--   * toma hasta 10 trabajos con next_attempt_at vencido (con reintentos
--     espaciados: 1, 5, 15, 60, 240 minutos),
--   * recupera los reclamos vencidos (ecf_outbox_recover_stale, migración
--     101) sin reenviar a ciegas lo que pudo llegar a Alanube.
--
-- La URL es la pública del Supabase propio y la llave es la anon (la misma
-- que va en la app; no es un secreto). Base COMPARTIDA con shop-plus: la cola
-- es una sola. Idempotente: reprograma la tarea si ya existe.
-- ============================================================================

create extension if not exists pg_net;
create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'ecf-emit-batch') then
    perform cron.unschedule('ecf-emit-batch');
  end if;
end $$;

select cron.schedule(
  'ecf-emit-batch',
  '* * * * *',
  $job$
  select net.http_post(
    url     := 'https://supabase.busiposweb.com/functions/v1/emit-document',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3OTQ2MTI4MCwiZXhwIjo0OTM1MTM0ODgwLCJyb2xlIjoiYW5vbiJ9.CdZEf7Ux9iGEvc2TXl-hMTOyqpZ3AFTCiN7yD1saswI',
      'apikey',        'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3OTQ2MTI4MCwiZXhwIjo0OTM1MTM0ODgwLCJyb2xlIjoiYW5vbiJ9.CdZEf7Ux9iGEvc2TXl-hMTOyqpZ3AFTCiN7yD1saswI'
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $job$
);

-- Comprobar (después de 1-2 minutos):
--   select jobid, jobname, schedule, active from cron.job where jobname = 'ecf-emit-batch';
--   select status, return_message, start_time from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'ecf-emit-batch')
--    order by start_time desc limit 5;
--   select status_code, left(content::text, 200), created from net._http_response
--    order by created desc limit 5;
--
-- Pausar:  select cron.unschedule('ecf-emit-batch');
