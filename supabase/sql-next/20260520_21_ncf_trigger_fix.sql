-- Fix: `tg_sales_register_fiscal_document` fallaba con
--   PostgrestException(message: record "v_client" is not assigned yet,
--                       code: 55000, ...)
-- al completar ventas con NCF cuando el cliente no estaba seleccionado
-- (o cuando el SELECT no encontraba fila).
--
-- Causa raíz: `v_client record` declarado sin asignar siempre. Cuando
-- `new.client_id is null` el SELECT INTO no se ejecuta, y el INSERT
-- posterior lee `v_client.field` sobre un record indeterminado.
--
-- Arreglo: reemplazar el record por variables escalares que defaultan a
-- NULL. Mismo fix para `v_settings` por defensa.

begin;

create or replace function public.tg_sales_register_fiscal_document()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq_id              uuid;
  v_seq_number          bigint;
  v_customer_name       text;
  v_customer_legal_name text;
  v_customer_doc_type   text;
  v_customer_doc_number text;
  v_customer_address    text;
  v_issuer_name         text;
  v_issuer_legal_name   text;
  v_issuer_tax_id       text;
begin
  if new.ncf is null or length(trim(new.ncf)) = 0 then
    return new;
  end if;

  -- Localizar la secuencia que produjo este NCF (por prefijo + tipo)
  select id
    into v_seq_id
    from public.ncf_sequences
   where branch_id = new.branch_id
     and receipt_type = new.receipt_type
     and new.ncf like prefix || '%'
   order by current_number desc
   limit 1;

  -- Extraer la parte numérica del NCF
  begin
    v_seq_number := (regexp_replace(new.ncf, '\D', '', 'g'))::bigint;
  exception when others then
    v_seq_number := null;
  end;

  -- Snapshot del cliente (solo si hay client_id). Las variables escalares
  -- quedan en NULL si no hay match.
  if new.client_id is not null then
    select c.full_name,
           c.legal_name,
           c.document_type::text,
           c.document_number,
           c.address
      into v_customer_name,
           v_customer_legal_name,
           v_customer_doc_type,
           v_customer_doc_number,
           v_customer_address
      from public.clients c
     where c.id = new.client_id
       and c.branch_id = new.branch_id;
  end if;

  -- Snapshot del emisor
  select company_name, company_legal_name, company_tax_id
    into v_issuer_name, v_issuer_legal_name, v_issuer_tax_id
    from public.app_settings
   where id = 1;

  insert into public.fiscal_documents (
    branch_id, sale_id, client_id, ncf_sequence_id, receipt_type,
    ncf, sequence_number, fiscal_status, issued_at,
    customer_name, customer_document_type, customer_document_number, customer_address,
    issuer_name, issuer_tax_id,
    subtotal, discount_amount, tax_amount, total_amount,
    payload
  ) values (
    new.branch_id, new.id, new.client_id, v_seq_id, new.receipt_type,
    new.ncf, v_seq_number, 'pending'::public.dgii_status, new.sale_date,
    coalesce(nullif(v_customer_legal_name, ''), v_customer_name),
    v_customer_doc_type,
    v_customer_doc_number,
    v_customer_address,
    coalesce(nullif(v_issuer_legal_name, ''), v_issuer_name),
    v_issuer_tax_id,
    new.subtotal, new.discount_amount, new.tax_amount, new.total_amount,
    jsonb_build_object('sale_number', new.sale_number)
  )
  on conflict (branch_id, ncf) do nothing;

  return new;
end;
$$;

commit;
