# PRD 07 — Módulo de Reportes Unificado (Unified Reports Module)

| Campo | Valor |
|---|---|
| **Versión** | 1.0 (Draft) |
| **Autor** | Cristian (DRI) |
| **Fecha** | 2026-05-09 |
| **Estado** | DRAFT — pendiente de revisión |
| **Programa** | Fiscal Stabilization Program (post-PRD 6) |
| **Predecesor** | PRD 06 — Unified Settings Module |
| **Lenguaje primario de UI** | Español (es-DO) |

---

## 1. Resumen ejecutivo

MangoPOS necesita un módulo único de **Reportes** accesible desde el panel principal, que centralice toda la inteligencia operativa, financiera y fiscal del negocio. Replica la matriz de reportes de Wilmax POS (referencia visual de 9 mayo 2026) adaptada al contexto de restaurantes en República Dominicana, **eliminando lo que no aplica** y **agregando los reportes fiscales DGII obligatorios** (606, 607, IT-1, Cierre Z fiscal) que Wilmax no provee de forma nativa.

Resultado:
- **24 categorías de reporte** (vs 26 de Wilmax: 23 mantenidas + 1 adaptada + 4 nuevas fiscales − 2 eliminadas).
- Cada categoría con 2 modos: **Reporte Gráfico** y **Reporte de Resumen**, idéntico a Wilmax.
- Exportación a **PDF** y **XLSX/CSV** (formato según `app_spreadsheet_format` de `business_settings`).
- Backend basado en **vistas materializadas** de Supabase con refresh on-demand y nocturno.
- Integración estricta con **multi-business RLS** y permisos basados en rol.

Este es un PRD de **lectura analítica intensiva**: no modifica el esquema transaccional, lee sobre él. La complejidad está en performance, formato de salida, y precisión fiscal.

---

## 2. Contexto y motivación

### 2.1 Estado actual

Hoy en MangoPOS no hay un módulo de reportes consolidado. Lo que existe es:
- **Pantalla "Historial"** con listado plano de ventas (sin agregaciones).
- **Cierre de caja** rudimentario (solo total, sin desglose por tipo de pago ni NCF).
- **Sin reportes DGII**: el usuario debe exportar a Excel manualmente y armar 606/607 a mano.
- **Sin gráficos**: ninguna vista temporal de tendencias.
- **Sin agregaciones cross-módulo**: imposible saber "ventas por categoría del mes pasado" sin SQL directo.

### 2.2 Motivación

1. **Cumplimiento fiscal RD**: 606 y 607 son **obligatorios** mensualmente. Hoy se hacen manualmente, con riesgo de error y multas DGII.
2. **Operación diaria**: dueños y gerentes necesitan ver ventas del día, propinas por mesero, gastos, y arqueo en tiempo real.
3. **Toma de decisiones**: análisis de tendencias (qué plato vende más, qué día factura más, qué mesero tiene mejor ticket promedio) es hoy imposible.
4. **Paridad con competidores**: Wilmax tiene 26 categorías de reporte; MangoPOS tiene 0. Es la diferencia más visible para clientes evaluando ambos.
5. **Base para BI futuro**: módulo de reportes bien estructurado habilita dashboards, alertas y exportación a herramientas externas.

### 2.3 Por qué ahora

PRD 5 (Printing) entrega impresión confiable. PRD 6 (Settings) entrega configuración centralizada. Sin reportes, los dos anteriores no se "ven" en valor de negocio. PRD 7 es el primer módulo que el cliente final **abre todos los días** y que justifica la inversión en MangoPOS frente a Wilmax.

---

## 3. Objetivos

### 3.1 Objetivos primarios (must-have)

- **O1**: Pantalla `/reportes` con sidebar de 24 categorías + panel derecho con tarjetas Reporte Gráfico / Reporte de Resumen.
- **O2**: Cada reporte funcional, con filtros (rango de fecha, sucursal, empleado/mesero, categoría, etc.), agregaciones reales sobre datos transaccionales, y exportación a PDF + XLSX.
- **O3**: Reportes fiscales DGII (606, 607, IT-1, Cierre Z fiscal) producen archivos en el formato exacto que acepta la oficina virtual de DGII.
- **O4**: Performance: ningún reporte de rango ≤ 31 días excede **3 segundos** en producción con dataset realista (50k ventas/mes).
- **O5**: Multi-business riguroso: cada query incluye `business_id` explícito; RLS verificado.

### 3.2 Objetivos secundarios (should-have)

- **O6**: Reportes Personalizados: query builder visual para que el usuario defina sus propias agregaciones (dimensiones + métricas + filtros).
- **O7**: Programación de reportes: enviar el reporte X cada día/semana/mes a un email — **diferido** (toggle visible, comportamiento PRD futuro).
- **O8**: Caché local (Hive) de los últimos 5 reportes ejecutados, con TTL de 10 minutos.

### 3.3 No-objetivos (out of scope)

- **NO**: dashboards en tiempo real con WebSockets. Los reportes son request-response.
- **NO**: BI avanzado (cohortes, embudos, segmentación). PRD futuro si hay demanda.
- **NO**: integración directa con la oficina virtual de DGII (subida automática de 606/607). Solo se genera el archivo TXT; el usuario lo sube manualmente.
- **NO**: reescribir el módulo de cierre de caja existente. Se complementa con un nuevo "Cierre Z fiscal" más detallado; el cierre operativo actual queda como está.
- **NO**: alertas / notificaciones basadas en reportes ("avísame si las ventas bajan 20%"). PRD futuro.
- **NO**: módulo de tarjeta de regalo en sí. Si el toggle `giftcard_disable_detection` está apagado y existen datos, se reporta; si no, la categoría no aparece en el sidebar.

---

## 4. Alcance funcional — Catálogo de reportes

### 4.1 Categorías mantenidas de Wilmax (23)

| # | Categoría | Adaptación restaurante | Filtros principales |
|---|---|---|---|
| 1 | Categorías | Categorías de menú (Entradas, Platos fuertes, Bebidas, Postres) | Rango fecha, sucursal |
| 2 | Liquidación | Cierre de turno operativo (no fiscal — ese es separado, sec 4.3) | Turno, empleado |
| 3 | Personalizados | Query builder visual | (dinámico) |
| 4 | Comisión | Comisión por mesero (lee `emp_commission_*` de `business_settings`) | Rango fecha, mesero |
| 5 | Clientes | Top clientes, frecuencia, ticket promedio | Rango fecha, segmento |
| 6 | Ventas suspendidas | Cuentas que quedaron abiertas y no se cerraron | Rango fecha, mesa |
| 7 | Descuentos | Descuentos aplicados (cortesías, promos) | Rango fecha, tipo, empleado |
| 8 | Empleados | Productividad por empleado (ventas, hrs, tickets) | Rango fecha, rol |
| 9 | Gastos | Gastos del negocio (no compras a proveedores) | Rango fecha, categoría |
| 10 | Inventario | Stock actual, valor, movimientos | Sucursal, categoría |
| 11 | Artículos | Top platos, peor desempeño, mix de ventas | Rango fecha, categoría |
| 12 | Cobros | Pagos recibidos por método (efectivo, tarjeta, transferencia, crédito) | Rango fecha, método |
| 13 | Pagos | Pagos hechos a proveedores y cuentas por pagar | Rango fecha, proveedor |
| 14 | Pérdidas y Ganancias | P&L del período | Rango fecha, sucursal |
| 15 | Compras | Compras a proveedores | Rango fecha, proveedor |
| 16 | Caja | Movimientos de caja (apertura, cierre, ingresos, egresos) | Rango fecha, sesión |
| 17 | Ventas | Reporte maestro de ventas | Rango fecha, sucursal, empleado |
| 18 | Crédito | Cuentas a crédito, antigüedad de saldos (aging) | Cliente, antigüedad |
| 19 | Proveedores | Top proveedores, deuda actual | Rango fecha |
| 20 | Ventas suspendidas y Cotizaciones | Cotizaciones emitidas y su conversión | Rango fecha, estado |
| 21 | Etiquetas | Ventas por etiqueta (tag) | Rango fecha, etiqueta |
| 22 | Impuestos | ITBIS, propina legal, otros impuestos por período | Rango fecha, tipo |
| 23 | Precios | Cambios de precio en el tiempo, comparativa por tipo de precio | Artículo, rango fecha |

### 4.2 Categorías adaptadas (1)

| # | Wilmax | MangoPOS | Razón |
|---|---|---|---|
| 24 | Decomisos | **Mermas** | Restaurante: desperdicio de cocina, derrames, vencidos, devoluciones a cocina. Mismo concepto, distinta semántica. |

### 4.3 Categorías nuevas (4) — Reportes Fiscales DGII

⚠️ **Críticas para operación legal en RD**.

| # | Categoría | Descripción | Salida |
|---|---|---|---|
| 25 | **606 — Compras (DGII)** | Reporte mensual de compras con NCF de proveedores | TXT formato DGII + PDF resumen |
| 26 | **607 — Ventas (DGII)** | Reporte mensual de ventas con NCF emitidos | TXT formato DGII + PDF resumen |
| 27 | **IT-1 — Resumen ITBIS** | Resumen mensual de ITBIS recibido vs pagado, saldo a pagar/favor | PDF |
| 28 | **Cierre Z Fiscal** | Cierre fiscal de día/turno: totales por tipo de NCF, ITBIS desglosado, propina legal 10%, anulaciones | PDF para impresión térmica + archivo |

### 4.4 Categorías eliminadas (2)

| Wilmax | Razón eliminación |
|---|---|
| Tarjetas de regalo | No se observa uso real en MangoPOS. Se mantiene la opción condicionada al toggle `giftcard_disable_detection = false` en `business_settings`: si está activo (regalo deshabilitado) la categoría no aparece en el sidebar. |
| Kits | Cubierto por reportes de Artículos. Si surge demanda explícita se reabre como sub-fase futura. |

### 4.5 Modos de visualización

Cada categoría tiene **dos sub-reportes**, idéntico a Wilmax:

- **Reporte Gráfico**: visualización temporal (line/bar/pie chart) usando `fl_chart`. Ideal para tendencias y comparativas.
- **Reporte de Resumen**: tabla densa con totales y subtotales. Ideal para auditoría e impresión.

Excepción: las categorías fiscales (606, 607, IT-1) **no tienen modo gráfico** — solo Resumen + archivo de exportación. Mostrar 606 como gráfico sería ruido informativo.

---

## 5. Especificación detallada por reporte

A continuación las especificaciones completas. Por brevedad muestro las **ocho más críticas** en detalle; las restantes siguen el mismo patrón y se expanden en el documento técnico de cada sub-fase.

### 5.1 Ventas (categoría 17) — el más usado

**Filtros**:
- Rango de fecha (default: hoy)
- Sucursal (multi-select; default: todas a las que el usuario tiene acceso)
- Empleado/Mesero (multi-select; default: todos)
- Tipo de venta: Consumo en sitio / Para llevar / Delivery
- Tipo de NCF emitido: Consumo / Crédito Fiscal / Gubernamental / Régimen Especial / Sin NCF
- Estado: Completada / Anulada / Suspendida

**Dimensiones disponibles**:
- Fecha (día / semana / mes)
- Sucursal
- Mesero
- Categoría de menú
- Mesa
- Tipo de NCF

**Métricas**:
- Cantidad de ventas
- Total bruto
- Total ITBIS
- Total propina legal (10%)
- Total descuentos
- Total neto
- Ticket promedio
- Tiempo promedio de mesa (apertura → cierre)

**Modo Gráfico**: line chart de ventas netas por día; bar chart por mesero; pie chart por categoría.

**Modo Resumen**: tabla con todas las métricas agrupadas por dimensión seleccionada, con subtotales y total general.

**Origen de datos**:
- `sales` (transaccional)
- `sale_items`
- `sale_payments`
- `tax_lines` (PRD 2)
- `cash_sessions`

**Vista materializada**: `mv_sales_daily` — refrescada cada hora.

### 5.2 Cierre Z Fiscal (categoría 28)

**Filtros**:
- Turno (sesión de caja específica) **o** rango de fecha
- Sucursal

**Estructura del reporte**:

```
═══════════════════════════════════════════
   CIERRE Z FISCAL
   Sucursal: <name>
   Sesión: #<cash_session_id>
   Apertura: <ts>
   Cierre:   <ts>
   Cajero:   <user>
═══════════════════════════════════════════

VENTAS POR TIPO DE NCF
  B01 Crédito Fiscal      : <count>  RD$ <total>
  B02 Consumo             : <count>  RD$ <total>
  B14 Régimen Especial    : <count>  RD$ <total>
  B15 Gubernamental       : <count>  RD$ <total>
  Sin NCF (cortesía)      : <count>  RD$ <total>
                                ─────────────
  TOTAL VENTAS                    RD$ <total>

DESGLOSE ITBIS
  Base 18%                : RD$ <base>
  ITBIS 18%               : RD$ <itbis>
  Base Exenta             : RD$ <base_exempt>

PROPINA LEGAL 10%         : RD$ <propina>

ANULACIONES (Notas de crédito)
  Cantidad                : <count>
  Monto                   : RD$ <total>

PAGOS RECIBIDOS POR MÉTODO
  Efectivo                : RD$ <total>
  Tarjeta de Débito       : RD$ <total>
  Tarjeta de Crédito      : RD$ <total>
  Transferencia           : RD$ <total>
  Crédito (cuentas)       : RD$ <total>
                                ─────────────
  TOTAL COBRADO                   RD$ <total>

ARQUEO DE CAJA
  Efectivo declarado      : RD$ <declared>
  Efectivo esperado       : RD$ <expected>
  Diferencia              : RD$ <diff>  (<%>)

═══════════════════════════════════════════
   FIN CIERRE Z
═══════════════════════════════════════════
```

**Salida**: PDF para impresión térmica 80mm + PDF tamaño carta + registro en tabla `fiscal_z_closures`.

⚠️ **Crítico**: el Cierre Z **sella** la sesión de caja. Una vez generado, no se puede modificar la sesión. Si se necesita corregir, se emite un Cierre Z complementario.

**Origen**: `cash_sessions`, `sales`, `tax_lines`, `sale_payments`, `comprobantes_fiscales`.

### 5.3 606 — Compras DGII (categoría 25)

**Filtros**:
- Año
- Mes

**Estructura del archivo TXT**: cada línea corresponde a una compra, separada por `|`.

```
606|<RNC_negocio>|<periodo_AAAAMM>|<cantidad_registros>
<RNC_proveedor>|<tipo_id>|<tipo_bien_servicio>|<NCF>|<NCF_modificado>|<fecha_comprobante>|<fecha_pago>|<monto_facturado>|<itbis_facturado>|<itbis_retenido>|<itbis_proporcionalidad>|<itbis_costo>|<isr_retenido>|<impuesto_selectivo>|<otros_impuestos>|<monto_propina_legal>|<forma_pago>
...
```

**Validaciones obligatorias antes de exportar**:
- RNC del negocio configurado en `business_settings.rnc`
- Cada compra del período tiene NCF válido (formato regex `^[A-Z][0-9]{2}[0-9]{8}$`)
- Si falta NCF en alguna compra, se lista en un "informe de inconsistencias" antes de generar el TXT.

**Salida**: 
1. Archivo TXT con nombre `DGII_F_606_<RNC>_<AAAAMM>.TXT`
2. PDF resumen para archivo del negocio.

### 5.4 607 — Ventas DGII (categoría 26)

Análogo a 606 pero para ventas. Estructura del TXT:

```
607|<RNC_negocio>|<periodo_AAAAMM>|<cantidad_registros>
<RNC_cliente>|<tipo_id>|<NCF>|<NCF_modificado>|<tipo_ingreso>|<fecha_comprobante>|<fecha_retencion>|<monto_facturado>|<itbis_facturado>|<itbis_retenido>|<itbis_percibido>|<retencion_renta>|<isr_percibido>|<impuesto_selectivo>|<otros_impuestos>|<monto_propina_legal>|<efectivo>|<cheque>|<tarjeta>|<credito>|<bonos>|<permuta>|<otras_formas>
```

**Validaciones**:
- Toda venta con NCF B01 (Crédito Fiscal) debe tener RNC de cliente.
- Sumatoria de pagos = monto facturado para cada línea.
- Las ventas anuladas por nota de crédito se incluyen con el NCF de la NC referenciando el original.

### 5.5 Comisión (categoría 4)

**Filtros**: rango fecha, mesero.

**Cálculo**: respeta `emp_commission_method` de `business_settings`:
- `sale_price`: comisión sobre precio de venta
- `profit_margin`: comisión sobre margen (precio − costo)
- `total_sales`: comisión sobre total de ventas del período

**Tasa**: `business_settings.emp_commission_rate`. Si el usuario tiene tasa individual (campo `users.commission_rate_override`), prevalece ese.

**Resultado**: tabla con: mesero, ventas totales, base de cálculo, % comisión, monto comisión.

### 5.6 Mermas (categoría 24)

**Filtros**: rango fecha, sucursal, motivo.

**Origen**: tabla `inventory_movements` con `movement_type IN ('waste', 'breakage', 'expired', 'kitchen_return')`.

**Resultado**: tabla con: fecha, item, cantidad, costo, motivo, registrado por.

### 5.7 Liquidación (categoría 2 — operativo, no fiscal)

Reporte breve para fin de turno. Diferenciado del **Cierre Z Fiscal** (categoría 28) que es exhaustivo.

**Contenido**:
- Total ventas del turno
- Total cobros por método
- Propinas reportadas (informativas)
- Tickets atendidos
- Promedio por ticket

### 5.8 Personalizados (categoría 3)

Query builder visual:
1. Selector de origen: Ventas / Compras / Inventario / Clientes / Empleados / Caja
2. Selector de dimensiones (multi-select): fecha, sucursal, empleado, categoría, etc.
3. Selector de métricas: count, sum, avg, min, max sobre campos numéricos.
4. Filtros: AND de condiciones simples (`campo op valor`).
5. Vista previa en vivo (limitado a 100 filas).
6. Botón "Guardar" → persiste en `custom_reports` con nombre y permisos.

**Restricción**: por seguridad, el query builder **no permite SQL crudo**. Genera SQL parametrizado que pasa por validación server-side (lista blanca de tablas y columnas).

---

## 6. Modelo de datos

### 6.1 Vistas materializadas (Supabase)

```sql
-- Ventas diarias agregadas
CREATE MATERIALIZED VIEW mv_sales_daily AS
SELECT
  s.business_id,
  s.branch_id,
  DATE(s.sale_date AT TIME ZONE 'America/Santo_Domingo') AS sale_day,
  s.seller_user_id,
  s.ncf_type,
  COUNT(*) AS sales_count,
  SUM(s.gross_total) AS gross_total,
  SUM(s.itbis_total) AS itbis_total,
  SUM(s.legal_tip_total) AS legal_tip_total,
  SUM(s.discount_total) AS discount_total,
  SUM(s.net_total) AS net_total
FROM sales s
WHERE s.status = 'completed'
GROUP BY 1,2,3,4,5;

CREATE UNIQUE INDEX idx_mv_sales_daily_pk
  ON mv_sales_daily (business_id, branch_id, sale_day, seller_user_id, ncf_type);

CREATE INDEX idx_mv_sales_daily_business_day
  ON mv_sales_daily (business_id, sale_day DESC);
```

Análogos para:
- `mv_sales_by_item` (ventas por artículo)
- `mv_sales_by_category` (ventas por categoría de menú)
- `mv_purchases_daily`
- `mv_inventory_movements_daily`
- `mv_cash_session_summary`

### 6.2 Refresh strategy

Tres modos:

1. **Programado**: CRON nocturno a las 03:00 RD time refresca todas las MVs.
2. **On-demand**: si el usuario abre un reporte y la MV tiene `staleness > 1 hora`, dispara refresh asíncrono y muestra banner "Actualizando…".
3. **Trigger-based**: para reportes intra-día críticos (Caja, Liquidación) se usa **incremental refresh** vía `pg_cron` cada 15 minutos.

### 6.3 Tablas nuevas

```sql
-- Cierres Z fiscales emitidos (inmutable post-emisión)
CREATE TABLE fiscal_z_closures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  branch_id UUID NOT NULL REFERENCES branches(id),
  cash_session_id UUID NOT NULL REFERENCES cash_sessions(id),
  closure_number INT NOT NULL,
  emitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  emitted_by UUID NOT NULL REFERENCES auth.users(id),
  payload JSONB NOT NULL,            -- snapshot completo del cierre
  pdf_url TEXT,                      -- URL en Supabase Storage
  is_complementary BOOLEAN NOT NULL DEFAULT FALSE,
  parent_closure_id UUID REFERENCES fiscal_z_closures(id),
  UNIQUE (business_id, branch_id, closure_number)
);

-- Reportes 606 / 607 generados
CREATE TABLE fiscal_dgii_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  report_type TEXT NOT NULL CHECK (report_type IN ('606','607','IT1')),
  period_year INT NOT NULL,
  period_month INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  generated_by UUID REFERENCES auth.users(id),
  records_count INT NOT NULL,
  txt_file_url TEXT,
  pdf_file_url TEXT,
  inconsistencies JSONB,             -- registros excluidos por validación
  UNIQUE (business_id, report_type, period_year, period_month)
);

-- Reportes Personalizados
CREATE TABLE custom_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  name TEXT NOT NULL,
  config JSONB NOT NULL,             -- definición del query builder
  is_shared BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (business_id, name)
);

-- Auditoría de generación de reportes
CREATE TABLE report_generation_log (
  id BIGSERIAL PRIMARY KEY,
  business_id UUID NOT NULL,
  user_id UUID,
  report_category TEXT NOT NULL,
  report_mode TEXT NOT NULL CHECK (report_mode IN ('graphic','summary','export')),
  filters JSONB,
  duration_ms INT,
  rows_returned INT,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rgl_business_date
  ON report_generation_log (business_id, generated_at DESC);
```

### 6.4 RLS

```sql
ALTER TABLE fiscal_z_closures ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_dgii_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_generation_log ENABLE ROW LEVEL SECURITY;

-- Solo miembros del business pueden leer
CREATE POLICY rep_read ON fiscal_z_closures FOR SELECT
  USING (business_id IN (SELECT business_id FROM business_members WHERE user_id = auth.uid()));

-- Solo owner/admin pueden generar reportes fiscales
CREATE POLICY rep_write ON fiscal_dgii_reports FOR INSERT
  WITH CHECK (
    business_id IN (
      SELECT business_id FROM business_members
      WHERE user_id = auth.uid() AND role IN ('owner','admin','accountant')
    )
  );

-- Cierres Z son inmutables: NO UPDATE policy
```

### 6.5 Funciones SECURITY DEFINER

```sql
-- Refrescar todas las MVs de un business (uso interno)
CREATE OR REPLACE FUNCTION refresh_business_reports(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_sales_daily;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_sales_by_item;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_sales_by_category;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_purchases_daily;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_inventory_movements_daily;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_cash_session_summary;
END;
$$;

-- Sellar cierre Z (inmutable post-llamada)
CREATE OR REPLACE FUNCTION seal_fiscal_z_closure(
  p_business_id UUID,
  p_branch_id UUID,
  p_cash_session_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_closure_id UUID;
  v_payload JSONB;
  v_next_number INT;
BEGIN
  -- Verificar que la sesión existe y está cerrada
  IF NOT EXISTS (
    SELECT 1 FROM cash_sessions
    WHERE id = p_cash_session_id
      AND business_id = p_business_id
      AND branch_id = p_branch_id
      AND closed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Cash session not found or not closed';
  END IF;

  -- Verificar que no exista ya un cierre Z para esta sesión
  IF EXISTS (
    SELECT 1 FROM fiscal_z_closures
    WHERE cash_session_id = p_cash_session_id
      AND is_complementary = FALSE
  ) THEN
    RAISE EXCEPTION 'Z closure already exists for this session';
  END IF;

  -- Calcular siguiente número correlativo
  SELECT COALESCE(MAX(closure_number), 0) + 1
    INTO v_next_number
    FROM fiscal_z_closures
   WHERE business_id = p_business_id AND branch_id = p_branch_id;

  -- Construir payload (snapshot)
  v_payload := build_z_closure_payload(p_business_id, p_branch_id, p_cash_session_id);

  INSERT INTO fiscal_z_closures (
    business_id, branch_id, cash_session_id, closure_number, emitted_by, payload
  ) VALUES (
    p_business_id, p_branch_id, p_cash_session_id, v_next_number, auth.uid(), v_payload
  ) RETURNING id INTO v_closure_id;

  RETURN v_closure_id;
END;
$$;
```

⚠️ **Multi-business awareness**: cada función incluye `business_id` explícito en los WHERE. Lección aprendida del fix de `fn_require_open_cash_session`.

---

## 7. Arquitectura Flutter

### 7.1 Capas

```
lib/
└── features/
    └── reports/
        ├── data/
        │   ├── dto/
        │   │   ├── sales_report_dto.dart
        │   │   ├── z_closure_dto.dart
        │   │   ├── dgii_606_dto.dart
        │   │   ├── dgii_607_dto.dart
        │   │   └── ...
        │   ├── reports_remote_ds.dart      # Supabase RPC
        │   └── reports_local_cache.dart    # Hive (TTL 10 min)
        ├── domain/
        │   ├── report_category.dart        # enum 24 categorías
        │   ├── report_filter.dart          # freezed
        │   ├── report_result.dart          # freezed
        │   └── reports_repository.dart
        ├── application/
        │   ├── reports_controller.dart     # Riverpod
        │   ├── filter_controller.dart
        │   └── export_controller.dart
        ├── export/
        │   ├── pdf/
        │   │   ├── pdf_renderer.dart       # paquete `pdf`
        │   │   ├── z_closure_pdf.dart
        │   │   ├── 606_pdf.dart
        │   │   └── ...
        │   └── xlsx/
        │       ├── xlsx_renderer.dart      # paquete `excel`
        │       └── ...
        └── presentation/
            ├── reports_screen.dart         # sidebar + panel
            ├── widgets/
            │   ├── category_sidebar.dart
            │   ├── report_card.dart        # Gráfico / Resumen
            │   ├── filter_bar.dart
            │   ├── chart_renderer.dart     # fl_chart
            │   └── summary_table.dart
            └── categories/
                ├── sales_report_screen.dart
                ├── z_closure_screen.dart
                ├── dgii_606_screen.dart
                ├── dgii_607_screen.dart
                ├── custom_report_screen.dart
                └── ...
```

### 7.2 Riverpod providers

```dart
final reportCategoryProvider = StateProvider<ReportCategory?>((ref) => null);

final reportFilterProvider = StateNotifierProvider<FilterController, ReportFilter>(
  (ref) => FilterController(),
);

final reportResultProvider = FutureProvider.autoDispose
    .family<ReportResult, ReportRequest>((ref, request) async {
  final repo = ref.watch(reportsRepositoryProvider);
  return repo.execute(request);
});
```

### 7.3 Performance

- **Paginación**: tablas resumen con scroll infinito, 50 filas por batch.
- **Skeleton loading**: mientras la query corre.
- **Cancelación**: si el usuario cambia filtro antes de que la query termine, se cancela la in-flight (ver `autoDispose.family` arriba).
- **Web workers**: el render de XLSX corre en isolate (`compute()`) para no bloquear UI.

### 7.4 Paquetes Flutter

| Paquete | Uso |
|---|---|
| `fl_chart: ^0.69.0` | Gráficos (line, bar, pie) |
| `pdf: ^3.11.0` + `printing: ^5.13.0` | Generación PDF |
| `excel: ^4.0.6` | Generación XLSX |
| `csv: ^6.0.0` | Generación CSV |
| `path_provider: ^2.1.0` | Guardar archivos localmente antes de share |
| `share_plus: ^10.0.0` | Compartir/imprimir archivo generado |
| `intl: ^0.20.0` | Formato fechas/moneda según `business_settings` |

---

## 8. Sistema de exportación

### 8.1 PDF

- **Plantillas reutilizables** por familia: ventas, fiscal, inventario, financiero.
- **Header común**: logo del negocio (de `business_settings.logo_url`), nombre, RNC, sucursal, rango del reporte, generado por, timestamp.
- **Footer común**: número de página, MangoPOS firma.
- **Modos de impresión**:
  - Carta (8.5×11) para archivo
  - Térmico 80mm (solo para Cierre Z fiscal y reportes operativos compactos)

### 8.2 XLSX / CSV

- **Formato**: respeta `business_settings.app_spreadsheet_format`. Si es `xlsx`, archivo Excel con formato; si es `csv`, archivo CSV plano.
- **Hoja única** por reporte; columnas tipadas (números como número, fechas como fecha, no string).
- **Header congelado** en XLSX para scroll fácil.
- **Filtros automáticos** activados en XLSX.

### 8.3 Archivos DGII (TXT)

- **Encoding**: UTF-8 sin BOM.
- **Separador**: `|`.
- **Sin cabecera** de columnas (DGII no la espera).
- **Validación previa**: antes de generar, se ejecuta `validate_dgii_export(report_type, period)` que devuelve lista de inconsistencias. Si hay inconsistencias críticas (ej: NCF inválido), bloquea generación. Si son informativas, permite generar y adjunta hoja de inconsistencias en el PDF resumen.

### 8.4 Storage

Archivos generados se suben a Supabase Storage bajo `reports/{business_id}/{year}/{month}/` con TTL de 90 días post-generación. La URL se persiste en `report_generation_log` o `fiscal_dgii_reports`.

---

## 9. UI / UX

### 9.1 Layout principal

Réplica de Wilmax con dos columnas:

- **Sidebar central** (320px): lista vertical de las 24 categorías con icono + nombre. Categoría seleccionada se resalta.
- **Panel derecho** (resto del ancho): tarjetas "Reportes Gráficos" y "Reportes de Resumen". Click → abre la pantalla específica del reporte.

Idéntico a Wilmax visualmente.

### 9.2 Pantalla de reporte específico

Layout vertical:
1. **Breadcrumb**: `Panel / Reportes / Ventas / Reporte de Resumen`
2. **Filter bar** sticky en la parte superior (rango de fecha, sucursal, etc.)
3. **Botones de acción**: Refrescar, Exportar (PDF / XLSX / CSV), Imprimir
4. **Cuerpo**: gráfico o tabla según modo
5. **Footer**: total de filas, tiempo de ejecución, badge "Datos al hh:mm"

### 9.3 Filtros

- **Rango de fecha**: con presets (Hoy, Ayer, Esta semana, Este mes, Mes anterior, Personalizado)
- **Multi-select**: dropdown con búsqueda y "Seleccionar todos"
- **Persistencia**: el último filtro usado por categoría se persiste en preferencias locales del usuario.

### 9.4 Permisos

- `owner` / `admin`: acceso total a todas las categorías.
- `accountant`: acceso a 606, 607, IT-1, Impuestos, P&L, Compras, Ventas (lectura).
- `manager`: operativos (Ventas, Caja, Empleados, Comisión, Inventario).
- `cashier`: solo Liquidación de su propio turno y Cierre Z de su propia sesión.

Validación en RLS + en UI (categorías sin permiso no aparecen en el sidebar).

### 9.5 Modo gráfico vs resumen

- **Toggle** prominente en cada pantalla de reporte.
- Si el reporte es solo Resumen (los fiscales), el toggle no aparece.
- Persiste última preferencia por reporte.

---

## 10. Integración con `business_settings` (PRD 6)

| Setting | Uso en Reportes |
|---|---|
| `app_spreadsheet_format` | Determina si exportar XLSX o CSV. |
| `currency_symbol`, `currency_decimals`, `currency_thousands_sep`, `currency_decimal_point` | Formato de moneda en PDF, XLSX y UI. |
| `app_date_format`, `app_time_format` | Formato de fechas/horas. |
| `emp_commission_rate`, `emp_commission_method` | Cálculo del reporte de Comisión. |
| `giftcard_disable_detection` | Si `true`, oculta categoría Tarjetas de Regalo. |
| `app_search_rows_per_page` | Paginación de tablas resumen. |
| `app_loyalty_enabled` | Si `false`, oculta secciones de fidelización en reporte de Clientes. |
| `prefix_*` | Mostrar id formateado en columnas. |
| `receipt_text_size` | Tamaño de texto en PDF térmico de Cierre Z. |

Si en algún momento se cambia un setting mientras el reporte está abierto, la UI emite toast "Configuración actualizada — refrescar para aplicar" y el botón Refrescar parpadea.

---

## 11. Plan de implementación por sub-fases

### Sub-fase 7.A — Backend: vistas materializadas + RLS + tablas nuevas

**DoD**:
- Migration `20260520_001_reports_schema.sql` aplicada en staging.
- 6 vistas materializadas creadas + indexadas.
- 4 tablas nuevas con RLS verificado por usuarios de distintos roles.
- Función `seal_fiscal_z_closure` testeada con casos: sesión no cerrada, cierre duplicado, multi-business cross-contamination.
- `pg_cron` configurado: refresh nocturno + intra-día cada 15 min para MVs operativas.
- Documentación en `docs/db/reports_schema.md`.

**Commit**: `feat(reports): backend schema + materialized views + sealing fn`

### Sub-fase 7.B — Repositorio + provider Flutter base

**DoD**:
- `ReportsRepository` con `execute(ReportRequest)` que despacha a Supabase RPC apropiado.
- `ReportFilter` y `ReportResult` (freezed).
- Cache local con Hive (TTL 10 min).
- 10+ unit tests: cache hit/miss, filtros vacíos, multi-business aislamiento, error handling.

**Commit**: `feat(reports): repository + riverpod controller`

### Sub-fase 7.C — UI esqueleto: sidebar + panel + filtros base

**DoD**:
- `ReportsScreen` accesible desde panel principal.
- Sidebar con 24 categorías (placeholders por ahora).
- Panel derecho con tarjetas Gráfico/Resumen.
- `FilterBar` con rango de fecha y sucursal funcional.
- Guard de permisos por rol.
- 5 golden tests: layout desktop, layout móvil, sidebar con permisos restringidos, filter bar abierto, filter bar cerrado.

**Commit**: `feat(reports): screen scaffold + filters + permissions`

### Sub-fase 7.D — Sistema de exportación PDF + XLSX + CSV

**DoD**:
- `pdf_renderer` con plantilla base (header, footer, paginación).
- `xlsx_renderer` con formato tipado (números, fechas).
- `csv_renderer` simple.
- Render en isolate para XLSX (no bloquear UI).
- Subida a Supabase Storage + URL persistida.
- 8 golden tests sobre PDFs (snapshots) + 4 unit tests sobre XLSX.

**Commit**: `feat(reports): export pipeline (pdf+xlsx+csv)`

### Sub-fase 7.E — Reportes operativos del día

Categorías: **Ventas, Caja, Liquidación, Cobros, Pagos, Ventas suspendidas**.

**DoD**:
- 6 reportes funcionales en ambos modos (gráfico + resumen) excepto Liquidación que es solo resumen.
- Filtros completos por reporte.
- Exportación PDF + XLSX en cada uno.
- Performance verificada: <3s en dataset de 50k ventas/mes.
- 18 golden tests (3 por reporte).

**Commit**: `feat(reports): operational reports (sales/cash/cobros/pagos/etc)`

### Sub-fase 7.F — Reportes de empleados

Categorías: **Empleados, Comisión**.

**DoD**:
- Cálculo de comisión respeta `business_settings.emp_commission_*`.
- Override por usuario funcional (`users.commission_rate_override`).
- Adaptación restaurante: "vendedor" = "mesero".
- 6 golden tests.

**Commit**: `feat(reports): employee + commission reports`

### Sub-fase 7.G — Reportes de productos e inventario

Categorías: **Inventario, Artículos, Categorías, Etiquetas, Precios, Mermas**.

**DoD**:
- 6 reportes funcionales.
- Mermas adaptadas (no Decomisos): origen `inventory_movements` con tipos `waste/breakage/expired/kitchen_return`.
- Reporte de Precios con histórico (cambios en el tiempo).
- 18 golden tests.

**Commit**: `feat(reports): product + inventory + waste reports`

### Sub-fase 7.H — Reportes financieros

Categorías: **Pérdidas y Ganancias, Crédito, Gastos, Compras, Proveedores**.

**DoD**:
- P&L con configuración: período, sucursal, drill-down por categoría de gasto.
- Crédito con aging (0-30, 31-60, 61-90, +90 días).
- 15 golden tests.

**Commit**: `feat(reports): financial reports (p&l/credit/expenses/etc)`

### Sub-fase 7.I — Reportes de clientes

Categorías: **Clientes, Descuentos**.

(Tarjetas de Regalo se omite salvo que `giftcard_disable_detection = false`.)

**DoD**:
- Top clientes por frecuencia y ticket promedio.
- Descuentos por tipo (cortesía, promo, manual).
- 6 golden tests.

**Commit**: `feat(reports): customer + discount reports`

### Sub-fase 7.J — Reportes Fiscales DGII (★ crítica)

Categorías: **606, 607, IT-1, Cierre Z Fiscal, Impuestos**.

**DoD**:
- 606 genera TXT en formato DGII validado contra el especificador oficial vigente.
- 607 genera TXT en formato DGII validado contra el especificador oficial vigente.
- IT-1 genera PDF con resumen mensual.
- Cierre Z fiscal funcional, sellado vía `seal_fiscal_z_closure`, inmutable.
- Reporte de Impuestos con desglose por tasa.
- Validación pre-export con bloqueo en inconsistencias críticas + reporte de inconsistencias.
- **Pruebas con dataset real**: tomar el último mes cerrado de un cliente piloto, generar 606/607, validar contra lo que ese cliente declaró manualmente.
- 25 golden tests + 4 integration tests con archivos TXT comparados byte-a-byte contra fixtures.

**Commit**: `feat(reports): DGII fiscal reports (606/607/IT1/Z-closure)`

### Sub-fase 7.K — Reportes Personalizados (query builder)

**DoD**:
- Query builder visual: origen, dimensiones, métricas, filtros.
- Validación server-side con lista blanca de tablas/columnas.
- Persistencia en `custom_reports`.
- Compartir reporte entre usuarios del mismo business (toggle `is_shared`).
- 12 golden tests.

**Commit**: `feat(reports): custom report builder`

### Sub-fase 7.L — Closeout, audit log y documentación

**DoD**:
- `report_generation_log` activo en producción.
- UI de "Mis reportes generados" (read-only, accesible a `owner`/`admin`).
- `STATE_OF_THE_PLATFORM.md` actualizado con sección "Module: Reports".
- Documentación operativa en `docs/features/reports.md` con un capítulo completo sobre 606/607.
- Smoke test que abre cada categoría, ejecuta con filtros default, exporta PDF y XLSX, verifica que no rompe.

**Commit**: `feat(reports): audit log + closeout`

---

## 12. Migración / Backfill

### 12.1 Refresh inicial de MVs

Tras desplegar la migration, ejecutar `SELECT refresh_business_reports(id) FROM businesses;` para poblar las MVs por primera vez. Tiempo estimado por business mediano: ~2 min.

### 12.2 Cierres Z históricos

⚠️ **Decisión explícita**: NO se generan cierres Z fiscales retroactivos para sesiones de caja ya cerradas en el pasado. El primer cierre Z emitido marca el inicio del histórico fiscal. Documentar esta decisión en `MANUAL_DEFERRED_DECISION.md`.

### 12.3 Reportes 606/607 históricos

Se permiten para cualquier mes pasado donde existan datos transaccionales. La validación previa flagueará inconsistencias (ventas sin NCF, etc.) que el usuario decide cómo tratar antes de exportar.

---

## 13. Testing

### 13.1 Golden tests (Flutter)

Mínimo **120 golden tests** distribuidos:
- 5 por categoría no fiscal (UI render gráfico + resumen + filter states).
- 25 sobre reportes fiscales (incluyendo edge cases de validación).
- 12 sobre custom reports.
- 8 sobre exportación PDF (snapshots).

### 13.2 Integration tests críticos

- **Multi-business**: dos businesses, generar 606 cada uno, verificar que ningún registro cruza.
- **RLS**: usuario `cashier` no puede acceder a 606.
- **Inmutabilidad de Cierre Z**: tras sellar, intentar UPDATE → falla.
- **606/607 byte-a-byte**: contra fixtures de archivos previamente validados con DGII.
- **Performance**: dataset de 100k ventas/mes, todos los reportes < 5s.

### 13.3 Smoke test final

Script que itera sobre las 24 categorías, ejecuta con filtros default, exporta PDF y XLSX, valida tamaño no-cero y formato válido.

### 13.4 Validación con cliente piloto

Antes de salir a producción, generar 606 y 607 de un mes ya declarado por un cliente piloto; comparar línea-por-línea con su declaración manual. Documentar las diferencias y resolver antes de release.

---

## 14. Definition of Done (global)

El PRD está DONE cuando:

1. ✅ Las 12 sub-fases commiteadas con sus golden tests pasando.
2. ✅ Suite total: **0 fallos**, **0 skipped no justificados**.
3. ✅ Performance: ningún reporte ≤ 31 días excede 3s en producción con 50k ventas/mes.
4. ✅ Validación con cliente piloto (606/607 mes ya declarado): coincidencia byte-a-byte o diferencias documentadas y aceptadas.
5. ✅ `STATE_OF_THE_PLATFORM.md` actualizado.
6. ✅ Documentación operativa publicada con capítulo dedicado a 606/607 (paso a paso para el contador del cliente).
7. ✅ Multi-business validado en staging con 3 businesses simultáneos.
8. ✅ Cierre Z fiscal: inmutabilidad verificada en producción.
9. ✅ Cero queries directas a la base sin pasar por las funciones SECURITY DEFINER (auditoría).

---

## 15. Métricas de éxito

| Métrica | Baseline | Target |
|---|---|---|
| Tiempo para generar 606 mensual | ~2-4 horas (manual en Excel) | <60 segundos |
| Errores de NCF detectados antes de subir a DGII | 0 (no hay validación) | 100% de inconsistencias detectadas |
| Tiempo de carga del reporte de Ventas mensual | n/a | <3 segundos |
| Cobertura golden tests | 0% | ≥80% |
| Tickets de soporte "cómo saco X reporte" | (medir 30 días pre-PRD) | reducción 70% |
| Adopción: usuarios únicos que abren `/reportes` por semana | 0 | ≥80% de los businesses activos |
| Cierres Z generados al cierre de turno | 0% | ≥95% de sesiones cerradas |

---

## 16. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Cambio en formato 606/607 por DGII durante desarrollo | Media | Alto | Sub-fase 7.J usa el formato vigente al momento de implementar; PRD no asume estabilidad. Suscripción manual al boletín DGII como parte del proceso de mantenimiento. |
| MVs lentas con datasets grandes | Media | Alto | Estrategia mixta: refresh nocturno + incremental cada 15 min para operativos. Si no alcanza, escalar a vistas particionadas por mes. |
| Inmutabilidad del Cierre Z confunde al usuario que necesita "corregir" | Media | Medio | UI explícita: para corregir se emite Cierre Z **complementario** (campo `is_complementary`), no se modifica el original. Documentación con ejemplos. |
| Multi-business cross-contamination en MVs | Baja | Crítico | Cada MV indexa `business_id` como primer campo del PK. Test de integración explícito que verifica aislamiento. |
| Custom reports → SQL injection | Baja | Crítico | Query builder NO acepta SQL crudo. Lista blanca server-side de tablas y columnas. Validación con fuzzing en sub-fase 7.K. |
| Generación de PDF/XLSX bloquea UI con datasets grandes | Media | Medio | Render en isolate (`compute()`) para XLSX. PDF con paginación lazy. |
| Validación 606/607 con cliente piloto encuentra diferencias inesperadas | Alta | Alto | Hacerlo en sub-fase 7.J **antes** de cerrar la sub-fase; presupuestar 2 días de iteración para resolver diferencias. |
| Tendencia a "respuesta intelectualmente correcta vs operativamente diferente" | Conocida | Medio | Disciplina explícita: cada sub-fase tiene DoD checklist. No marcar como done sin tachar todos los items. Self-review antes de commit. |
| Reportes históricos no funcionan porque los datos antiguos no tienen NCF | Alta | Medio | Validación previa flaguea filas sin NCF y permite al usuario decidir si excluirlas o no exportar. |

---

## 17. Decisiones explícitas y abiertas

### 17.1 Decisiones tomadas

- **D1**: 24 categorías totales (23 mantenidas + 1 adaptada + 4 nuevas fiscales − 2 eliminadas). No hay paridad 1:1 con Wilmax porque Wilmax no tiene reportes DGII.
- **D2**: Reportes fiscales (606/607/IT-1) **no tienen modo gráfico**. Solo Resumen + archivo de exportación.
- **D3**: Cierre Z fiscal **inmutable** post-sellado. Correcciones se hacen vía cierre complementario.
- **D4**: NO se generan cierres Z retroactivos para sesiones cerradas antes del PRD.
- **D5**: Custom reports usan **lista blanca** server-side; nunca SQL crudo del cliente.
- **D6**: Email programado de reportes queda como toggle diferido (paridad de superficie sin compromiso de implementación).
- **D7**: Tarjetas de Regalo y Kits eliminados como categorías independientes. Tarjetas reaparece condicionalmente; Kits se cubre con Artículos.

### 17.2 Decisiones abiertas (resolver antes de comenzar)

- **A1**: ¿Las MVs se refrescan también al `INSERT` en `sales`/`purchases` vía trigger, o solo por CRON? Trigger garantiza frescura pero impacta latencia transaccional. Recomendación inicial: solo CRON + refresh on-demand al abrir reporte si staleness > 1h.
- **A2**: ¿Cierre Z fiscal y cierre operativo de caja son el **mismo** evento de UI o dos botones distintos? Recomendación: dos eventos. El cierre operativo cierra `cash_sessions`. El cierre Z fiscal lo emite el sistema automáticamente al cerrar la sesión, pero es archivo independiente.
- **A3**: Encoding del TXT DGII — ¿UTF-8 sin BOM o ANSI? El especificador no es 100% explícito. Recomendación: validar con cliente piloto en sub-fase 7.J.
- **A4**: ¿Mostrar el reporte 606 con datos de **cualquier** mes pasado, o restringir a meses con cierre fiscal cerrado? Recomendación: cualquier mes, con banner "Período aún abierto" si no está cerrado.

---

## 18. Referencias

- **Wilmax POS** — captura de pantalla `/index.php/reports`, 9 mayo 2026.
- **PRD 02** — Unified Tax Schema (origen de `tax_lines`).
- **PRD 04** — Venta Rápida (origen de ventas express en reportes).
- **PRD 05** — Unified Printing Module (impresión térmica de Cierre Z).
- **PRD 06** — Unified Settings Module (settings consumidos por todos los reportes).
- **DGII** — Especificador técnico de archivos 606 y 607 (versión vigente al inicio de sub-fase 7.J).
- **STATE_OF_THE_PLATFORM.md** — fuente de verdad del programa.
- **MANUAL_DEFERRED_DECISION.md** — patrón de documentación para deprecaciones diferidas.

---

## 19. Bitácora

| Fecha | Versión | Cambio | Autor |
|---|---|---|---|
| 2026-05-09 | 1.0 | Draft inicial | Cristian |
