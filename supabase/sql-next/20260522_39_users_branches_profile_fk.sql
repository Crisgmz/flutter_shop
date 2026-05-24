-- Fix: PostgREST no detecta relación users_branches → profiles.
--
-- Síntoma:
--   En /sucursales, al cargar la lista de miembros de una sucursal, la
--   app falla con:
--     PostgrestException(
--       message: "Could not find a relationship between 'users_branches'
--       and 'profiles' in the schema cache",
--       code: PGRST200,
--       hint: "Perhaps you meant 'branches' instead of 'profiles'."
--     )
--
-- Causa raíz:
--   El query usa embedded select de PostgREST:
--     .from('users_branches').select('..., profiles(full_name, email, ...)')
--   PostgREST necesita una FK directa entre users_branches.user_id y
--   profiles.id para hacer el join. Pero el schema original solo tiene:
--     users_branches.user_id → auth.users(id)
--     profiles.id            → auth.users(id)
--   Ambas apuntan al mismo destino, pero NO una a la otra. PostgREST no
--   puede inferir la relación.
--
-- Fix:
--   Agregar una FK explícita users_branches.user_id → profiles.id. Es
--   lógicamente correcta: por el trigger handle_auth_user_upsert(), cada
--   user_id en users_branches tiene siempre un profile con ese id.
--
--   Después de aplicar esta migration y reiniciar PostgREST (notify pgrst),
--   los queries con embedded select funcionan.
--
-- Idempotente.

begin;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'users_branches_user_profile_fk'
      and conrelid = 'public.users_branches'::regclass
  ) then
    alter table public.users_branches
      add constraint users_branches_user_profile_fk
      foreign key (user_id)
      references public.profiles(id)
      on delete cascade;
  end if;
end $$;

-- Forzar reload del schema cache de PostgREST para que detecte la FK
-- recién agregada.
notify pgrst, 'reload schema';

commit;
