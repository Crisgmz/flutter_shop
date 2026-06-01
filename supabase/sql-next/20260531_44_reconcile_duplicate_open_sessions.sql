-- Conciliación de cuadres duplicados (preparación para la migration 44).
--
-- El bug de "abrir caja encima de otra" dejó cajas con 2 sesiones abiertas.
-- Esta limpieza, por cada caja con más de una sesión abierta:
--   - CONSERVA una sola sesión abierta: la que tiene actividad (más pagos);
--     si hay empate (todas vacías), la más antigua.
--   - CIERRA las demás SOLO si están vacías (0 ventas y 0 pagos).
--   - Si alguna sesión que se debería cerrar TIENE ventas/pagos, aborta:
--     ese caso requiere consolidación manual (no se pierde dinero en silencio).
--
-- Idempotente y seguro. Correr ANTES de 20260531_44_shared_register_sessions.sql.

begin;

do $$
declare
  r record;
  v_keeper uuid;
  v_conflict text;
begin
  -- 0) Detectar si alguna sesión NO conservada tiene actividad → abortar.
  select string_agg(
           format('caja=%s session=%s ventas=%s pagos=%s',
                  x.cash_register_id, x.id, x.ventas, x.pagos),
           E'\n')
    into v_conflict
  from (
    select cs.id, cs.cash_register_id,
           (select count(*) from public.sales s    where s.cash_session_id = cs.id) as ventas,
           (select count(*) from public.payments p where p.cash_session_id = cs.id) as pagos,
           row_number() over (
             partition by cs.branch_id, cs.cash_register_id
             order by
               (select count(*) from public.payments p where p.cash_session_id = cs.id) desc,
               cs.opened_at asc
           ) as rn
      from public.cash_sessions cs
     where cs.status = 'open'
       and cs.cash_register_id is not null
       and cs.cash_register_id in (
         select cash_register_id
           from public.cash_sessions
          where status = 'open' and cash_register_id is not null
          group by branch_id, cash_register_id
         having count(*) > 1
       )
  ) x
  where x.rn > 1                       -- las que se cerrarían
    and (x.ventas > 0 or x.pagos > 0); -- y tienen actividad

  if v_conflict is not null then
    raise exception E'Hay sesiones duplicadas CON actividad que se cerrarían. Requiere consolidación manual:\n%', v_conflict;
  end if;

  -- 1) Cerrar las sesiones sobrantes (vacías). Conserva la rn=1 por caja.
  for r in
    select x.id
      from (
        select cs.id,
               row_number() over (
                 partition by cs.branch_id, cs.cash_register_id
                 order by
                   (select count(*) from public.payments p where p.cash_session_id = cs.id) desc,
                   cs.opened_at asc
               ) as rn
          from public.cash_sessions cs
         where cs.status = 'open'
           and cs.cash_register_id is not null
           and cs.cash_register_id in (
             select cash_register_id
               from public.cash_sessions
              where status = 'open' and cash_register_id is not null
              group by branch_id, cash_register_id
             having count(*) > 1
           )
      ) x
     where x.rn > 1
  loop
    update public.cash_sessions
       set status = 'closed',
           closed_at = timezone('utc', now()),
           closing_amount = coalesce(expected_amount, 0),
           difference_amount = 0,
           notes = trim(both ' ' from
                     coalesce(notes, '') ||
                     ' [Cerrada automáticamente: sesión duplicada vacía conciliada el ' ||
                     to_char(timezone('utc', now()), 'YYYY-MM-DD HH24:MI') || ' UTC]')
     where id = r.id;
  end loop;
end $$;

commit;
