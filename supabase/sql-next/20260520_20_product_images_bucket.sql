-- Bucket público para imágenes de productos (Supabase Storage).
--
-- Diseño:
--   - Bucket 'product_images' público (lectura abierta).
--   - Subida/actualización/borrado: solo usuarios autenticados.
--   - Path convencional: <branch_id>/<product_id>-<timestamp>.<ext>
--
-- Ejecutar después de los anteriores 01-19. Idempotente.

begin;

-- 1) Crear bucket si no existe.
insert into storage.buckets (id, name, public)
values ('product_images', 'product_images', true)
on conflict (id) do update set public = excluded.public;

-- 2) Políticas RLS sobre storage.objects para este bucket.
--    Limpiamos primero por idempotencia.
drop policy if exists "product_images_read" on storage.objects;
drop policy if exists "product_images_insert" on storage.objects;
drop policy if exists "product_images_update" on storage.objects;
drop policy if exists "product_images_delete" on storage.objects;

-- Lectura pública (bucket público).
create policy "product_images_read"
  on storage.objects for select
  using (bucket_id = 'product_images');

-- Insertar: usuarios autenticados.
create policy "product_images_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'product_images');

-- Actualizar: usuarios autenticados.
create policy "product_images_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'product_images')
  with check (bucket_id = 'product_images');

-- Borrar: usuarios autenticados.
create policy "product_images_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'product_images');

commit;
