#!/bin/bash
# Genera supabase/shop_plus_full.sql concatenando todas las migrations
# en el orden correcto para un Supabase self-hosted desde cero.
#
# Uso:   bash supabase/build_full_sql.sh
# Salida: supabase/shop_plus_full.sql

set -euo pipefail

cd "$(dirname "$0")"

OUT="shop_plus_full.sql"
BASE="sql"
NEXT="sql-next"

# Archivos en el orden EXACTO de aplicación.
# El seed (02_seed.sql) está comentado por defecto — descomentalo si quieres
# datos demo para probar.
FILES=(
  "$BASE/01_schema.sql"
  # "$BASE/02_seed.sql"   # ← descomentá esta línea para incluir datos demo
  "$BASE/03_reports_views.sql"
  "$BASE/04_branch_context.sql"

  "$NEXT/05_cash_foundation_core.sql"
  "$NEXT/06_cash_foundation_backfill.sql"
  "$NEXT/07_cash_foundation_views.sql"
  "$NEXT/20260410_pos_transactional_core.sql"
  "$NEXT/20260410_quotations_schema.sql"
  "$NEXT/20260421_structural_backoffice_foundation.sql"
  "$NEXT/20260422_fix_permissions_final.sql"
  "$NEXT/20260509_08_app_settings.sql"
  "$NEXT/20260509_09_reports_schema.sql"
  "$NEXT/20260509_10_dashboard_v2.sql"
  "$NEXT/20260509_11_returns.sql"
  "$NEXT/20260509_12_closeout_returns_fix.sql"
  "$NEXT/20260509_13_reports_round2_views.sql"
  "$NEXT/20260509_14_dgii_reports.sql"
  "$NEXT/20260509_15_realtime_report_views.sql"
  "$NEXT/20260509_16_operational_extensions.sql"
  "$NEXT/20260509_17_quotations_fix_and_autoexpire.sql"
  "$NEXT/20260513_18_ncf_autoassign.sql"
  "$NEXT/20260513_19_product_price_history.sql"
  "$NEXT/20260520_20_product_images_bucket.sql"
  "$NEXT/20260520_21_ncf_trigger_fix.sql"
  "$NEXT/20260520_22_credit_due_dates.sql"
  "$NEXT/20260520_23_dgii_reports_fix.sql"
  "$NEXT/20260520_24_enable_realtime_inventory.sql"
  "$NEXT/20260520_25_edit_sale_rpc.sql"
  "$NEXT/20260520_26_multi_cashier_sessions.sql"
  "$NEXT/20260520_27_multi_tenant_foundation.sql"
  "$NEXT/20260520_28_company_bootstrap.sql"
  "$NEXT/20260521_29_bootstrap_upsert_profile.sql"
  "$NEXT/20260521_30_void_sale_with_stock_return.sql"
  "$NEXT/20260521_31_update_sale_payment_method.sql"
  "$NEXT/20260521_32_extra_price_tiers.sql"
  "$NEXT/20260521_33_cash_registers.sql"
  "$NEXT/20260522_34_app_settings_legacy_fix.sql"
  "$NEXT/20260522_35_checkout_respects_global_stock_setting.sql"
  "$NEXT/20260522_36_user_isolation_per_company.sql"
  "$NEXT/20260522_37_branch_isolation_per_company.sql"
  "$NEXT/20260522_38_multitenant_isolation_audit.sql"
  "$NEXT/20260522_39_users_branches_profile_fk.sql"
  "$NEXT/20260522_40_record_dgii_report_company.sql"
  "$NEXT/20260522_41_enable_realtime_core_tables.sql"
  "$NEXT/20260522_42_multiple_open_cash_sessions.sql"
  "$NEXT/20260525_43_drop_old_checkout_signature.sql"

  "$NEXT/create_employee_rpc.sql"
)

# Cabecera del bundle
{
  echo "-- ============================================================"
  echo "-- Shop+ RD — Bundle SQL completo (self-hosted)"
  echo "-- Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "--"
  echo "-- Aplicar en orden, en una BD Postgres limpia (Supabase self-hosted)."
  echo "-- Cada archivo está delimitado por un banner para que sea fácil"
  echo "-- ubicar problemas si algo falla."
  echo "--"
  echo "-- Si querés datos demo, edita build_full_sql.sh y descomenta"
  echo "-- la línea de 02_seed.sql."
  echo "-- ============================================================"
  echo
} > "$OUT"

for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: archivo no encontrado: $f" >&2
    exit 1
  fi
  {
    echo
    echo "-- ============================================================"
    echo "-- BEGIN: $f"
    echo "-- ============================================================"
    cat "$f"
    echo
    echo "-- ============================================================"
    echo "-- END:   $f"
    echo "-- ============================================================"
    echo
  } >> "$OUT"
done

lines=$(wc -l < "$OUT")
size=$(du -h "$OUT" | cut -f1)
echo "Generado $OUT  ($lines líneas, $size)"
