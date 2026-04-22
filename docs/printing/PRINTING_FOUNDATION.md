# Printing foundation for Shop+ RD

Status: foundation/spec + starter code only

This package establishes the first serious printing direction for `flutter_shop+` without forcing DB changes or risky UI wiring yet.

## Goals

1. Support **80mm thermal** receipts for day-to-day POS flow.
2. Support **A4** invoice-style documents for formal printing/export.
3. Keep document composition **independent** from printer transport.
4. Prepare for a **local print agent** model, inspired by `mangospos`, but adapted to Shop+ RD's simpler current architecture.
5. Make future Supabase tables and print history coherent before implementation starts.

## What was borrowed from MangoPOS

From `mangospos`, the useful ideas are:

- Flutter should not own hardware-specific printer logic end to end.
- A **print agent** is the safest long-term bridge for USB/network printers.
- `print_jobs` should be tracked as queued/dispatched/printed/failed, not treated like a blind fire-and-forget action.
- The app should generate a **structured print document**, then render/dispatch it according to destination.

## What is different for Shop+ RD

Shop+ is currently:

- Supabase-first
- feature-first Flutter app
- retail/POS focused
- still building its complete fiscal/document workflow

So the recommended adaptation is:

- keep document building in Flutter
- keep printer transport abstract
- avoid premature ESC/POS package coupling in the app
- let backend/local agent own device-specific execution later

## Recommended architecture

```text
Sale / Purchase / Cash flow
        ↓
Structured PrintDocumentData
        ↓
PrintingTemplateService
        ↓
A) ThermalTicketTemplate (80mm)
B) A4DocumentTemplate
        ↓
PrintDispatchPayloadBuilder
        ↓
Transport layer
  - backend queue / Supabase-backed job creation
  - local print agent
  - browser preview / PDF export
```

## Format strategy

### 80mm thermal

Use for:

- receipt after sale
- simplified fiscal receipt
- cash close slip
- reprint copy

Characteristics:

- narrow width
- fewer columns
- concise customer and tax info
- optimized for ESC/POS or agent JSON instructions

### A4

Use for:

- invoice
- credit sale printable invoice
- quote/proforma later
- purchase document later

Characteristics:

- full business identity
- richer customer details
- more legible item table
- signature/notes/terms space
- PDF/browser rendering friendly

## Template strategy

Do **not** hardcode document layout directly inside sales pages.

Instead:

1. Build a canonical `PrintDocumentData`
2. Render it to one of these template models:
   - `ThermalTicketTemplate`
   - `A4DocumentTemplate`
3. Convert the rendered template into transport payloads later

That separation prevents these common problems:

- sale page becoming full of print formatting logic
- ESC/POS constraints leaking into business/domain code
- A4 and 80mm diverging semantically
- reprints becoming inconsistent with originals

## Recommended document types for phase 1

Start with:

- `saleReceipt`
- `fiscalInvoice`
- `cashClose`

Keep placeholders ready for:

- `quote`
- `purchaseOrder`
- `creditNote`

## Transport strategy

### Near term

Good enough for first implementation:

- create document in Flutter
- build dispatch payload in app
- send to a future backend endpoint / Supabase edge function / local agent

### Long term

Preferred production path:

- Flutter app creates `print_jobs`
- backend or edge layer validates route/template/printer assignment
- local print agent executes network/USB jobs
- A4 can be generated as HTML/PDF independently of thermal flow

## Why not one renderer for everything?

Because thermal and A4 have different realities:

- thermal is command- and width-driven
- A4 is document/page-driven
- thermal is operational
- A4 is archival/fiscal/business-facing

The source data should be shared. The rendering model should not.

## Starter code added

The Dart scaffolding added under `lib/features/printing/data/` provides:

- core enums and models for printers, jobs, templates, and canonical print documents
- `PrintingTemplateService` to transform a canonical document into:
  - `ThermalTicketTemplate`
  - `A4DocumentTemplate`
- `PrintDispatchPayloadBuilder` to produce backend/agent friendly payload maps
- `PrintingRepository` as an abstract contract for future Supabase/backend integration

## Rollout plan

### Phase 1 — foundation

- define models
- define document/template strategy
- define job status lifecycle
- define printer routing concepts

### Phase 2 — backend persistence

- add DB tables for printers/templates/jobs
- add repository implementation
- store print history and failures

### Phase 3 — execution

- add local print agent handshake
- send thermal jobs to agent
- support A4 preview/export/print

### Phase 4 — production hardening

- retries
- idempotency keys
- reprint audit trail
- template versioning by branch
- printer health and fallback routing

## Practical rule for future contributors

When adding a new printable document:

1. extend `PrintDocumentType`
2. enrich `PrintDocumentData` only if the field is truly cross-format
3. update `PrintingTemplateService`
4. update dispatch payload builder
5. only then wire UI/backend

That order keeps the printing stack maintainable.
