-- ============================================================================
-- Migración 112 — Preguntarle a Alanube por los e-CF que se quedan en 'sent'
-- ============================================================================
-- El resultado de la DGII (aceptado / rechazado) solo llegaba por el aviso de
-- Alanube (alanube-webhook), y el aviso se configura por empresa en Alanube.
-- El 27-nov: Maranatha tenía 48 e-CF en 'sent' desde el 05-nov y Soluciones
-- Plásticas 14 desde el 12-nov, sin un solo aviso en ecf_webhook_inbox (J COBO,
-- en cambio, recibía todos). La app los mostraba "en proceso" para siempre.
--
-- Qué hace:
--   1) fiscal_documents.ecf_status_checked_at: cuándo se le preguntó a Alanube
--      por última vez. ecf-status-sync consulta primero los que hace más que no
--      se consultan, así uno que la DGII tenga días «en proceso» no tapa a los
--      demás. Nula y sin default: no reescribe la tabla.
--   2) Cron ecf-status-sync cada 15 min: si hay e-CF en 'sent' enviados hace
--      más de 15 min (y emitidos en los últimos 45 días), llama a la función,
--      que revisa hasta 20 por vuelta. Si no hay ninguno, no llama.
--
-- URL y llave como ecf-emit-batch (migración 108): la pública del Supabase
-- propio y la anon (la misma de la app; no es un secreto). Base COMPARTIDA con
-- shop-plus.
--
-- ORDEN: correr esta migración y LUEGO desplegar ecf-status-sync (lee la
-- columna nueva). Mientras no esté desplegada, el runtime responde error cada
-- 15 min y no pasa nada más. Idempotente.
-- ============================================================================

set lock_timeout = '5s';

alter table public.fiscal_documents
  add column if not exists ecf_status_checked_at timestamptz;

comment on column public.fiscal_documents.ecf_status_checked_at is
  'Última vez que ecf-status-sync le preguntó a Alanube por este e-CF '
  '(aviso que no llegó). Migración 112.';

reset lock_timeout;

create extension if not exists pg_net;
create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'ecf-status-sync') then
    perform cron.unschedule('ecf-status-sync');
  end if;
end $$;

select cron.schedule(
  'ecf-status-sync',
  '*/15 * * * *',
  $job$
  select net.http_post(
    url     := 'https://supabase.busiposweb.com/functions/v1/ecf-status-sync',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3OTQ2MTI4MCwiZXhwIjo0OTM1MTM0ODgwLCJyb2xlIjoiYW5vbiJ9.CdZEf7Ux9iGEvc2TXl-hMTOyqpZ3AFTCiN7yD1saswI',
      'apikey',        'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3OTQ2MTI4MCwiZXhwIjo0OTM1MTM0ODgwLCJyb2xlIjoiYW5vbiJ9.CdZEf7Ux9iGEvc2TXl-hMTOyqpZ3AFTCiN7yD1saswI'
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 55000
  )
  where exists (
    select 1 from public.fiscal_documents fd
    where fd.ecf_status = 'sent'
      and fd.alanube_document_id is not null
      and fd.submitted_at < now() - interval '15 minutes'
      and fd.issued_at >= now() - interval '45 days'
  );
  $job$
);

-- Comprobar:
--   select jobid, jobname, schedule, active from cron.job where jobname = 'ecf-status-sync';
--   select status, return_message, start_time from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'ecf-status-sync')
--    order by start_time desc limit 5;
--   select ecf_status, count(*) from public.fiscal_documents
--    where ncf like 'E%' and issued_at > now() - interval '45 days' group by 1;
--
-- Pausar:  select cron.unschedule('ecf-status-sync');
-- Revertir: además  alter table public.fiscal_documents drop column ecf_status_checked_at;
--           (con la función ecf-status-sync ya retirada).
