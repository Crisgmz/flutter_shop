-- ============================================================================
-- Migración 98 — Saldo a favor del cliente (notas de crédito)
-- ============================================================================
-- PEDIDO (6 oct 2026): en una devolución quedan solo dos formas de reembolso:
--   · "Efectivo o consumir" (refund_method = 'cash'): sale de la gaveta.
--   · "Nota de crédito" (refund_method = 'credit_note'): NO sale dinero; el
--     monto queda como SALDO A FAVOR del cliente y el POS lo descuenta solo en
--     sus próximas compras (nota de 1,000 y compra de 800 → paga 0, le quedan
--     200; luego compra 700 → paga 500).
--
-- CÓMO: un libro de movimientos (`client_credit_movements`) y el saldo
-- cacheado en `clients.credit_balance`, mantenidos por DOS DISPARADORES:
--   · returns  → una devolución con 'credit_note' suma al saldo del cliente
--                lo que NO se fue a pagar la deuda de la venta original.
--                Sirve con las dos versiones vivas de `process_return`:
--                  - la vieja (88 de flutter_shop+ / 84 de shop-plus) no tiene
--                    `returns.cash_refund_amount`; si la venta original era a
--                    crédito rebaja TODO el total de la deuda del cliente, así
--                    que ahí no queda saldo a favor (si no, se daría dos
--                    veces); si no era a crédito, queda el total.
--                  - la nueva (97 de shop-plus) guarda en `cash_refund_amount`
--                    lo que sobró después de rebajar la deuda: eso queda.
--   · payments → un pago con método 'credit_note' (lo manda el POS al cobrar)
--                lo resta; si no alcanza, la venta entera se cancela. Si el
--                pago se borra (anular la venta) o se edita, el saldo vuelve.
--
-- NO AFECTA SHOP-PLUS NI LAS RPC COMPARTIDAS: no reemplaza `process_return`,
-- `checkout_sale_transactional` ni ninguna otra función existente. Solo
-- agrega un valor al enum `payment_method`, una tabla, una columna y dos
-- disparadores que no hacen nada salvo cuando el método es 'credit_note'
-- (shop-plus no ofrece nota de crédito en su devolución).
--
-- Idempotente: se puede volver a correr.
-- Si el SQL Editor se queja de "ALTER TYPE ... ADD VALUE cannot be executed
-- inside a transaction block", correr primero solo la línea del ALTER TYPE y
-- luego el resto.
-- ============================================================================

-- 1) Método de pago "Nota de crédito" (lo usa el POS para consumir el saldo).
alter type public.payment_method add value if not exists 'credit_note';

-- 2) Libro del saldo a favor: + al dar una nota de crédito, − al consumirla.
create table if not exists public.client_credit_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  client_id uuid not null,
  amount numeric(14,2) not null check (amount <> 0),
  kind text not null check (kind in ('return', 'sale', 'adjustment')),
  return_id uuid,
  payment_id uuid,
  sale_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  created_by uuid default auth.uid(),
  constraint client_credit_movements_client_fk
    foreign key (client_id, branch_id)
    references public.clients(id, branch_id)
    on delete restrict
);

comment on table public.client_credit_movements is
  'Saldo a favor de clientes (notas de crédito). Lo escriben los disparadores de returns y payments; la app solo lee.';

create unique index if not exists client_credit_movements_return_uidx
  on public.client_credit_movements (return_id) where return_id is not null;
create unique index if not exists client_credit_movements_payment_uidx
  on public.client_credit_movements (payment_id) where payment_id is not null;
create index if not exists client_credit_movements_client_idx
  on public.client_credit_movements (branch_id, client_id, created_at desc);

alter table public.client_credit_movements enable row level security;

drop policy if exists client_credit_movements_select on public.client_credit_movements;
create policy client_credit_movements_select
on public.client_credit_movements
for select
to authenticated
using (public.can_access_branch(branch_id));

-- Sin políticas de escritura: solo los disparadores (security definer) la
-- tocan, así nadie se fabrica saldo desde la app.
grant select on public.client_credit_movements to authenticated;

-- 3) Saldo cacheado en el cliente (como `balance_due` para la deuda).
alter table public.clients
  add column if not exists credit_balance numeric(14,2) not null default 0;

comment on column public.clients.credit_balance is
  'Saldo a favor por notas de crédito = suma de client_credit_movements. No editar a mano.';

create or replace function public.recompute_client_credit_balance(
  p_client_id uuid,
  p_branch_id uuid
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.clients c
     set credit_balance = coalesce((
       select sum(m.amount)
         from public.client_credit_movements m
        where m.client_id = p_client_id
          and m.branch_id = p_branch_id
     ), 0)
   where c.id = p_client_id
     and c.branch_id = p_branch_id;
$$;

revoke all on function public.recompute_client_credit_balance(uuid, uuid) from public;

-- 4) Devoluciones con nota de crédito → suman saldo a favor.
--    `process_return` inserta la devolución en 0 y después la actualiza con
--    el total (y, en la versión nueva, `cash_refund_amount` y el método final,
--    que pasa a 'credit_balance' si todo se fue a la deuda); por eso el
--    disparador recalcula en cada actualización. `cash_refund_amount` se lee
--    con `to_jsonb(new)` porque en la versión vieja la columna no existe.
create or replace function public.sync_return_credit_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(14,2);
  v_cash_refund numeric(14,2);
begin
  if tg_op in ('UPDATE', 'DELETE') then
    if old.client_id is not null
       and exists (
         select 1 from public.client_credit_movements where return_id = old.id
       ) then
      perform pg_advisory_xact_lock(hashtext('client_credit:' || old.client_id::text));
      delete from public.client_credit_movements where return_id = old.id;
      perform public.recompute_client_credit_balance(old.client_id, old.branch_id);
    end if;
  end if;

  if tg_op in ('INSERT', 'UPDATE') and new.refund_method = 'credit_note' then
    v_cash_refund := (to_jsonb(new) ->> 'cash_refund_amount')::numeric;
    if v_cash_refund is not null then
      -- Versión nueva: ya viene sin lo que rebajó la deuda.
      v_amount := round(v_cash_refund, 2);
    elsif new.client_id is not null
          and new.original_sale_id is not null
          and exists (
            select 1 from public.sales s
             where s.id = new.original_sale_id
               and s.status::text = 'credit'
          ) then
      -- Versión vieja con venta a crédito: todo el total rebaja la deuda.
      v_amount := 0;
    else
      v_amount := round(coalesce(new.total_amount, 0), 2);
    end if;
    if v_amount > 0 then
      if new.client_id is null then
        raise exception 'La nota de crédito necesita un cliente: selecciona el cliente antes de procesar la devolución.';
      end if;
      perform pg_advisory_xact_lock(hashtext('client_credit:' || new.client_id::text));
      insert into public.client_credit_movements (
        branch_id, client_id, amount, kind, return_id, sale_id, notes, created_by
      ) values (
        new.branch_id, new.client_id, v_amount, 'return', new.id,
        new.original_sale_id,
        'Nota de crédito ' || coalesce(new.return_number, ''),
        coalesce(new.cashier_id, auth.uid())
      );
      perform public.recompute_client_credit_balance(new.client_id, new.branch_id);
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_returns_credit_note on public.returns;
-- Sin `cash_refund_amount` en la lista: en la versión vieja no existe. La
-- nueva la actualiza en el mismo UPDATE que `refund_method`, que sí está.
create trigger trg_returns_credit_note
after insert or delete or update of refund_method, total_amount, client_id, return_number
on public.returns
for each row
execute function public.sync_return_credit_note();

-- 5) Pagos con nota de crédito → restan saldo a favor (y lo validan).
--    Lo inserta `checkout_sale_transactional` con el método 'credit_note';
--    si el saldo no alcanza, el error cancela la venta completa. Anular la
--    venta borra sus pagos → el saldo vuelve; editar los pagos también.
create or replace function public.sync_payment_credit_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance numeric(14,2);
begin
  if tg_op in ('UPDATE', 'DELETE') and old.payment_method::text = 'credit_note' then
    if old.client_id is not null then
      perform pg_advisory_xact_lock(hashtext('client_credit:' || old.client_id::text));
    end if;
    delete from public.client_credit_movements where payment_id = old.id;
    if old.client_id is not null then
      perform public.recompute_client_credit_balance(old.client_id, old.branch_id);
    end if;
  end if;

  if tg_op in ('INSERT', 'UPDATE') and new.payment_method::text = 'credit_note' then
    if new.client_id is null then
      raise exception 'El pago con nota de crédito necesita un cliente.';
    end if;
    perform pg_advisory_xact_lock(hashtext('client_credit:' || new.client_id::text));
    select coalesce(sum(m.amount), 0)
      into v_balance
      from public.client_credit_movements m
     where m.client_id = new.client_id
       and m.branch_id = new.branch_id;
    if v_balance + 0.005 < new.amount then
      raise exception 'Saldo a favor insuficiente: el cliente tiene %, se intentó usar %.',
        to_char(v_balance, 'FM999,999,990.00'),
        to_char(new.amount, 'FM999,999,990.00');
    end if;
    insert into public.client_credit_movements (
      branch_id, client_id, amount, kind, payment_id, sale_id, notes, created_by
    ) values (
      new.branch_id, new.client_id, -new.amount, 'sale', new.id, new.sale_id,
      'Consumo en venta ' || coalesce(new.reference, ''),
      auth.uid()
    );
    perform public.recompute_client_credit_balance(new.client_id, new.branch_id);
  end if;

  return null;
end;
$$;

drop trigger if exists trg_payments_credit_note on public.payments;
create trigger trg_payments_credit_note
after insert or delete or update of payment_method, amount, client_id
on public.payments
for each row
execute function public.sync_payment_credit_note();

-- 6) OPCIONAL — notas de crédito dadas ANTES de esta migración.
--    Hasta hoy "Nota de crédito" era solo una etiqueta: no le dejaba saldo al
--    cliente. Si esas devoluciones se le deben todavía al cliente, quitar los
--    guiones de este bloque y correrlo UNA vez (el índice único por
--    return_id evita duplicarlas). Revisar antes con:
--      select r.return_number, r.client_id, r.total_amount, r.return_date,
--             s.status as venta_original
--        from public.returns r
--        left join public.sales s on s.id = r.original_sale_id
--       where r.refund_method = 'credit_note' order by r.return_date;
--    (Las de una venta original A CRÉDITO ya rebajaron la deuda: no se
--    acreditan.)
--
-- insert into public.client_credit_movements
--   (branch_id, client_id, amount, kind, return_id, sale_id, notes, created_by)
-- select r.branch_id, r.client_id, round(r.total_amount, 2),
--        'return', r.id, r.original_sale_id,
--        'Nota de crédito ' || r.return_number || ' (anterior)', r.cashier_id
--   from public.returns r
--   left join public.sales s on s.id = r.original_sale_id
--  where r.refund_method = 'credit_note'
--    and r.client_id is not null
--    and r.total_amount > 0
--    and coalesce(s.status::text, '') <> 'credit'
-- on conflict do nothing;
--
-- select public.recompute_client_credit_balance(c.client_id, c.branch_id)
--   from (select distinct client_id, branch_id
--           from public.client_credit_movements) c;

notify pgrst, 'reload schema';
