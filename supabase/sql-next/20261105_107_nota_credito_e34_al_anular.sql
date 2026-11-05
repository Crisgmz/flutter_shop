-- ============================================================================
-- Migración 107 — Nota de crédito E34 automática al anular un e-CF
-- ============================================================================
-- Una e-CF que la DGII ya aceptó NO se "desanula": la única forma de
-- reversarla es una nota de crédito electrónica (E34) que la referencie. Hasta
-- ahora anular una venta electrónica solo la marcaba anulada aquí, y ante la
-- DGII seguía siendo una venta (caso Maranatha, 5 nov 2026: E310000000001 y
-- E320000000001 anuladas y refacturadas en B01/B02 → ingreso declarado dos
-- veces).
--
-- Portado de mangospos (`fn_issue_credit_note`, migraciones 20260903_0001,
-- 20260917_0005 y 20261104_0002) a las tablas de este POS. Diferencia de
-- regla, decidida por el dueño el 5 nov 2026: aquí lleva nota TODA e-CF
-- aceptada que se anule (E31, E32, E44, E45), no solo crédito fiscal.
--
-- Qué hace:
--   1. fiscal_documents: related_document_id (la nota apunta a lo que anula),
--      modification_code (CodigoModificacion DGII) y modification_reason.
--   2. fn_issue_credit_note(doc, motivo, código): emite la E34 con los montos
--      EXACTOS del original (con código 1 la DGII exige el mismo total), la
--      pone en la cola de emit-document y marca el original anulado. NUNCA
--      tumba la anulación: sin secuencia devuelve 'no_sequence' y la nota
--      queda pendiente (v_fiscal_docs_pending_credit_note).
--   3. Disparadores: al anular la VENTA (sales.status → voided) o el
--      COMPROBANTE (fiscal_documents.voided_at), desde cualquiera de las dos
--      apps, se llama solo.
--   4. La E34 solo la entrega fn_issue_credit_note: `assign_next_ncf(…,
--      'credit_note')` ya no devuelve serie E. Sin esto, la devolución de
--      shop-plus (process_return) tomaría la E34 en modalidad híbrida y no la
--      emitiría. Las devoluciones de ventas e-CF siguen sin E34 (pendiente).
--   5. La regla de la 106 ya no bloquea la E34: basta con que sea de tipo
--      'credit_note' (el mapa prefijo → tipo sigue).
--   6. Datos: las E34 que quedaron como 'fiscal_credit' pasan a
--      'credit_note', y las secuencias E cargadas desde la tarjeta (que solo
--      tenían max_number) ganan sequence_end: assign_next_ncf mira
--      sequence_end y, sin él, pasaba del final del rango autorizado.
--
-- ANTES: correr SOLA, en su propia pestaña y sin begin/commit (Postgres no
-- deja usar un valor nuevo de enum en la misma transacción que lo crea):
--
--   alter type public.receipt_type add value if not exists 'credit_note';
--
-- Base COMPARTIDA con shop-plus: aplica a las dos apps. Idempotente.
-- ============================================================================

begin;

do $$
begin
  if not exists (
    select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
     where t.typname = 'receipt_type' and e.enumlabel = 'credit_note'
  ) then
    raise exception 'Falta el tipo credit_note. Corre primero, sola: alter type public.receipt_type add value if not exists ''credit_note'';';
  end if;
end $$;

-- ── 1. Columnas de la nota ──────────────────────────────────────────────────

alter table public.fiscal_documents
  add column if not exists related_document_id uuid
    references public.fiscal_documents(id) on delete set null,
  add column if not exists modification_code   smallint,
  add column if not exists modification_reason text;

alter table public.fiscal_documents
  drop constraint if exists fiscal_documents_modification_code_check,
  add constraint fiscal_documents_modification_code_check
    check (modification_code is null or modification_code between 1 and 5);

create index if not exists fiscal_documents_related_document_idx
  on public.fiscal_documents (related_document_id)
  where related_document_id is not null;

comment on column public.fiscal_documents.related_document_id is
  'En una nota de crédito (E34): el comprobante que anula.';
comment on column public.fiscal_documents.modification_code is
  'CodigoModificacion DGII de la nota: 1 anula el e-CF de referencia, 2 corrige '
  'texto, 3 corrige montos, 4 reemplaza uno de contingencia, 5 referencia consumo.';
comment on column public.fiscal_documents.modification_reason is
  'RazonModificacion: el motivo de la anulación.';

-- ── 2. Datos: tipo de las E34 y fin de rango de las secuencias E ────────────

update public.ncf_sequences
   set receipt_type = 'credit_note'::text::public.receipt_type
 where upper(left(trim(prefix), 3)) = 'E34'
   and receipt_type::text <> 'credit_note';

update public.ncf_sequences
   set sequence_end = max_number
 where upper(left(trim(prefix), 1)) = 'E'
   and sequence_end is null
   and max_number is not null;

-- ── 3. Regla de la 106: la E34 ya se puede activar (como nota de crédito) ───

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

  v_expected := public.fn_ncf_prefix_receipt_type(new.prefix);
  if v_expected is not null and new.receipt_type::text <> v_expected then
    raise exception 'El prefijo % es de tipo %, no de %. Elige el tipo de comprobante que corresponde.',
      v_series, v_expected, new.receipt_type
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

-- ── 4. assign_next_ncf: 'credit_note' nunca da serie E ──────────────────────
-- Se parchea la función VIVA (no se reescribe de memoria): se busca el filtro
-- de modalidad y se le agrega la condición. Si no se reconoce, no se toca nada.

do $$
declare
  v_src    text;
  v_marker constant text := E'         else true\n       end\n     )';
  v_extra  constant text := E'\n     -- La E34 solo la entrega fn_issue_credit_note (migración 107): una\n     -- devolución que la tomara aquí la gastaría sin emitirla.\n     and not (p_receipt_type::text = ''credit_note'' and prefix like ''E%'')';
begin
  select p.prosrc into v_src
    from pg_proc p
   where p.oid = 'public.assign_next_ncf(uuid, public.receipt_type)'::regprocedure;

  if position('credit_note' in v_src) > 0 then
    raise notice 'assign_next_ncf ya excluye la serie E para notas de crédito.';
  elsif position(v_marker in v_src) = 0 then
    raise exception 'No reconozco assign_next_ncf (falta el filtro de modalidad de la migración 63). No toco nada.';
  else
    v_src := replace(v_src, v_marker, v_marker || v_extra);
    execute format(
      'create or replace function public.assign_next_ncf(p_branch_id uuid, p_receipt_type public.receipt_type) '
      'returns text language plpgsql security definer set search_path = public as %L',
      v_src
    );
    raise notice 'assign_next_ncf: la serie E ya no sale para notas de crédito.';
  end if;
end $$;

-- ── 5. fn_issue_credit_note ─────────────────────────────────────────────────

create or replace function public.fn_issue_credit_note(
  p_fiscal_document_id uuid,
  p_reason text default null,
  p_modification_code smallint default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_doc      public.fiscal_documents%rowtype;
  v_existing record;
  v_seq      record;
  v_end      bigint;
  v_next     bigint;
  v_ncf      text;
  v_note_id  uuid;
  v_company  uuid;
  v_attempts integer := 0;
  v_reason   text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  select * into v_doc
    from public.fiscal_documents
   where id = p_fiscal_document_id
   for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;

  -- auth.uid() es null con service_role (SQL Editor, cron): el llamador ya es
  -- de confianza.
  if auth.uid() is not null and not public.has_branch_access(v_doc.branch_id) then
    raise exception 'Sin acceso a la sucursal del comprobante' using errcode = '42501';
  end if;

  -- Papel: se declara anulado en el 608, sin nota.
  if left(coalesce(v_doc.ncf, ''), 1) <> 'E' then
    return jsonb_build_object('status', 'not_applicable', 'reason', 'no_electronico');
  end if;

  -- Una nota no se anula con otra nota.
  if v_doc.receipt_type::text = 'credit_note' or upper(left(v_doc.ncf, 3)) in ('E33', 'E34') then
    return jsonb_build_object('status', 'not_applicable', 'reason', 'es_nota');
  end if;

  -- Incierto: pudo llegar a Alanube. Se resuelve primero en Comprobantes.
  if coalesce(v_doc.ecf_status, '') = 'uncertain' then
    return jsonb_build_object('status', 'uncertain');
  end if;

  -- Rechazado o nunca enviado: para la DGII no existe, no hay nada que
  -- reversar (y Alanube rechaza la nota de un documento que no conoce).
  if coalesce(v_doc.ecf_status, '') = 'rejected' then
    return jsonb_build_object('status', 'not_applicable', 'reason', 'rechazado');
  end if;
  if v_doc.alanube_document_id is null then
    return jsonb_build_object('status', 'not_applicable', 'reason', 'no_enviado');
  end if;

  -- Idempotencia: la misma factura no lleva dos notas (la UI y los dos
  -- disparadores pueden caer aquí).
  select id, ncf into v_existing
    from public.fiscal_documents
   where related_document_id = v_doc.id
     and fiscal_status::text <> 'voided'
   order by created_at desc
   limit 1;
  if found then
    return jsonb_build_object('status', 'already_issued', 'credit_note_id', v_existing.id, 'ncf', v_existing.ncf);
  end if;

  -- La E34 es de la sucursal que emitió el original, sea cual sea la
  -- modalidad de hoy: un e-CF solo se reversa con otro e-CF.
  select s.* into v_seq
    from public.ncf_sequences s
   where s.branch_id = v_doc.branch_id
     and upper(left(trim(s.prefix), 3)) = 'E34'
     and s.receipt_type::text = 'credit_note'
     and s.is_active
     and coalesce(s.status, 'active') = 'active'
     and (s.expires_on is null or s.expires_on >= current_date)
   order by s.updated_at desc
   limit 1
   for update;
  if not found then
    return jsonb_build_object('status', 'no_sequence', 'branch_id', v_doc.branch_id);
  end if;

  v_end := coalesce(v_seq.sequence_end, v_seq.max_number);
  v_next := coalesce(
    v_seq.next_number,
    greatest(coalesce(v_seq.sequence_start, 1), coalesce(v_seq.current_number, 0) + 1)
  );

  loop
    if v_end is not null and v_next > v_end then
      return jsonb_build_object('status', 'no_sequence', 'reason', 'agotada', 'branch_id', v_doc.branch_id);
    end if;
    v_ncf := upper(left(trim(v_seq.prefix), 3)) || lpad(v_next::text, 10, '0');
    begin
      insert into public.fiscal_documents (
        branch_id, sale_id, client_id, ncf_sequence_id, receipt_type,
        ncf, sequence_number, fiscal_status, issued_at, expires_on,
        customer_name, customer_document_type, customer_document_number, customer_address,
        issuer_name, issuer_tax_id, issuer_address,
        subtotal, discount_amount, taxable_amount, exempt_amount, tax_amount,
        service_charge_amount, total_amount, payload,
        related_document_id, modification_code, modification_reason
      ) values (
        v_doc.branch_id, v_doc.sale_id, v_doc.client_id, v_seq.id,
        'credit_note'::text::public.receipt_type,
        v_ncf, v_next, 'pending', timezone('utc', now()), v_seq.expires_on,
        v_doc.customer_name, v_doc.customer_document_type, v_doc.customer_document_number,
        v_doc.customer_address,
        v_doc.issuer_name, v_doc.issuer_tax_id, v_doc.issuer_address,
        -- Montos EXACTOS: con código 1 la DGII exige el mismo total (AP3014).
        v_doc.subtotal, v_doc.discount_amount, v_doc.taxable_amount, v_doc.exempt_amount,
        v_doc.tax_amount, v_doc.service_charge_amount, v_doc.total_amount,
        jsonb_build_object('original_ncf', v_doc.ncf, 'original_document_id', v_doc.id),
        v_doc.id, coalesce(p_modification_code, 1), v_reason
      )
      returning id into v_note_id;
      exit;
    exception when unique_violation then
      -- Ese e-NCF ya existe en la sucursal: el siguiente.
      v_attempts := v_attempts + 1;
      if v_attempts >= 20 then
        raise exception 'Demasiadas colisiones de e-NCF al emitir la nota de crédito' using errcode = 'P0001';
      end if;
      v_next := v_next + 1;
    end;
  end loop;

  update public.ncf_sequences
     set current_number = v_next,
         next_number    = v_next + 1,
         updated_at     = timezone('utc', now())
   where id = v_seq.id;

  -- A la cola aunque la modalidad esté en 'physical' (el disparador de
  -- encolado la salta en ese caso): un e-CF aceptado se reversa siempre.
  select company_id into v_company from public.branches where id = v_doc.branch_id;
  insert into public.ecf_emit_outbox (fiscal_document_id, branch_id, company_id)
  values (v_note_id, v_doc.branch_id, v_company)
  on conflict (fiscal_document_id) do nothing;

  update public.fiscal_documents
     set fiscal_status = 'voided',
         voided_at     = coalesce(voided_at, timezone('utc', now())),
         void_reason   = coalesce(void_reason, v_reason)
   where id = v_doc.id;

  return jsonb_build_object(
    'status', 'issued',
    'credit_note_id', v_note_id,
    'ncf', v_ncf,
    'original_ncf', v_doc.ncf
  );
end;
$function$;

revoke all on function public.fn_issue_credit_note(uuid, text, smallint) from public, anon;
grant execute on function public.fn_issue_credit_note(uuid, text, smallint) to authenticated, service_role;

comment on function public.fn_issue_credit_note(uuid, text, smallint) is
  'Emite la nota de crédito E34 de un e-CF aceptado que se anula (montos exactos, '
  'código 1) y la encola en emit-document. Nunca falla la anulación: devuelve '
  'issued | already_issued | no_sequence | uncertain | not_applicable.';

-- ── 6. Disparadores: anular la venta o el comprobante emite la nota ────────

create or replace function public.tg_sales_void_issue_credit_notes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  if new.status::text <> 'voided' or old.status::text = 'voided' then
    return new;
  end if;
  for r in
    select fd.id
      from public.fiscal_documents fd
     where fd.sale_id = new.id
       and left(fd.ncf, 1) = 'E'
       and fd.receipt_type::text <> 'credit_note'
       and fd.related_document_id is null
  loop
    begin
      perform public.fn_issue_credit_note(
        r.id, 'Anulación de la venta ' || coalesce(new.sale_number, ''), 1::smallint);
    exception when others then
      -- La anulación NO se tumba: la nota queda en v_fiscal_docs_pending_credit_note.
      raise warning 'No se pudo emitir la nota de crédito del comprobante %: %', r.id, sqlerrm;
    end;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_sales_void_issue_credit_notes on public.sales;
create trigger trg_sales_void_issue_credit_notes
after update of status on public.sales
for each row
when (new.status is distinct from old.status)
execute function public.tg_sales_void_issue_credit_notes();

create or replace function public.tg_fiscal_documents_void_issue_credit_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Anidado (lo disparó fn_issue_credit_note al marcar el original): ya se emitió.
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  if new.voided_at is null or old.voided_at is not null
     or left(new.ncf, 1) <> 'E' or new.receipt_type::text = 'credit_note' then
    return new;
  end if;
  begin
    perform public.fn_issue_credit_note(new.id, new.void_reason, 1::smallint);
  exception when others then
    raise warning 'No se pudo emitir la nota de crédito del comprobante %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_fiscal_documents_void_issue_credit_note on public.fiscal_documents;
create trigger trg_fiscal_documents_void_issue_credit_note
after update of voided_at on public.fiscal_documents
for each row
execute function public.tg_fiscal_documents_void_issue_credit_note();

-- ── 7. Anuladas que se quedaron sin nota ────────────────────────────────────

create or replace view public.v_fiscal_docs_pending_credit_note
with (security_invoker = true) as
select fd.id,
       fd.branch_id,
       fd.sale_id,
       fd.ncf,
       fd.receipt_type,
       fd.ecf_status,
       fd.total_amount,
       coalesce(fd.voided_at, s.updated_at) as voided_at,
       fd.void_reason
  from public.fiscal_documents fd
  left join public.sales s on s.id = fd.sale_id
 where left(fd.ncf, 1) = 'E'
   and fd.receipt_type::text <> 'credit_note'
   and (fd.voided_at is not null or s.status::text = 'voided')
   and fd.alanube_document_id is not null
   and coalesce(fd.ecf_status, '') not in ('rejected', 'uncertain')
   and not exists (
     select 1 from public.fiscal_documents n
      where n.related_document_id = fd.id
        and n.fiscal_status::text <> 'voided'
   );

comment on view public.v_fiscal_docs_pending_credit_note is
  'e-CF aceptados y anulados que todavía NO tienen nota de crédito E34. Casi '
  'siempre falta cargar/activar la secuencia E34 de la sucursal: después se '
  'emite con select fn_issue_credit_note(id, motivo).';

grant select on public.v_fiscal_docs_pending_credit_note to authenticated;

commit;

notify pgrst, 'reload schema';
