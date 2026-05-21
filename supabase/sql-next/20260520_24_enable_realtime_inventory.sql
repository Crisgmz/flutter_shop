-- 20260520_24_enable_realtime_inventory.sql
-- Habilitar actualizaciones en tiempo real para la tabla de productos y categorías de productos de forma segura.

do $$
begin
  -- Asegurar que la publicación supabase_realtime exista
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end;
$$;

-- Intentar agregar la tabla products a la publicación
do $$
begin
  alter publication supabase_realtime add table public.products;
exception
  when duplicate_object then
    null;
end;
$$;

-- Intentar agregar la tabla product_categories a la publicación
do $$
begin
  alter publication supabase_realtime add table public.product_categories;
exception
  when duplicate_object then
    null;
end;
$$;
