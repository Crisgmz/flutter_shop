-- 20260601_46_realtime_replica_identity_full.sql
--
-- Fix: los eventos DELETE (y los valores "old" de UPDATE) de Supabase
-- Realtime solo incluyen la REPLICA IDENTITY de la tabla. Por defecto esa
-- identidad es la PRIMARY KEY, así que el payload de un DELETE NO trae
-- `branch_id`.
--
-- El cliente (RealtimeInvalidator) se suscribe con filtro
-- `branch_id=eq.<id>`. Como el DELETE no trae branch_id, el filtro lo
-- descarta y la UI NO se entera de los borrados (p. ej. al eliminar un
-- producto o cliente no desaparece solo en otras pestañas/dispositivos).
--
-- Solución: poner REPLICA IDENTITY FULL en las tablas que están en realtime,
-- para que el WAL incluya la fila completa (con branch_id) en DELETE/UPDATE.
--
-- Costo: REPLICA IDENTITY FULL aumenta un poco el tamaño del WAL en
-- UPDATE/DELETE. Para estas tablas operativas es despreciable y necesario
-- para que el filtrado por sucursal funcione en realtime.
--
-- Idempotente: ALTER ... REPLICA IDENTITY FULL se puede correr varias veces.
-- Mantener la lista sincronizada con `_tableToProviders` en
-- lib/core/realtime/realtime_invalidator.dart y con las migrations 24 y 41.

alter table public.products                 replica identity full;
alter table public.product_categories       replica identity full;
alter table public.sales                    replica identity full;
alter table public.payments                 replica identity full;
alter table public.cash_sessions            replica identity full;
alter table public.cash_register_movements  replica identity full;
alter table public.clients                  replica identity full;
alter table public.returns                  replica identity full;
