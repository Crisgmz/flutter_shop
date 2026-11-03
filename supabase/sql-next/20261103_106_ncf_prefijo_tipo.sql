-- ============================================================================
-- Migración 106 — El prefijo de una secuencia NCF tiene que ser de su tipo
-- ============================================================================
-- Bug (3 nov 2026): "Cargar secuencia e-NCF" dejaba cargar E34 (nota de
-- crédito) y la guardaba con receipt_type = 'fiscal_credit'. Con e-CF
-- encendido, `assign_next_ncf(…, 'fiscal_credit')` elige la serie E con el
-- número siguiente más bajo: la E34 empata con la E31 en el 1 y una factura de
-- crédito fiscal podía salir como E340000000001 (número gastado, rechazo de la
-- DGII: una E34 tiene que citar la factura que modifica).
--
-- Tampoco basta con guardarla como 'credit_note': la devolución de shop-plus
-- (`process_return` → `assign_next_ncf(…, 'credit_note')`) la tomaría antes
-- que la B04 en modalidad híbrida, y ninguna app emite todavía la E34: el
-- e-NCF quedaría usado sin llegar nunca a la DGII.
--
-- Esta migración:
--   1. Desactiva las secuencias E34 que haya (no las borra: conserva el
--      historial y se pueden reactivar cuando exista la emisión de E34).
--   2. Disparador en ncf_sequences: una secuencia ACTIVA tiene que tener el
--      receipt_type que corresponde a su prefijo DGII (B01/E31 crédito fiscal,
--      B02/E32 consumo, B04 nota de crédito, B14/E44 especial,
--      B15/E45 gubernamental, B16/E46 exportación), y la E34 no puede estar
--      activa. Prefijos fuera de esa lista no se tocan.
--
-- El disparador solo mira INSERT y UPDATE de prefix, receipt_type o is_active:
-- `assign_next_ncf` actualiza current_number / next_number y no lo dispara, así
-- que una secuencia vieja mal clasificada no frena ninguna venta. Esas se
-- listan abajo (aviso) para revisarlas a mano.
--
-- Base COMPARTIDA con shop-plus: aplica a las dos apps (es lo que se quiere).
-- Idempotente.
-- ============================================================================

begin;

-- ── 1. E34 fuera ────────────────────────────────────────────────────────────

do $$
declare
  v_count integer;
begin
  update public.ncf_sequences
     set is_active = false
   where upper(left(trim(prefix), 3)) = 'E34'
     and is_active;
  get diagnostics v_count = row_count;
  raise notice 'Secuencias E34 desactivadas: %', v_count;
end $$;

-- ── 2. Prefijo ↔ tipo ───────────────────────────────────────────────────────

create or replace function public.fn_ncf_prefix_receipt_type(p_prefix text)
returns text
language sql
immutable
as $$
  select case upper(left(trim(coalesce(p_prefix, '')), 3))
    when 'B01' then 'fiscal_credit'
    when 'E31' then 'fiscal_credit'
    when 'B02' then 'consumer_final'
    when 'E32' then 'consumer_final'
    when 'B04' then 'credit_note'
    when 'E34' then 'credit_note'
    when 'B14' then 'special'
    when 'E44' then 'special'
    when 'B15' then 'governmental'
    when 'E45' then 'governmental'
    when 'B16' then 'export'
    when 'E46' then 'export'
    else null
  end
$$;

comment on function public.fn_ncf_prefix_receipt_type(text) is
  'receipt_type que corresponde a un prefijo NCF/e-NCF de la DGII; null si no es uno conocido.';

create or replace function public.tg_ncf_sequences_prefix_matches_type()
returns trigger
language plpgsql
as $$
declare
  v_expected text;
  v_series   text := upper(left(trim(coalesce(new.prefix, '')), 3));
begin
  if not new.is_active then
    return new;
  end if;

  if v_series = 'E34' then
    raise exception 'La nota de crédito electrónica (E34) todavía no se emite: no se puede activar esa secuencia.'
      using errcode = 'P0001';
  end if;

  v_expected := public.fn_ncf_prefix_receipt_type(new.prefix);
  if v_expected is not null and new.receipt_type::text <> v_expected then
    raise exception 'El prefijo % es de tipo %, no de %. Elige el tipo de comprobante que corresponde.',
      v_series, v_expected, new.receipt_type
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ncf_sequences_prefix_matches_type on public.ncf_sequences;
create trigger trg_ncf_sequences_prefix_matches_type
before insert or update of prefix, receipt_type, is_active on public.ncf_sequences
for each row execute function public.tg_ncf_sequences_prefix_matches_type();

-- ── 3. Aviso: secuencias activas que ya estaban mal clasificadas ────────────

do $$
declare
  r record;
  v_any boolean := false;
begin
  for r in
    select s.id, s.branch_id, s.prefix, s.receipt_type,
           public.fn_ncf_prefix_receipt_type(s.prefix) as expected
      from public.ncf_sequences s
     where s.is_active
       and public.fn_ncf_prefix_receipt_type(s.prefix) is not null
       and s.receipt_type::text <> public.fn_ncf_prefix_receipt_type(s.prefix)
  loop
    v_any := true;
    raise notice 'Revisar: secuencia % (sucursal %) prefijo % está como %, debería ser %',
      r.id, r.branch_id, r.prefix, r.receipt_type, r.expected;
  end loop;
  if not v_any then
    raise notice 'Ninguna secuencia activa mal clasificada.';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
