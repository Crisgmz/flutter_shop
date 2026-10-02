-- ============================================================================
-- Migración 95 — Quita la `edit_sale_transactional` duplicada (deshace la 93)
-- ============================================================================
-- SÍNTOMA (2 oct 2026): al guardar cualquier venta en "Editar venta":
--
--   Could not choose the best candidate function between:
--     public.edit_sale_transactional(p_sale_id, p_items, p_client_id,
--       p_clear_client, p_notes, p_clear_notes)
--     public.edit_sale_transactional(..., p_honor_client_tax boolean)
--
-- CAUSA: esta base la comparten flutter_shop+ y shop-plus. La función viva es
-- la de shop-plus (migraciones 91/97/99, 7 parámetros; el último,
-- `p_honor_client_tax`, con default). La 93 de este árbol se escribió con la
-- firma vieja de 6 parámetros: `create or replace` no la reemplazó, creó una
-- SEGUNDA función, y una llamada con 6 parámetros encaja en las dos.
--
-- ARREGLO: borrar la de 6 parámetros. Las llamadas vuelven a resolver a la de
-- shop-plus, que es la que se usaba antes de la 93. Esa ya trae la regla de
-- stock de la 87 (solo bloquea si la edición pide MÁS de lo que la venta
-- tenía y "No permitir venta sin stock" está prendido) y además arregla el
-- inventario doble al editar.
--
-- Si la de 7 parámetros no existiera, aborta sin borrar nada, para no dejar
-- la base sin función de editar.
--
-- NO volver a correr la 87 ni la 93 de este árbol: las dos recrean la de 6.
--
-- Idempotente. Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

begin;

do $$
begin
  if to_regprocedure(
       'public.edit_sale_transactional(uuid, jsonb, uuid, boolean, text, boolean, boolean)'
     ) is null then
    raise exception
      'No existe edit_sale_transactional de 7 parámetros (shop-plus 91/97/99). No se borra la de 6.';
  end if;
end $$;

drop function if exists public.edit_sale_transactional(
  uuid, jsonb, uuid, boolean, text, boolean
);

commit;

notify pgrst, 'reload schema';
