# Printing data model guide for Shop+ RD

Status: recommended schema only

No database migration is applied by this work. This is guidance so future implementation stays coherent.

## Design principles

1. **Jobs are auditable**
   - every print attempt should have status, destination, timestamps, and failure reason
2. **Templates are versioned**
   - printing must stay reproducible over time
3. **Routing is explicit**
   - cashier receipt, warehouse A4, office invoice, etc.
4. **Devices and printers are separate**
   - one agent device can expose many printers
5. **A4 and 80mm share business data, not storage assumptions**

## Recommended tables

### 1) print_devices
Represents the local execution node / print agent host.

Suggested fields:

- `id uuid primary key`
- `branch_id uuid not null`
- `name text not null`
- `device_type text not null` — `agent | workstation | kiosk`
- `host text null`
- `auth_token_ref text null`
- `status text not null default 'offline'`
- `last_seen_at timestamptz null`
- `app_version text null`
- `is_active boolean not null default true`
- audit fields

Why:

- adapted from the `mangospos` device/agent concept
- allows one branch to have multiple execution points

### 2) printers
Physical or logical printer target.

Suggested fields:

- `id uuid primary key`
- `branch_id uuid not null`
- `device_id uuid null references print_devices(id)`
- `code text not null`
- `name text not null`
- `paper_size text not null` — `thermal_80mm | a4`
- `transport_type text not null` — `network | usb | system | pdf`
- `driver_type text null` — `epson_escpos | generic_escpos | cups | windows_spooler | pdf`
- `endpoint text null`
- `capabilities jsonb not null default '{}'::jsonb`
- `is_default boolean not null default false`
- `is_active boolean not null default true`
- audit fields

Capabilities examples:

```json
{
  "supports_qr": true,
  "supports_logo": true,
  "supports_cut": true,
  "columns": 48
}
```

### 3) print_routes
Maps document flows to a preferred printer/template.

Suggested fields:

- `id uuid primary key`
- `branch_id uuid not null`
- `document_type text not null`
- `paper_size text not null`
- `printer_id uuid null references printers(id)`
- `template_id uuid null references print_templates(id)`
- `copies integer not null default 1`
- `fallback_printer_id uuid null references printers(id)`
- `is_active boolean not null default true`
- audit fields

Why:

- lets the business say things like:
  - sale receipt → cashier thermal
  - invoice → office A4
  - cash close → admin A4 or thermal

### 4) print_templates
Versioned visual/config templates.

Suggested fields:

- `id uuid primary key`
- `branch_id uuid not null`
- `code text not null`
- `name text not null`
- `document_type text not null`
- `paper_size text not null`
- `version integer not null default 1`
- `is_default boolean not null default false`
- `settings jsonb not null default '{}'::jsonb`
- `is_active boolean not null default true`
- audit fields

Settings examples:

```json
{
  "show_logo": true,
  "show_cashier": true,
  "show_qr": false,
  "footer_message": "Gracias por su compra",
  "thermal_columns": 48,
  "a4_compact_mode": false
}
```

### 5) print_jobs
Core audit and queue table.

Suggested fields:

- `id uuid primary key`
- `branch_id uuid not null`
- `source_table text null` — e.g. `sales`, `cash_sessions`
- `source_id uuid null`
- `document_type text not null`
- `paper_size text not null`
- `status text not null` — `queued | processing | printed | failed | cancelled`
- `printer_id uuid null references printers(id)`
- `template_id uuid null references print_templates(id)`
- `requested_by uuid null references profiles(id)`
- `copies integer not null default 1`
- `payload jsonb not null`
- `render_snapshot jsonb null`
- `printed_at timestamptz null`
- `failed_at timestamptz null`
- `failure_reason text null`
- `retry_count integer not null default 0`
- `idempotency_key text null`
- audit fields

Important:

- `payload` stores the canonical document data or transport-safe version
- `render_snapshot` optionally stores the concrete rendered lines/table for reproducibility

### 6) print_job_events
Optional but strongly recommended.

Suggested fields:

- `id uuid primary key`
- `print_job_id uuid not null references print_jobs(id)`
- `event_type text not null` — `queued | dispatched | ack | retry | failed | printed`
- `message text null`
- `meta jsonb not null default '{}'::jsonb`
- `created_at timestamptz not null default now()`

This is useful when debugging flaky printers.

## Recommended enums / controlled vocab

Keep as text initially if you want faster iteration, but standardize these values.

### paper_size

- `thermal_80mm`
- `a4`

### document_type

- `sale_receipt`
- `fiscal_invoice`
- `cash_close`
- `quote`
- `purchase_order`
- `credit_note`

### transport_type

- `network`
- `usb`
- `system`
- `pdf`

### print_job_status

- `queued`
- `processing`
- `printed`
- `failed`
- `cancelled`

## Relation to existing Shop+ tables

### sales
Best first-class source for phase 1 printing.

Print jobs should be able to reference:

- `sales.id`
- `sales.sale_number`
- `sales.receipt_type`
- `sales.ncf`
- `sales.total_amount`
- `sales.tax_amount`
- `sales.paid_amount`
- `sales.balance_due`
- `sales.cashier_id`

### sale_items
Used to build printable line items.

### payments
Needed for payment breakdown on receipts/invoices.

### branches
Used for issuer identity on both A4 and thermal.

### profiles
Needed for cashier/requested_by metadata.

## Minimal implementation order

If this becomes DB work later, the safest order is:

1. `print_devices`
2. `printers`
3. `print_templates`
4. `print_routes`
5. `print_jobs`
6. optional `print_job_events`

## What not to do

- Do not store only raw ESC/POS bytes as the single source of truth.
- Do not hardcode one printer per branch forever.
- Do not merge device and printer into one table.
- Do not make A4 depend on thermal fields like `columns`.
- Do not skip job history if reprints matter fiscally or operationally.

## Recommended first branch-level defaults

For an MVP branch config:

- one thermal printer route for `sale_receipt`
- one A4 route for `fiscal_invoice`
- one template per paper size
- print job history enabled from day one

That is enough to start without overbuilding.
