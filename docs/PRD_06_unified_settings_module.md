# PRD 06 — Módulo de Configuración Unificado (Unified Settings Module)

| Campo | Valor |
|---|---|
| **Versión** | 1.0 (Draft) |
| **Autor** | Cristian (DRI) |
| **Fecha** | 2026-05-09 |
| **Estado** | DRAFT — pendiente de revisión |
| **Programa** | Fiscal Stabilization Program (post-PRD 5) |
| **Predecesor** | PRD 05 — Unified Printing Module |
| **Lenguaje primario de UI** | Español (es-DO) |

---

## 1. Resumen ejecutivo

MangoPOS necesita una pantalla única de **Configuración Global del Negocio** que centralice todos los ajustes operativos (información de la compañía, inventario, empleados, impuestos, ventas, recibos, cuentas abiertas y aplicación) en una sola ubicación, persistida en Supabase y respetada por todos los módulos en runtime.

Este PRD replica de forma casi 1-a-1 la matriz de configuración de Wilmax POS (referencia visual de 9 mayo 2026), adaptada al contexto de restaurantes en República Dominicana y al stack Flutter + Supabase de MangoPOS. **La meta es paridad funcional**: ~120 opciones, todas funcionales, todas persistidas, todas leídas en runtime por los módulos correspondientes.

Este es un PRD de **base operativa**: no inventa funcionalidad nueva, formaliza y centraliza lo que hoy está disperso entre constantes hardcodeadas, valores en `app_state`, columnas sueltas en `businesses`, y suposiciones implícitas en código de UI.

---

## 2. Contexto y motivación

### 2.1 Estado actual

Hoy en MangoPOS, ajustes operativos están dispersos:

- **Hardcoded en Dart**: prefijos de id (`FA`, `NC`, `ND`), tamaño de texto del recibo, símbolo de moneda, decimales, separador de miles.
- **Columnas sueltas en `businesses`**: `name`, `rnc`, `logo_url`, algunos flags.
- **Lógica implícita**: "imprimir recibo después de venta = siempre true", "permitir ventas a crédito = siempre true".
- **Sin equivalente**: política de devoluciones, comisiones de empleado, denominaciones de moneda para arqueo, columna a mostrar en interfaz de venta.

Resultado: cualquier cambio operativo (ej: añadir un canal de pago, cambiar el prefijo de NC, ocultar el saldo de crédito en el recibo) requiere despliegue de código.

### 2.2 Motivación

1. **Paridad con competidores**: Wilmax es la referencia de mercado en RD; los clientes esperan el mismo nivel de configurabilidad.
2. **Reducir despliegues**: separar configuración de código.
3. **Multi-business limpio**: cada negocio en `businesses` debe tener su propio set de configuraciones (ya tuviste un bug por `LIMIT 1` en `fn_require_open_cash_session` precisamente por no respetar multi-tenancy de forma estricta).
4. **Base para futuras features**: fidelización de clientes, comisiones, modo prueba, 2FA — todas requieren un módulo de configuración robusto antes.

### 2.3 Por qué ahora

PRDs 1-4 estabilizaron el motor fiscal y Venta Rápida. PRD 5 (en curso) consolida impresión. Configuración unificada es el **siguiente cuello de botella natural**: sin ella, cualquier ajuste de comportamiento sigue siendo un commit + deploy.

---

## 3. Objetivos

### 3.1 Objetivos primarios (must-have)

- **O1**: Pantalla única `/configuracion` en Flutter con las 7 secciones de Wilmax (adaptadas), accesible solo para roles `owner` / `admin`.
- **O2**: Tabla `business_settings` en Supabase, una fila por `business_id`, con todas las opciones tipadas.
- **O3**: Repositorio `SettingsRepository` (Riverpod) con cache local y sync con Supabase.
- **O4**: Migración progresiva (strangler fig) de los call-sites existentes que hoy leen de constantes hardcodeadas, a leer de `SettingsRepository`.
- **O5**: Todas las opciones funcionales — no se aceptan placeholders ni "se guarda pero no se respeta".

### 3.2 Objetivos secundarios (should-have)

- **O6**: Búsqueda dentro de la pantalla de configuración (campo `Buscar` filtra opciones por etiqueta).
- **O7**: Botón "Restaurar valores por defecto" por sección.
- **O8**: Audit log: cada cambio de configuración registra `user_id`, `field`, `old_value`, `new_value`, `changed_at` en tabla `business_settings_audit`.

### 3.3 No-objetivos (out of scope)

- **NO**: redondeo a 5 más cercano (solo Canadá) — eliminado por irrelevante.
- **NO**: sistema de fidelización de clientes funcional — solo el toggle de activación. El módulo de fidelización en sí es PRD futuro.
- **NO**: 2FA con Google Authenticator funcional — solo el toggle. Implementación es PRD futuro.
- **NO**: Modo prueba (ventas no guardan) funcional — solo el toggle, dejado deshabilitado por defecto, el comportamiento es PRD futuro (riesgoso por incidentes fiscales).
- **NO**: rediseño del módulo de impuestos. PRD 2 ya estableció el unified tax schema; este PRD **lee y escribe sobre ese esquema**, no lo reemplaza.
- **NO**: cambio del sistema de NCF/eCF. El campo "Comprobante por defecto" es un dropdown sobre la tabla `comprobantes_fiscales` existente.

---

## 4. Alcance funcional

7 secciones, mapeadas 1-a-1 con Wilmax salvo las adaptaciones explicitadas.

### 4.1 Sección "Información de la Compañía"

| Campo | Tipo | Default | Notas de implementación |
|---|---|---|---|
| Logotipo de la empresa | `image_upload` | `null` | Sube a Supabase Storage bucket `business-assets/{business_id}/logo`. Aparece en recibos y panel. |
| ¿Eliminar logo? | `bool` | `false` | Botón de acción inmediata, no se persiste como toggle. |
| Nombre de la compañía | `text` (req) | (existente) | Migra de `businesses.name`. |
| RNC | `text` | `null` | Migra de `businesses.rnc`. Validar formato RD (9 u 11 dígitos). |
| Sitio web | `text` | `null` | Validar URL. |
| Comprobante fiscal por defecto | `dropdown` (FK `comprobantes_fiscales.id`) | `null` | Dropdown lee de tabla existente. |

### 4.2 Sección "Inventario"

| Campo | Tipo | Default |
|---|---|---|
| Marcar "es servicio" por defecto en artículos nuevos | `bool` | `false` |
| Id para mostrar en código de barras | `enum`(`item_id`, `barcode`, `sku`) | `item_id` |
| No permitir venta de artículos con precio inferior al costo | `bool` | `false` |
| No permitir venta de artículos sin stock | `bool` | `false` |
| Resaltar artículos en stock mínimo | `bool` | `true` |
| Desactivar calculadora de margen de precio | `bool` | `true` |

**Wiring obligatorio**: cada flag debe respetarse en el módulo correspondiente. Ej: "No permitir venta sin stock" se valida en `SaleController.addItem()` y bloquea con un `Toast` si stock <= 0.

### 4.3 Sección "Ajustes del Empleado"

| Campo | Tipo | Default |
|---|---|---|
| Seleccionar persona de las ventas durante la venta | `bool` | `false` |
| El vendedor es requerido en la venta | `bool` | `false` |
| Persona de ventas por defecto | `enum`(`logged_in_user`, `last_used`, `manual`) | `logged_in_user` |
| Tasa de comisión (%) | `numeric(5,2)` | `0.00` |
| Método de cálculo de comisión | `enum`(`sale_price`, `profit_margin`, `total_sales`) | `sale_price` |
| Exigir login antes de cada venta | `bool` | `false` |
| Mantener mismo lugar después de cambio de empleado | `bool` | `true` |
| Activar registro de tiempo (entrada/salida) | `bool` | `false` |

**Adaptación restaurante**: en MangoPOS "vendedor" = mesero. La opción "El vendedor es requerido en la venta" se traduce a "asignar mesero obligatorio para abrir mesa".

### 4.4 Sección "Impuestos y Moneda"

⚠️ **Crítico**: esta sección NO crea un nuevo sistema de impuestos. Lee y escribe sobre el **unified tax schema de PRD 2**. Los campos "Tasa de impuestos 1/2/N" son un editor visual de filas en `tax_rates`.

| Campo | Tipo | Default |
|---|---|---|
| Marcar "precio incluye impuestos" por defecto en artículos nuevos | `bool` | `false` |
| Cargar impuesto sobre recepciones | `bool` | `false` |
| Tasas de impuestos (lista dinámica) | `jsonb` proxy a `tax_rates` | ITBIS 18% (RD por defecto) |
| Acumulativo (por tasa) | `bool` | `false` |
| Incluir impuestos en códigos de barras | `bool` | `true` |
| Símbolo de moneda | `text` | `RD$` |
| Número de decimales | `int` | `2` |
| Separador de miles | `char(1)` | `,` |
| Punto decimal | `char(1)` | `.` |
| Denominaciones de moneda | `jsonb` (lista de `{label, value}`) | `[2000, 1000, 500, 200, 100, 50, 25, 10, 5, 1]` |

**Denominaciones**: usadas por el módulo de arqueo de caja para el desglose de billetes/monedas. Lista editable con drag-and-drop, agregar y eliminar.

### 4.5 Sección "Ventas y Recibo"

Esta es la sección más densa (~50 campos). Los agrupo lógicamente.

#### 4.5.1 Recibo (presentación)

| Campo | Tipo | Default |
|---|---|---|
| Ignorar título recibo | `text` | `null` |
| Sello | `image_upload` | `null` |
| ¿Eliminar sello? | acción | — |
| Firma | `image_upload` | `null` |
| ¿Eliminar firma? | acción | — |
| ¿Ocultar firma? | `bool` | `true` |
| Tamaño del texto del recibo | `enum`(`small`, `normal`, `large`) | `small` |
| Mostrar id de elemento en el recibo | `bool` | `false` |
| Ocultar código de barras en recibos | `bool` | `false` |
| Ocultar saldo de crédito del cliente en recibo | `bool` | `true` |

#### 4.5.2 Recibo (comportamiento)

| Campo | Tipo | Default |
|---|---|---|
| Imprimir recibo después de venta | `bool` | `true` |
| Imprimir recibo después de recepción/compra | `bool` | `true` |
| Imprimir automáticamente recibo duplicado para tarjeta de crédito | `bool` | `true` |
| Mostrar recibo después de suspender venta | `bool` | `true` |
| Envío automático correo electrónico al cliente | `bool` | `true` |
| Mostrar automáticamente observaciones sobre recibo | `bool` | `false` |
| Redirigir a venta/recepción tras imprimir el recibo | `bool` | `false` |

#### 4.5.3 Interfaz de venta

| Campo | Tipo | Default |
|---|---|---|
| Columna a mostrar en interfaz de ventas | `enum`(`barcode`, `sku`, `category`, `none`) | `barcode` |
| Posicionar cursor en campo del artículo | `bool` | `false` |
| Ventas recientes por cliente a mostrar | `int` | `10` |
| Eliminar info de contacto del cliente desde la recepción | `bool` | `false` |
| Ocultar ventas recientes para cliente | `bool` | `false` |
| Desactivar confirmación de venta completada | `bool` | `true` |
| Desactivar la venta rápida | `bool` | `false` |
| Cambiar fecha de venta en nueva venta | `bool` | `false` |
| No agrupar elementos iguales | `bool` | `false` |
| Editar precio del artículo si es 0 al añadir a la venta | `bool` | `true` |

⚠️ **Integración con PRD 4**: "Desactivar la venta rápida" debe hacer que el botón Venta Rápida no aparezca en el panel principal — se valida en `MainScaffold.build()`.

#### 4.5.4 Costo y precios

| Campo | Tipo | Default |
|---|---|---|
| Calcular costo promedio de la compra | `bool` | `true` |
| Método de promedio | `enum`(`current_received_price`, `weighted_avg`, `last_purchase`) | `current_received_price` |
| Siempre usar costo global medio para venta | `bool` | `false` |
| Tipos de precios redondean a 2 decimales | `bool` | `true` |
| Tipos de precios (lista) | `jsonb` lista | `[mayorista, pago efectivo]` |

#### 4.5.5 Tarjetas de regalo y recepciones suspendidas

| Campo | Tipo | Default |
|---|---|---|
| Ocultar recepciones suspendidas en informes | `bool` | `false` |
| Desactivar detección de tarjetas de regalo | `bool` | `false` |
| Calcular tarjeta regalo beneficio cuando | `enum`(`do_nothing`, `on_sale`, `on_redemption`) | `do_nothing` |

#### 4.5.6 Cuadrícula y layout

| Campo | Tipo | Default |
|---|---|---|
| Mostrar cuadrícula automáticamente durante venta | `bool` | `false` |
| Ocultar artículos sin stock al mostrar cuadrícula | `bool` | `false` |
| Predeterminado para cuadrícula | `enum`(`categories`, `tags`, `favorites`) | `categories` |

#### 4.5.7 Cliente y crédito

| Campo | Tipo | Default |
|---|---|---|
| Requerir cliente para venta | `bool` | `false` |
| Requerir cliente en venta suspendida | `bool` | `false` |
| Permitir ventas a crédito | `bool` | `true` |
| Permitir compras a crédito | `bool` | `true` |
| Cuenta de tienda desactiva al exceder límite de crédito | `bool` | `false` |
| Tienda estado de cuenta mensaje | `text` | `null` |
| Preguntar por CCV al pasar tarjeta de crédito | `bool` | `false` |
| No vender a cliente cuando | `enum`(`exceeds_balance_limit`, `has_overdue_invoices`, `never`) | `exceeds_balance_limit` |
| Permitir comprobante en productos exentos | `bool` | `true` |
| Desactivar notificaciones de venta | `bool` | `false` |
| Grupo de todos los impuestos sobre la recepción | `bool` | `false` |
| Control de impresión de facturas | `bool` | `false` |

#### 4.5.8 Prefijos de documentos

Todos `text(10)`, validar uppercase y solo `[A-Z0-9]`.

| Campo | Default |
|---|---|
| Prefijo id venta | `FA` |
| Prefijo id nota de crédito | `NC` |
| Prefijo id nota de débito | `ND` |
| Prefijo id conduce | `CON` |
| Prefijo id cotización | `CO` |
| Prefijo id abono a línea de crédito | `PAC` |
| Prefijo id pago a plazo | `PA` |
| Prefijo id compra | `COM` |
| Prefijo id orden de compra | `OC` |
| Prefijo id recibo | `REC` |

#### 4.5.9 Métodos de pago

| Campo | Tipo | Default |
|---|---|---|
| Métodos de pago habilitados | `multi-select` | `[Efectivo, Tarjeta de Débito, Tarjeta de Crédito, Transferencia Bancaria]` |
| Método de pago por defecto | `enum` (de los habilitados) | `Efectivo` |
| Canales de pago (lista) | `jsonb` | `[]` |
| Mostrar canales de pago en la venta | `bool` | `false` |

#### 4.5.10 Formato y políticas

| Campo | Tipo | Default |
|---|---|---|
| Formato de factura por defecto | `enum`(`pos_invoice`, `letter_invoice`) | `pos_invoice` |
| Formato de factura (B2X) | `enum`(`b2c`, `b2b`, `b2g`) | `b2c` |
| Política de devoluciones | `text` (req) | `0` |
| Anuncios / especiales | `text` | `null` |

### 4.6 Sección "Cuentas abiertas / Ventas suspendidas"

⚠️ **Adaptación restaurante**: en Wilmax esto es "apartados" (layaway). En MangoPOS se traduce a **cuentas abiertas / mesas en curso**.

| Campo | Tipo | Default |
|---|---|---|
| Ocultar cuentas por pagar en informes de tienda | `bool` | `false` |
| Ocultar pagos de cuenta de tienda en totales del informe | `bool` | `false` |
| Cambiar fecha de venta al suspender venta | `bool` | `true` |
| Cambiar fecha de venta al completar venta suspendida | `bool` | `true` |
| Mostrar recibo después de suspensión de venta | `bool` | `true` |

### 4.7 Sección "Configuración de la aplicación"

| Campo | Tipo | Default |
|---|---|---|
| Activar verificación en dos pasos | `bool` | `false` |
| Modo de prueba (ventas no guardan) | `bool` | `false` |
| Activar cambio rápido de usuario | `bool` | `false` |
| Habilitar conduces | `bool` | `false` |
| Idioma | `enum`(`es`, `en`) | `es` |
| Formato de fecha | `enum` (ISO, DMY, MDY) | `dd-MM-yyyy` |
| Formato de hora | `enum`(`12h`, `24h`) | `12h` |
| Ocultar precio en códigos de barras | `bool` | `false` |
| Activar sistema de fidelización | `bool` | `false` |
| Activar sonidos para mensajes de estado | `bool` | `true` |
| Filas por página en búsqueda | `int (5-100)` | `20` |
| Elementos por página en cuadrícula | `int (5-100)` | `15` |
| Orden de vista en búsqueda | `enum`(`newest_first`, `oldest_first`, `alphabetical`) | `newest_first` |
| Ocultar estadísticas del panel | `bool` | `false` |
| Mostrar selector de idioma | `bool` | `false` |
| Mostrar reloj en cabecera | `bool` | `false` |
| Acelerar consultas de búsqueda | `bool` | `true` |
| Formato de hoja de cálculo | `enum`(`xlsx`, `csv`) | `xlsx` |
| Comportamiento al cerrar sesión | `enum`(`close_browser`, `redirect_login`, `lock_screen`) | `redirect_login` |

**Eliminados de Wilmax**:
- "Redondea a nearest5 en receipt .0 (solo para Canadá)" — irrelevante.
- "Legado informe detallado excel exportación" — sin migración legacy en MangoPOS.
- "Legado método de búsqueda" — irrelevante.

---

## 5. Modelo de datos

### 5.1 Tabla principal: `business_settings`

```sql
CREATE TABLE business_settings (
  business_id UUID PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,

  -- Sección 1: Información de la Compañía
  logo_url TEXT,
  website TEXT,
  default_fiscal_receipt_id UUID REFERENCES comprobantes_fiscales(id),

  -- Sección 2: Inventario
  inv_default_is_service BOOLEAN NOT NULL DEFAULT FALSE,
  inv_barcode_id_source TEXT NOT NULL DEFAULT 'item_id'
    CHECK (inv_barcode_id_source IN ('item_id', 'barcode', 'sku')),
  inv_disallow_below_cost BOOLEAN NOT NULL DEFAULT FALSE,
  inv_disallow_no_stock BOOLEAN NOT NULL DEFAULT FALSE,
  inv_highlight_min_stock BOOLEAN NOT NULL DEFAULT TRUE,
  inv_disable_margin_calculator BOOLEAN NOT NULL DEFAULT TRUE,

  -- Sección 3: Empleado
  emp_pick_seller_during_sale BOOLEAN NOT NULL DEFAULT FALSE,
  emp_seller_required BOOLEAN NOT NULL DEFAULT FALSE,
  emp_default_seller TEXT NOT NULL DEFAULT 'logged_in_user'
    CHECK (emp_default_seller IN ('logged_in_user', 'last_used', 'manual')),
  emp_commission_rate NUMERIC(5,2) NOT NULL DEFAULT 0.00,
  emp_commission_method TEXT NOT NULL DEFAULT 'sale_price'
    CHECK (emp_commission_method IN ('sale_price', 'profit_margin', 'total_sales')),
  emp_require_login_each_sale BOOLEAN NOT NULL DEFAULT FALSE,
  emp_keep_position_after_switch BOOLEAN NOT NULL DEFAULT TRUE,
  emp_time_clock_enabled BOOLEAN NOT NULL DEFAULT FALSE,

  -- Sección 4: Impuestos y Moneda
  tax_default_price_includes_tax BOOLEAN NOT NULL DEFAULT FALSE,
  tax_charge_on_receivings BOOLEAN NOT NULL DEFAULT FALSE,
  tax_include_in_barcodes BOOLEAN NOT NULL DEFAULT TRUE,
  currency_symbol TEXT NOT NULL DEFAULT 'RD$',
  currency_decimals INT NOT NULL DEFAULT 2 CHECK (currency_decimals BETWEEN 0 AND 4),
  currency_thousands_sep CHAR(1) NOT NULL DEFAULT ',',
  currency_decimal_point CHAR(1) NOT NULL DEFAULT '.',
  currency_denominations JSONB NOT NULL DEFAULT
    '[{"label":"RD$2000","value":2000},{"label":"RD$1000","value":1000},{"label":"RD$500","value":500},{"label":"RD$200","value":200},{"label":"RD$100","value":100},{"label":"RD$50","value":50},{"label":"RD$25","value":25},{"label":"RD$10","value":10},{"label":"RD$5","value":5},{"label":"RD$1","value":1}]'::jsonb,

  -- Sección 5: Ventas y Recibo
  receipt_ignore_title TEXT,
  receipt_stamp_url TEXT,
  receipt_signature_url TEXT,
  receipt_hide_signature BOOLEAN NOT NULL DEFAULT TRUE,
  receipt_text_size TEXT NOT NULL DEFAULT 'small'
    CHECK (receipt_text_size IN ('small', 'normal', 'large')),
  receipt_show_item_id BOOLEAN NOT NULL DEFAULT FALSE,
  receipt_hide_barcode BOOLEAN NOT NULL DEFAULT FALSE,
  receipt_hide_credit_balance BOOLEAN NOT NULL DEFAULT TRUE,
  receipt_print_after_sale BOOLEAN NOT NULL DEFAULT TRUE,
  receipt_print_after_purchase BOOLEAN NOT NULL DEFAULT TRUE,
  receipt_auto_duplicate_on_credit_card BOOLEAN NOT NULL DEFAULT TRUE,
  receipt_show_after_suspend BOOLEAN NOT NULL DEFAULT TRUE,
  receipt_email_customer_auto BOOLEAN NOT NULL DEFAULT TRUE,
  receipt_show_observations_auto BOOLEAN NOT NULL DEFAULT FALSE,
  receipt_redirect_after_print BOOLEAN NOT NULL DEFAULT FALSE,

  sale_ui_column TEXT NOT NULL DEFAULT 'barcode'
    CHECK (sale_ui_column IN ('barcode','sku','category','none')),
  sale_focus_item_field BOOLEAN NOT NULL DEFAULT FALSE,
  sale_recent_per_customer INT NOT NULL DEFAULT 10,
  sale_strip_customer_contact BOOLEAN NOT NULL DEFAULT FALSE,
  sale_hide_recent_for_customer BOOLEAN NOT NULL DEFAULT FALSE,
  sale_disable_complete_confirmation BOOLEAN NOT NULL DEFAULT TRUE,
  sale_disable_quick_sale BOOLEAN NOT NULL DEFAULT FALSE,
  sale_change_date_on_new BOOLEAN NOT NULL DEFAULT FALSE,
  sale_no_group_identical_items BOOLEAN NOT NULL DEFAULT FALSE,
  sale_edit_zero_price_on_add BOOLEAN NOT NULL DEFAULT TRUE,
  sale_calc_avg_purchase_cost BOOLEAN NOT NULL DEFAULT TRUE,
  sale_avg_method TEXT NOT NULL DEFAULT 'current_received_price'
    CHECK (sale_avg_method IN ('current_received_price','weighted_avg','last_purchase')),
  sale_always_use_global_avg_cost BOOLEAN NOT NULL DEFAULT FALSE,
  sale_price_types_round_2_decimals BOOLEAN NOT NULL DEFAULT TRUE,
  sale_price_types JSONB NOT NULL DEFAULT '["mayorista","pago efectivo"]'::jsonb,

  giftcard_hide_suspended_receivings BOOLEAN NOT NULL DEFAULT FALSE,
  giftcard_disable_detection BOOLEAN NOT NULL DEFAULT FALSE,
  giftcard_benefit_when TEXT NOT NULL DEFAULT 'do_nothing'
    CHECK (giftcard_benefit_when IN ('do_nothing','on_sale','on_redemption')),

  grid_show_during_sale BOOLEAN NOT NULL DEFAULT FALSE,
  grid_hide_no_stock BOOLEAN NOT NULL DEFAULT FALSE,
  grid_default TEXT NOT NULL DEFAULT 'categories'
    CHECK (grid_default IN ('categories','tags','favorites')),

  customer_required_for_sale BOOLEAN NOT NULL DEFAULT FALSE,
  customer_required_for_suspended BOOLEAN NOT NULL DEFAULT FALSE,
  credit_allow_sales BOOLEAN NOT NULL DEFAULT TRUE,
  credit_allow_purchases BOOLEAN NOT NULL DEFAULT TRUE,
  credit_disable_account_on_overlimit BOOLEAN NOT NULL DEFAULT FALSE,
  credit_account_message TEXT,
  credit_ask_ccv_on_card BOOLEAN NOT NULL DEFAULT FALSE,
  credit_block_when TEXT NOT NULL DEFAULT 'exceeds_balance_limit'
    CHECK (credit_block_when IN ('exceeds_balance_limit','has_overdue_invoices','never')),
  fiscal_allow_for_exempt_products BOOLEAN NOT NULL DEFAULT TRUE,
  sale_disable_notifications BOOLEAN NOT NULL DEFAULT FALSE,
  sale_group_all_taxes_on_receipt BOOLEAN NOT NULL DEFAULT FALSE,
  sale_invoice_print_control BOOLEAN NOT NULL DEFAULT FALSE,

  -- Prefijos
  prefix_sale       TEXT NOT NULL DEFAULT 'FA',
  prefix_credit_note TEXT NOT NULL DEFAULT 'NC',
  prefix_debit_note  TEXT NOT NULL DEFAULT 'ND',
  prefix_delivery    TEXT NOT NULL DEFAULT 'CON',
  prefix_quote       TEXT NOT NULL DEFAULT 'CO',
  prefix_credit_payment TEXT NOT NULL DEFAULT 'PAC',
  prefix_installment_payment TEXT NOT NULL DEFAULT 'PA',
  prefix_purchase    TEXT NOT NULL DEFAULT 'COM',
  prefix_purchase_order TEXT NOT NULL DEFAULT 'OC',
  prefix_receipt     TEXT NOT NULL DEFAULT 'REC',

  payment_methods_enabled JSONB NOT NULL DEFAULT
    '["cash","debit_card","credit_card","bank_transfer"]'::jsonb,
  payment_method_default TEXT NOT NULL DEFAULT 'cash',
  payment_channels JSONB NOT NULL DEFAULT '[]'::jsonb,
  payment_show_channels_in_sale BOOLEAN NOT NULL DEFAULT FALSE,

  invoice_default_format TEXT NOT NULL DEFAULT 'pos_invoice'
    CHECK (invoice_default_format IN ('pos_invoice','letter_invoice')),
  invoice_b2x_format TEXT NOT NULL DEFAULT 'b2c'
    CHECK (invoice_b2x_format IN ('b2c','b2b','b2g')),
  return_policy TEXT NOT NULL DEFAULT '0',
  announcements TEXT,

  -- Sección 6: Cuentas abiertas / Suspendidas
  suspended_hide_payables_in_reports BOOLEAN NOT NULL DEFAULT FALSE,
  suspended_hide_account_payments_in_totals BOOLEAN NOT NULL DEFAULT FALSE,
  suspended_change_date_on_suspend BOOLEAN NOT NULL DEFAULT TRUE,
  suspended_change_date_on_complete BOOLEAN NOT NULL DEFAULT TRUE,

  -- Sección 7: Aplicación
  app_2fa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  app_test_mode BOOLEAN NOT NULL DEFAULT FALSE,
  app_quick_user_switch BOOLEAN NOT NULL DEFAULT FALSE,
  app_enable_delivery_notes BOOLEAN NOT NULL DEFAULT FALSE,
  app_language TEXT NOT NULL DEFAULT 'es' CHECK (app_language IN ('es','en')),
  app_date_format TEXT NOT NULL DEFAULT 'dd-MM-yyyy',
  app_time_format TEXT NOT NULL DEFAULT '12h' CHECK (app_time_format IN ('12h','24h')),
  app_hide_price_in_barcodes BOOLEAN NOT NULL DEFAULT FALSE,
  app_loyalty_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  app_status_sounds BOOLEAN NOT NULL DEFAULT TRUE,
  app_search_rows_per_page INT NOT NULL DEFAULT 20 CHECK (app_search_rows_per_page BETWEEN 5 AND 100),
  app_grid_items_per_page INT NOT NULL DEFAULT 15 CHECK (app_grid_items_per_page BETWEEN 5 AND 100),
  app_search_sort_order TEXT NOT NULL DEFAULT 'newest_first'
    CHECK (app_search_sort_order IN ('newest_first','oldest_first','alphabetical')),
  app_hide_panel_stats BOOLEAN NOT NULL DEFAULT FALSE,
  app_show_language_switcher BOOLEAN NOT NULL DEFAULT FALSE,
  app_show_header_clock BOOLEAN NOT NULL DEFAULT FALSE,
  app_fast_search_queries BOOLEAN NOT NULL DEFAULT TRUE,
  app_spreadsheet_format TEXT NOT NULL DEFAULT 'xlsx' CHECK (app_spreadsheet_format IN ('xlsx','csv')),
  app_logout_behavior TEXT NOT NULL DEFAULT 'redirect_login'
    CHECK (app_logout_behavior IN ('close_browser','redirect_login','lock_screen')),

  -- Auditoría
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID REFERENCES auth.users(id)
);
```

### 5.2 Tabla de auditoría: `business_settings_audit`

```sql
CREATE TABLE business_settings_audit (
  id BIGSERIAL PRIMARY KEY,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  field_name TEXT NOT NULL,
  old_value JSONB,
  new_value JSONB,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  changed_by UUID REFERENCES auth.users(id)
);

CREATE INDEX idx_bsa_business_changed ON business_settings_audit (business_id, changed_at DESC);
```

Trigger `AFTER UPDATE` en `business_settings` que escribe una fila por columna modificada.

### 5.3 RLS

```sql
ALTER TABLE business_settings ENABLE ROW LEVEL SECURITY;

-- Solo miembros del business pueden leer
CREATE POLICY bs_select ON business_settings FOR SELECT
  USING (business_id IN (SELECT business_id FROM business_members WHERE user_id = auth.uid()));

-- Solo owner / admin pueden escribir
CREATE POLICY bs_update ON business_settings FOR UPDATE
  USING (
    business_id IN (
      SELECT business_id FROM business_members
      WHERE user_id = auth.uid() AND role IN ('owner','admin')
    )
  );
```

### 5.4 Función de inicialización

```sql
CREATE OR REPLACE FUNCTION initialize_business_settings(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO business_settings (business_id)
  VALUES (p_business_id)
  ON CONFLICT (business_id) DO NOTHING;
END;
$$;
```

Llamada desde el trigger `AFTER INSERT ON businesses`.

---

## 6. Arquitectura Flutter

### 6.1 Capas

```
lib/
└── features/
    └── settings/
        ├── data/
        │   ├── settings_dto.dart          # freezed
        │   ├── settings_remote_ds.dart    # Supabase
        │   └── settings_local_cache.dart  # Hive/shared_prefs
        ├── domain/
        │   ├── settings_entity.dart       # freezed
        │   └── settings_repository.dart   # interface
        ├── application/
        │   ├── settings_controller.dart   # Riverpod
        │   └── settings_providers.dart
        └── presentation/
            ├── settings_screen.dart
            ├── widgets/
            │   ├── section_card.dart
            │   ├── setting_row.dart
            │   ├── setting_search_bar.dart
            │   └── ...
            └── sections/
                ├── company_info_section.dart
                ├── inventory_section.dart
                ├── employee_section.dart
                ├── tax_currency_section.dart
                ├── sales_receipt_section.dart
                ├── suspended_section.dart
                └── application_section.dart
```

### 6.2 Provider central

```dart
final settingsProvider = AsyncNotifierProvider<SettingsController, SettingsEntity>(
  SettingsController.new,
);

// Selectores tipados (extension methods)
extension SettingsSelectors on Ref {
  String watchPrefix(PrefixKind k) =>
    watch(settingsProvider).requireValue.getPrefix(k);

  bool watchFlag(SettingsFlag f) =>
    watch(settingsProvider).requireValue.getFlag(f);
}
```

Esto permite a cualquier widget hacer `ref.watchFlag(SettingsFlag.printAfterSale)` sin acoplarse al modelo completo.

### 6.3 Cache y sync

- **Local**: Hive box `settings_cache` con la última versión leída.
- **Estrategia**: cache-then-network. UI rinde inmediatamente con cache, dispara fetch en background, actualiza cuando llega.
- **Realtime**: suscripción Supabase Realtime al canal `business_settings:business_id=eq.{id}` para que cambios desde otra sesión se reflejen.

### 6.4 Validación

Todos los valores se validan en `SettingsController` antes de persistir:
- Prefijos: regex `^[A-Z0-9]{1,10}$`.
- Símbolo de moneda: 1-5 caracteres.
- Decimales: 0-4.
- RNC: 9 u 11 dígitos numéricos (validación RD).
- Tasa de comisión: 0.00-100.00.

---

## 7. Strangler fig: migración de call-sites

Esta es la parte que **no se puede saltar**. El objetivo es migrar los lugares que hoy hardcodean valores, a leer de `SettingsRepository`. Cada migración va con su sub-fase y golden test.

### 7.1 Inventario de call-sites a migrar

| Call-site actual | Constante actual | Setting destino |
|---|---|---|
| `lib/features/sales/printing/receipt_builder.dart:42` | `const _kPrefixSale = 'FA'` | `prefix_sale` |
| `lib/features/sales/printing/receipt_builder.dart:43` | `const _kPrefixCredit = 'NC'` | `prefix_credit_note` |
| `lib/features/sales/sale_completed_dialog.dart:18` | `const _kAutoConfirm = false` (skip) | `sale_disable_complete_confirmation` |
| `lib/features/quick_sale/quick_sale_button.dart:25` | siempre visible | `sale_disable_quick_sale` |
| `lib/features/inventory/item_form.dart:78` | `isService = false` | `inv_default_is_service` |
| `lib/core/format/currency_format.dart:12` | `'RD\$'` | `currency_symbol` |
| `lib/core/format/currency_format.dart:13` | `2` | `currency_decimals` |
| ... | (~40 más, inventario exhaustivo en sub-fase 7.A) | ... |

### 7.2 Patrón de migración (por call-site)

1. Buscar el call-site, anotarlo en `STATE_OF_THE_PLATFORM.md` sección "Settings migration".
2. Reemplazar la constante con `ref.read(settingsProvider).requireValue.<field>`.
3. Eliminar la constante antigua.
4. Añadir golden test que verifique el comportamiento bajo dos valores distintos del setting.
5. Commit con mensaje `settings(migrate): <field_name>`.

---

## 8. UI / UX

### 8.1 Layout

- **Desktop / tablet (Windows agent + Android tablet)**: dos columnas — sidebar de secciones + contenido scrolleable. Idéntico a Wilmax.
- **Móvil (Android wider)**: lista de secciones colapsables.

### 8.2 Componente base `SettingRow`

```dart
SettingRow(
  label: 'Imprimir recibo después de una venta',
  required: false,
  helperText: null,
  child: SettingToggle(
    value: settings.receiptPrintAfterSale,
    onChanged: (v) => controller.update(receiptPrintAfterSale: v),
  ),
)
```

Tipos de control:
- `SettingToggle` (bool)
- `SettingTextField` (text, numeric)
- `SettingDropdown` (enum)
- `SettingMultiSelect` (lista de enums)
- `SettingDynamicList` (denominaciones, canales de pago, tipos de precio)
- `SettingImageUpload` (logo, sello, firma)

### 8.3 Comportamiento de guardado

- **Auto-save por campo** con debounce 500ms.
- Indicador visual breve (`Guardado ✓`) tras éxito.
- Si falla, banner rojo persistente con retry.
- Cambios optimistas en UI; rollback si falla la persistencia.

### 8.4 Búsqueda

Campo `Buscar` arriba que filtra opciones por etiqueta (case-insensitive, normaliza acentos). Resalta el match. Si no hay resultados, muestra "Sin coincidencias".

### 8.5 Permisos

- Usuario sin rol `owner`/`admin`: pantalla muestra un banner "Solo lectura" y todos los controles deshabilitados.
- Botón "Aceptar" final solo dispara un toast de confirmación; el guardado real es por campo.

---

## 9. Plan de implementación por sub-fases

Siguiendo el patrón habitual: **commit por sub-fase**, golden test por sub-fase, DoD explícito.

### Sub-fase 6.A — Tabla, RLS, función init (backend)

**DoD**:
- Migration `20260510_001_create_business_settings.sql` aplicada en Supabase staging.
- RLS verificado con dos usuarios de distinto rol.
- Función `initialize_business_settings` testeada.
- Trigger en `businesses` confirmed.
- Documentación de la tabla en `docs/db/business_settings.md`.

**Commit**: `feat(settings): backend schema + RLS`

### Sub-fase 6.B — Repositorio + provider Flutter

**DoD**:
- `SettingsEntity` (freezed) con todos los campos.
- `SettingsRemoteDataSource` con `fetch()` y `update(field, value)`.
- `SettingsLocalCache` con Hive.
- `SettingsController` con cache-then-network.
- 8+ unit tests cubriendo: cache hit, cache miss, network failure, optimistic update, rollback.

**Commit**: `feat(settings): repository + riverpod controller`

### Sub-fase 6.C — UI esqueleto (sin secciones)

**DoD**:
- `SettingsScreen` accesible desde el panel.
- Sidebar de secciones renderizado.
- Búsqueda funcional (sin resultados aún, solo filtro de etiquetas).
- Guard de permisos (`owner`/`admin` only).
- 3 golden tests: layout desktop, layout móvil, banner de solo lectura.

**Commit**: `feat(settings): screen scaffold + permissions guard`

### Sub-fase 6.D — Sección "Información de la Compañía"

**DoD**:
- 6 campos funcionales y persistidos.
- Logo upload a Supabase Storage funciona.
- Validación RNC funcional.
- Migrar `businesses.name`, `rnc`, `logo_url` a leer también de `business_settings` (strangler).
- 5 golden tests.

**Commit**: `feat(settings): section company info`

### Sub-fase 6.E — Sección "Inventario"

**DoD**:
- 6 campos funcionales y persistidos.
- **Wiring real**: cada flag respetado por el módulo correspondiente:
  - `inv_disallow_no_stock` valida en `SaleController.addItem()`.
  - `inv_default_is_service` aplica en `ItemFormScreen`.
  - `inv_highlight_min_stock` aplica en `InventoryListScreen`.
- 8 golden tests (3 de UI + 5 de wiring).

**Commit**: `feat(settings): section inventory + wiring`

### Sub-fase 6.F — Sección "Empleado"

**DoD**:
- 8 campos funcionales.
- Wiring: comisión calculada en cierre de venta cuando `emp_commission_rate > 0`.
- Adaptación restaurante: "vendedor requerido" = "mesero requerido al abrir mesa".
- 6 golden tests.

**Commit**: `feat(settings): section employee + commission wiring`

### Sub-fase 6.G — Sección "Impuestos y Moneda"

⚠️ **Sub-fase crítica**. Toca el unified tax schema de PRD 2. Revisión obligatoria del PRD 2 antes de empezar.

**DoD**:
- Editor visual de tasas funcional, escribe sobre `tax_rates`.
- Denominaciones de moneda funcional, leídas por el módulo de arqueo de caja.
- `currency_symbol`, `currency_decimals`, `currency_thousands_sep`, `currency_decimal_point` migrados desde `lib/core/format/currency_format.dart`.
- 12 golden tests.

**Commit**: `feat(settings): section tax + currency + currency format strangler`

### Sub-fase 6.H — Sección "Ventas y Recibo" (parte 1: recibo)

**DoD**:
- 14 campos del subgrupo "Recibo" funcionales.
- **Integración con PRD 5**: `receipt_print_after_sale` y `receipt_auto_duplicate_on_credit_card` consumidos por el módulo unificado de impresión.
- Sello y firma upload funcional.
- 10 golden tests.

**Commit**: `feat(settings): section sales-receipt (receipt subgroup)`

### Sub-fase 6.I — Sección "Ventas y Recibo" (parte 2: comportamiento)

**DoD**:
- 22 campos restantes funcionales (interfaz, costos, cliente, prefijos, métodos pago, formato).
- Migrar 10 prefijos desde constantes hardcodeadas (strangler).
- Métodos de pago: el panel de cobro lee de `payment_methods_enabled`.
- 18 golden tests.

**Commit**: `feat(settings): section sales-receipt (behavior + prefixes strangler)`

### Sub-fase 6.J — Sección "Cuentas Abiertas / Suspendidas"

**DoD**:
- 5 campos funcionales.
- Wiring con módulo de mesas.
- 4 golden tests.

**Commit**: `feat(settings): section suspended-sales (restaurant adapted)`

### Sub-fase 6.K — Sección "Aplicación"

**DoD**:
- 19 campos funcionales (toggles funcionales; los toggles que activan features pendientes — 2FA, modo prueba, fidelización — escriben el flag pero no implementan la feature; ese es PRD futuro).
- Idioma, formato de fecha, formato de hora aplicados globalmente.
- Filas/elementos por página aplicados a búsquedas y cuadrícula.
- 14 golden tests.

**Commit**: `feat(settings): section application + global formatting`

### Sub-fase 6.L — Auditoría y closeout

**DoD**:
- Trigger de auditoría en producción.
- UI de "Historial de cambios" (read-only, accesible solo a `owner`).
- Documentación en `STATE_OF_THE_PLATFORM.md` actualizada.
- Inventario final de constantes hardcodeadas restantes (debe ser 0 para los campos cubiertos).
- Test de regresión: smoke test que verifica que ningún módulo del POS rompe al cambiar cada setting una a una.

**Commit**: `feat(settings): audit log + closeout`

---

## 10. Migración de datos

### 10.1 Para businesses existentes

```sql
-- Una sola vez tras desplegar la migration
INSERT INTO business_settings (
  business_id, logo_url, /* ... */
)
SELECT
  id,
  logo_url,
  /* otros campos hoy en businesses */
FROM businesses
WHERE id NOT IN (SELECT business_id FROM business_settings);
```

### 10.2 Decisión: deprecación de columnas en `businesses`

`businesses.logo_url`, `businesses.rnc` se mantienen como **read-mirror** por al menos 30 días post-deploy. Triggers `BEFORE UPDATE` en `business_settings` espejan esos campos hacia `businesses`. Tras 30 días de estabilidad, se eliminan de `businesses` en una migration separada.

Documentar en `MANUAL_DEFERRED_DECISION.md` análogo al patrón usado para Venta Manual.

---

## 11. Testing

### 11.1 Golden tests (Flutter)

Mínimo **80 golden tests** distribuidos:
- 5 por cada sección (UI render).
- 30+ de wiring (flag activado/desactivado → comportamiento esperado).

Ejemplos de wiring a cubrir:
- `inv_disallow_no_stock = true` + intentar añadir item sin stock → toast de error.
- `sale_disable_quick_sale = true` → botón Venta Rápida no presente en `MainScaffold`.
- `prefix_sale = 'TEST'` → siguiente venta tiene id `TEST-00001`.
- `currency_decimals = 0` → formato de moneda sin decimales en toda la UI.

### 11.2 Integration tests

- Multi-business: dos businesses, settings distintos, verificar aislamiento total.
- RLS: usuario de business A no puede leer ni escribir settings de business B.
- Realtime: cambio en sesión 1 propaga a sesión 2 dentro de 2s.

### 11.3 Smoke test final

Script que itera sobre cada setting, lo cambia, ejecuta una venta dummy completa, verifica que no rompe.

---

## 12. Definition of Done (global)

El PRD está DONE cuando:

1. ✅ Las 12 sub-fases están commiteadas con sus golden tests pasando.
2. ✅ Suite de golden tests del proyecto: **0 fallos**, **0 skipped no justificados**.
3. ✅ `STATE_OF_THE_PLATFORM.md` actualizado con sección "Module: Settings".
4. ✅ Inventario de constantes hardcodeadas migradas: 100% para campos en alcance.
5. ✅ Audit log funcionando en producción.
6. ✅ Multi-business validado en staging con 3 businesses simultáneos.
7. ✅ Documentación en `docs/features/settings.md`.
8. ✅ Cero call-sites que escriban directamente a `businesses.{logo_url, rnc}` (todos pasan por el repositorio de settings).
9. ✅ El flag de los toggles diferidos (2FA, modo prueba, fidelización) está documentado como "guardado pero no implementado, ver PRD futuro X".

---

## 13. Métricas de éxito

| Métrica | Baseline | Target |
|---|---|---|
| Tiempo para cambiar un prefijo de documento | 1 deploy (~15 min) | <30 segundos (en UI) |
| Constantes hardcodeadas en código (alcance del PRD) | ~50 | 0 |
| Tickets de soporte por "necesito cambiar X" sin deploy | (medir 30 días pre-PRD) | reducción 80% |
| Cobertura de golden tests sobre el módulo | 0% | ≥85% |
| Tiempo de carga inicial de pantalla `/configuracion` | n/a | <500ms con cache, <2s sin cache |

---

## 14. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Conflicto con unified tax schema (PRD 2) en sub-fase 6.G | Media | Alto | Revisión obligatoria del PRD 2 antes de empezar 6.G; pair review con golden tests del PRD 2. |
| Strangler fig incompleto — quedan call-sites no migrados | Media | Medio | Inventario exhaustivo en 6.A; checklist en `STATE_OF_THE_PLATFORM.md`; smoke test final. |
| Cache local desincronizado con remoto | Baja | Medio | Realtime subscription; TTL del cache de 5 min máximo; "force refresh" disponible. |
| Performance degradada por `ref.watch(settingsProvider)` en widgets de alto refresh | Media | Medio | Selectores tipados (Sec 6.2) que solo notifican cuando el campo específico cambia. |
| Multi-business: algún módulo lee settings del business equivocado | Baja | Alto | Auditoría análoga al fix de `fn_require_open_cash_session`: cada query SQL incluye `business_id` explícito. |
| Toggles diferidos confunden al usuario ("activé 2FA pero no pasa nada") | Alta | Bajo | UI muestra badge "Próximamente" en los toggles diferidos; tooltip explicativo. |
| Política de devoluciones requerida pero vacía rompe checkout | Baja | Alto | Validación en backend: NOT NULL + DEFAULT '0'. |

---

## 15. Decisiones explícitas y abiertas

### 15.1 Decisiones tomadas en este PRD

- **D1**: Una tabla flat (`business_settings`) en vez de un esquema EAV (`settings_kv`). Justificación: tipado fuerte, queries simples, las opciones son finitas y conocidas.
- **D2**: Auto-save por campo en vez de botón "Guardar" global. Justificación: feedback inmediato, paridad con apps modernas, evita perder cambios por navegación.
- **D3**: "Apartados" se traduce a "Cuentas abiertas / Suspendidas" en español de RD para restaurantes. Justificación: contexto MangoPOS.
- **D4**: Eliminar redondeo Canadá. Justificación: irrelevante para el mercado.
- **D5**: Toggles de features no implementadas (2FA, modo prueba, fidelización) se guardan pero no actúan. Justificación: paridad de superficie con Wilmax sin asumir el coste de implementación inmediata.

### 15.2 Decisiones abiertas (resolver antes de comenzar)

- **A1**: ¿Auditoría en `business_settings_audit` se conserva indefinidamente o se trunca tras N meses?
- **A2**: ¿"Modo prueba" se incluye realmente o se omite del PRD por riesgo fiscal? Recomendación inicial: omitir el toggle por completo hasta tener PRD propio que defina semánticas.
- **A3**: Tabla `business_settings` vs `business_settings_v2` con strangler fig. Para esta sub-fase no aplica strangler porque la tabla es nueva, pero conviene documentar el patrón para evolución futura.

---

## 16. Referencias

- **Wilmax POS** — captura de pantalla de configuración, `/index.php/config`, 9 mayo 2026.
- **PRD 02** — Unified Tax Schema (precondición para sub-fase 6.G).
- **PRD 04** — Venta Rápida (afectado por flag `sale_disable_quick_sale`).
- **PRD 05** — Unified Printing Module (afectado por flags `receipt_print_after_*`).
- **STATE_OF_THE_PLATFORM.md** — fuente de verdad para el inventario de strangler fig.
- **MANUAL_DEFERRED_DECISION.md** — patrón de documentación para deprecaciones diferidas.

---

## 17. Bitácora

| Fecha | Versión | Cambio | Autor |
|---|---|---|---|
| 2026-05-09 | 1.0 | Draft inicial | Cristian |
