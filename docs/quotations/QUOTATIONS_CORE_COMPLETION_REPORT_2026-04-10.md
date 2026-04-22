# Quotations core completion report — 2026-04-10

## Scope closed
Aligned the quotations module with the minimum required scope in `docs/quotations/REQUISITO_MINIMO_COTIZACIONES.md`.

## What was completed

### 1. Create
- Kept quote creation working with:
  - client
  - lines/products
  - quantities
  - prices
  - taxes
  - notes
  - expiry date
  - explicit initial status

### 2. View
- Added a real quote detail route: `/cotizaciones/:quoteId`
- Quotes can now be opened from the list/table/mobile card.
- Detail screen shows:
  - code
  - status
  - creation date
  - expiry date
  - client
  - notes
  - lines
  - totals
  - converted sale linkage state

### 3. Edit
- Reworked `QuotationCreatePage` into a real create/edit screen.
- Existing quotes can now be updated from the same screen.
- Editable fields now include the required minimum:
  - client
  - products/lines
  - quantities
  - prices (through product snapshot pricing currently used by the module)
  - observations/notes
  - expiry date
- Added status management from UI (`draft`, `sent`, `under_review`, `approved`, `rejected`, `expired`).

### 4. Delete
- Deletion remains restricted by state rules.
- Converted quotations are blocked from deletion.
- Detail screen now exposes delete when the state allows it.

### 5. Expiry date management
- Expiry date is shown clearly in list and detail.
- Expired quotes are visually marked as expired.
- Expired quotes can be reopened by editing the expiry date to a future date and saving.

### 6. Convert quotation to sale
- Kept the conversion path on backend RPC (`convert_quotation_to_sale`) instead of fragile client-side multi-insert logic.
- Conversion is now reachable from both:
  - quotations list
  - quote detail screen
- Conversion still enforces structural rules:
  - approved only
  - not expired
  - not previously converted
  - must contain lines
  - must have stock available

## Structural changes made

### Flutter
- `lib/features/quotations/data/quotations_models.dart`
  - added detail model and edit/view state helpers
- `lib/features/quotations/data/quotations_repository.dart`
  - added quote detail fetch
  - added quote update flow via RPC
- `lib/features/quotations/presentation/quotation_create_page.dart`
  - now supports create + view + edit + delete + convert
- `lib/features/quotations/presentation/quotations_page.dart`
  - quotes can now be opened directly
- `lib/features/quotations/presentation/quotations_providers.dart`
  - added detail provider
- `lib/app/router.dart`
  - added `/cotizaciones/:quoteId`

### SQL / additive backend
- `supabase/sql-next/20260410_quotations_schema.sql`
  - preserved transactional `convert_quotation_to_sale(...)`
  - added transactional `update_quotation_document(...)` so header + lines + expiry/status update together

## Validation run
- `flutter analyze lib/features/quotations lib/app/router.dart test/features/quotations/quotations_models_test.dart` ✅
- `flutter test test/features/quotations/quotations_models_test.dart` ⚠️ failed in local environment with:
  - `Resource deadlock avoided`
  - failure occurs while launching `flutter_tester`, not from quotation assertions themselves

## Important notes
- No live database was modified directly.
- DB work remains additive in `supabase/sql-next/`.
- This closes the required minimum scope much more credibly than the previous placeholder state.
- Advanced commercial workflow still remains out of scope here:
  - approvals policy
  - advanced versioning
  - PDF/print polish
  - quotation reports
