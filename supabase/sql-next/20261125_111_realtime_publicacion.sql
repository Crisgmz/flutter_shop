-- ============================================================================
-- Migración 111 — Tiempo real encendido en todas las pantallas
-- ============================================================================
-- 25 nov 2026: el Panel ("Ventas Hoy", "Ventas del Mes") y la Caja no se
-- actualizaban solos con cada venta. La publicación `supabase_realtime` solo
-- tenía `payments`: sales, returns, cash_sessions, clients y products no
-- avisaban a ninguna pantalla abierta.
--
-- Misma lista que la 93 de shop-plus (20260916_93_realtime_todas_las_pantallas),
-- que es la fuente del conjunto completo: publica las 20 tablas operativas y
-- les pone REPLICA IDENTITY FULL (sin ella un DELETE no trae branch_id y el
-- filtro por sucursal lo descarta).
--
-- BASE COMPARTIDA con shop-plus: solo AGREGA tablas a la publicación. Realtime
-- entrega a cada usuario solo las filas que su RLS le deja leer. El costo es
-- algo más de WAL en los UPDATE y DELETE de estas tablas.
--
-- Tolerante: si una tabla no existe, la salta. Idempotente: se puede correr
-- varias veces y donde ya estaba no cambia nada.
--
-- Mantener sincronizado con `_tableToProviders` en
-- lib/core/realtime/realtime_invalidator.dart.
-- ============================================================================

begin;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

do $$
declare
  v_tabla     text;
  v_agregada  text[] := '{}';
  v_ya_habia  text[] := '{}';
  v_no_existe text[] := '{}';
begin
  foreach v_tabla in array array[
    -- Las que escucha esta app (Panel, Caja, Ventas, Cobros, Inventario).
    'products', 'product_categories',
    'sales', 'payments', 'returns', 'clients',
    'cash_sessions', 'cash_register_movements',
    -- Las demás pantallas (shop-plus las escucha).
    'cash_registers',
    'quotations', 'quotation_items',
    'purchases', 'purchase_items',
    'suppliers', 'expenses', 'supplier_payments',
    'petty_cash_sessions', 'petty_cash_movements', 'petty_cash_categories',
    'ncf_sequences'
  ] loop
    if to_regclass('public.' || v_tabla) is null then
      v_no_existe := v_no_existe || v_tabla;
      continue;
    end if;

    execute format('alter table public.%I replica identity full', v_tabla);

    begin
      execute format(
        'alter publication supabase_realtime add table public.%I', v_tabla
      );
      v_agregada := v_agregada || v_tabla;
    exception when duplicate_object then
      v_ya_habia := v_ya_habia || v_tabla;
    end;
  end loop;

  raise notice 'Realtime → agregadas: %  | ya estaban: %  | no existen (saltadas): %',
    v_agregada, v_ya_habia, v_no_existe;
end $$;

commit;

-- ── Verificación (solo lectura): deben salir las 20 ─────────────────────────
select tablename
  from pg_publication_tables
 where pubname = 'supabase_realtime'
   and schemaname = 'public'
   and tablename in (
     'products', 'product_categories', 'sales', 'payments', 'returns',
     'clients', 'cash_sessions', 'cash_register_movements', 'cash_registers',
     'quotations', 'quotation_items', 'purchases', 'purchase_items',
     'suppliers', 'expenses', 'supplier_payments', 'petty_cash_sessions',
     'petty_cash_movements', 'petty_cash_categories', 'ncf_sequences'
   )
 order by tablename;
