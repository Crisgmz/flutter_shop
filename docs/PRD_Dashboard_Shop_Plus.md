# PRD — Dashboard Operacional & Toggle Venta/Devolución en POS

| Campo | Valor |
|---|---|
| **Producto** | Shop+ (Shell v1) |
| **PRD ID** | SHOP-PRD-DASHBOARD-001 |
| **Versión** | v1.0 |
| **Fecha** | 09-05-2026 |
| **Autor** | Cristian (DRI) |
| **Estado** | Draft — Pendiente de aprobación |
| **Tipo** | Feature (UI + Backend integration) |
| **Prioridad** | Alta |
| **Inspiración funcional** | WilmaxSoft POS v15.5.14b3 — Panel & Reporte de Liquidación |

---

## 1. Resumen Ejecutivo

Implementar una vista **Panel (Dashboard)** en Shop+ que consolide los KPIs operacionales del negocio y el detalle del cierre del día, replicando la **estructura de información** del Panel y Reporte de Liquidación de WilmaxSoft POS, pero **manteniendo íntegramente** la identidad visual actual de Shop+ (header azul oscuro, sidebar oscuro, tipografía y componentes existentes).

Adicionalmente, agregar un **toggle Venta / Devolución** en la vista de Punto de Venta para permitir alternar entre el flujo de venta (actual) y un nuevo flujo de devolución, sin abandonar la pantalla.

Este PRD **no introduce un rediseño**: reutiliza la shell, los colores y los componentes ya en producción en Shop+.

---

## 2. Contexto y Motivación

### 2.1 Estado actual

- Shop+ ya cuenta con módulos funcionales de **Clientes**, **Ventas (POS)**, **Cotizaciones**, **Cobros**, **Cierre de Caja**, **Inventario**, **Compras**, **Proveedores**, **Reportes**, **Gastos** y **Comprobantes**.
- La vista **Panel** del sidebar existe pero **no muestra información operativa consolidada** (placeholder o vacío).
- El **POS** sólo soporta el flujo de venta. No existe un flujo nativo de devolución desde la misma pantalla.

### 2.2 Problema

El administrador/cajero hoy debe navegar a múltiples vistas (Reportes, Cierre de Caja, Inventario, Clientes) para tener una imagen del negocio. No hay un único lugar donde se respondan las preguntas básicas:

- ¿Cuánto vendí hoy? ¿Cuántas transacciones?
- ¿Cuánto entró en efectivo? ¿Cuánto en crédito?
- ¿Hubo devoluciones? ¿Cuáles?
- ¿Cuántos clientes/items tengo en total?
- ¿Cuál es la tendencia de ventas de los últimos días?

### 2.3 Inspiración

El **Panel** y el **Reporte de Liquidación** de WilmaxSoft POS (referencia visual en Anexo A) resuelven exactamente esta necesidad con una estructura clara:

- 4 KPI cards arriba.
- Accesos directos a reportes/acciones frecuentes.
- Gráfico de ventas con toggle Mes/Semana.
- Reporte detallado de cierre con secciones: Ventas, Crédito, Devoluciones, Compras, Gastos.

Adoptamos la **arquitectura de información** y los **agregados de datos**, **no el diseño visual**.

---

## 3. Objetivos

### 3.1 Objetivos de producto

1. Reducir a **una sola vista** el tiempo necesario para responder las preguntas operativas básicas del día.
2. Igualar la **paridad funcional informativa** del Panel + Liquidación de WilmaxSoft.
3. Habilitar el flujo de **devolución desde el POS** sin cambio de pantalla.

### 3.2 Objetivos no-objetivos (para evitar scope creep)

- **NO** se rediseña el header, el sidebar ni la paleta de colores actual de Shop+.
- **NO** se reemplaza la vista actual de Reportes ni la de Cierre de Caja.
- **NO** se implementa exportación a PDF/Excel del dashboard en este PRD (queda fuera de alcance — futuro PRD).
- **NO** se implementa drill-down clicable en cada métrica (futuro PRD).

---

## 4. Alcance

### 4.1 In Scope

| ID | Funcionalidad |
|---|---|
| F1 | Vista **Panel** con 4 KPI cards |
| F2 | 5 botones de accesos directos |
| F3 | Gráfico de barras **Información de Ventas** (Mes / Semana) |
| F4 | Sección detallada de **Cierre del día actual** (Ventas / Crédito / Devoluciones / Compras / Gastos) |
| F5 | Toggle **Venta / Devolución** en pantalla POS |
| F6 | Endpoint(s) backend que devuelvan los agregados del dashboard |

### 4.2 Out of Scope

- Filtro por sucursal en el dashboard (v1 toma siempre la sucursal seleccionada en el header).
- Filtro por rango de fechas custom (v1 sólo "hoy" + gráfico Mes/Semana).
- Drill-down al hacer clic en una métrica.
- Exportación / impresión del Panel.
- Notificaciones o alertas basadas en KPIs.
- Edición o anulación de transacciones desde el dashboard.

---

## 5. Restricciones de Diseño (CRÍTICAS)

> Esta sección es **bloqueante**. Cualquier desviación requiere aprobación explícita.

### 5.1 Estructura visual a **MANTENER** (no negociable)

| Elemento | Especificación |
|---|---|
| **Header superior** | Barra azul oscuro (`bg-blue-900` / `#0a1d3a` aprox., el ya en uso) que ocupa el ancho completo. Debe contener: selector de **Sucursal** (con ícono de tienda), nombre del usuario + rol ("Usuario de Prueba / Administrador"), avatar circular con iniciales, y botón de **Salir** (ícono). Idéntico al header actual del POS de Shop+ (ver Anexo B, Imagen 4). |
| **Sidebar** | Sidebar oscuro existente con la estructura actual: secciones "OPERACIÓN", "CATÁLOGO", "CONTROL". El ítem **Panel** ya existe y debe quedar como entrada al dashboard. |
| **Branding** | Logo "Shop+" + chip "Shell v1" en la esquina superior izquierda del sidebar (sin cambios). |
| **Tipografía** | La actual de Shop+ (sans-serif, tamaños del design system existente). |
| **Paleta** | La actual de Shop+. **No** portar el naranja del Wilmax. |

### 5.2 Inspiración estructural (qué SÍ tomamos del Wilmax)

De WilmaxSoft tomamos **la organización de la información**, no la apariencia:

- Layout de 4 KPI cards en fila.
- Bloque de accesos directos con ícono + label.
- Gráfico de barras vertical con toggle Mes/Semana.
- Tabla de cierre del día con secciones tipo "header de sección" en negrita.
- Etiquetas en español con la misma terminología del dominio fiscal RD (ITBIS, RD$, "Sin impuesto", "Con impuesto", "Beneficios", etc.).

### 5.3 Adaptaciones obligatorias al estilo Shop+

- Las KPI cards de Shop+ son **rectangulares blancas con borde redondeado** (no cuadradas con bloque de color como Wilmax). Mantener el patrón ya usado en la vista **Clientes** (ver Anexo B, Imagen 3): número grande, label debajo, ícono pequeño en esquina superior derecha en chip de color suave.
- Botones de accesos directos: estilo "fila clicable" con ícono a la izquierda y texto, consistente con los inputs actuales de Shop+. Uno destacado en color de acento (azul Shop+, no naranja).
- Tablas: las del cierre del día deben usar el componente de tabla ya empleado en Clientes / Inventario.

---

## 6. Funcionalidades — Detalle

### F1. Vista Panel — Tarjetas KPI

**Ubicación:** Sidebar → Operación → **Panel** (ítem ya existente).

**Layout:** Grid de 4 columnas en desktop (≥1024px), 2 columnas en tablet, 1 columna en mobile.

| # | Tarjeta | Fuente de dato | Valor de ejemplo |
|---|---|---|---|
| 1 | **Total Ventas** | `count(*)` de ventas registradas (todas las fechas, sucursal actual) | `1862` |
| 2 | **Total Inventario** | `count(*)` de items distintos en `inventory` con stock > 0 | `371` |
| 3 | **Total Clientes** | `count(*)` de clientes activos (excluye Consumidor Final) | `231` |
| 4 | **Total Kits** | `count(*)` de kits/combos definidos | `0` |

**Criterios de aceptación:**
- AC-F1.1: Cada tarjeta muestra el número en tipografía grande, el label debajo, y un ícono representativo a la derecha.
- AC-F1.2: Si no hay datos (count = 0), la tarjeta muestra `0` (no `--` ni `N/A`).
- AC-F1.3: Los valores reflejan la **sucursal actualmente seleccionada** en el header. Cambiar de sucursal recarga los KPIs.
- AC-F1.4: Carga inicial muestra **skeleton shimmer**, no el número 0 transitorio.

---

### F2. Accesos Directos (Quick Actions)

**Layout:** Dos columnas debajo de las KPI cards. 5 acciones totales.

| # | Acción | Ícono | Destino / Comportamiento |
|---|---|---|---|
| 1 | **Informe de cierre de hoy** | reloj | Scroll suave a la sección F4 (en la misma vista) |
| 2 | **Informe de resumen de artículos de hoy** | clipboard | Navega a `Reportes` → filtro "Artículos vendidos hoy" |
| 3 | **Iniciar una nueva venta** | carrito | Navega a `Ventas` (POS) en modo Venta |
| 4 | **Informe de ventas detallada de hoy** *(destacado)* | gráfico | Navega a `Reportes` → filtro "Ventas detalladas hoy" |
| 5 | **Registrar nueva recepción / compra** | cloud-down | Navega a `Compras` → nueva |

**Criterios de aceptación:**
- AC-F2.1: La acción **Informe de ventas detallada de hoy** se renderiza en color de acento (azul primario Shop+, **no** naranja).
- AC-F2.2: Las demás 4 acciones usan el estilo neutral (fondo blanco, borde gris, texto oscuro).
- AC-F2.3: Hover muestra estado interactivo coherente con el resto de la app.
- AC-F2.4: Cada botón es accesible por teclado (tab + enter).

---

### F3. Gráfico — Información de Ventas

**Layout:** Card de ancho completo debajo de los Accesos Directos.

**Especificación:**
- Título: **Información de Ventas**.
- Tabs en la parte superior: **Mes** (default) y **Semana**.
- Gráfico de barras verticales.
- **Eje X:** días del mes (Mes) o días de la semana (Semana).
- **Eje Y:** número de ventas (transacciones), no monto.
- Color de las barras: azul primario de Shop+.
- Si no hay datos para un día, la barra es 0 (no se omite el día).

**Criterios de aceptación:**
- AC-F3.1: Tab por defecto = "Mes", muestra los días del mes en curso hasta hoy.
- AC-F3.2: Tab "Semana" muestra los últimos 7 días (incluyendo hoy).
- AC-F3.3: Cambio de tab no recarga la página, sólo el gráfico (animación suave).
- AC-F3.4: Tooltip al hover muestra: fecha completa + número de transacciones + monto total.

---

### F4. Cierre del Día — Sección Detallada

**Layout:** Tabla extensa al final de la vista. Mismo formato de dos columnas (`Descripción` | `Datos`) del Wilmax, pero usando el componente de tabla de Shop+.

**Encabezado de sección:** `Reportes - Liquidación dd-mm-yyyy` con navegación `« El día anterior` / `Siguiente día »` (links de texto en azul).

#### F4.1 — Bloque "Ventas"

| Campo | Fuente |
|---|---|
| Las ventas totales (Sin impuestos) | `SUM(sale.subtotal_sin_itbis)` |
| Las ventas totales (Con impuestos) | `SUM(sale.total)` |
| Beneficios | `SUM(sale.total - sale.cost_of_goods)` |
| Total artículos en inventario | `SUM(inventory.qty_on_hand)` |
| Valor total del inventario | `SUM(inventory.qty * cost)` |
| Desglose por categoría/item | Lista dinámica: nombre + monto |
| Número de transacciones | `count(sale)` del día |
| Ticket Tamaño promedio | `AVG(sale.total)` |
| Número de artículos vendidos | `SUM(sale_item.qty)` |
| Impuesto | `SUM(sale.itbis)` |
| Sin impuesto | `SUM(sale.subtotal_sin_itbis)` |
| Efectivo | `SUM(sale.total) WHERE payment_method = 'cash'` |

#### F4.2 — Bloque "Crédito"

| Campo | Fuente |
|---|---|
| Débitos | Movimientos de débito del día en cuentas por cobrar |
| Créditos | Movimientos de crédito del día |
| Saldo total de todas las cuentas de tiendas | `SUM(customer.balance)` actual |

#### F4.3 — Bloque "Devoluciones"

| Campo | Fuente |
|---|---|
| Los retornos totales | `SUM(return.total)` del día |
| Desglose por item devuelto | Lista dinámica |
| Número de transacciones | `count(return)` |
| Los artículos devueltos | `SUM(return_item.qty)` |
| Impuesto | `SUM(return.itbis)` |

#### F4.4 — Bloque "Compras"

| Campo | Fuente |
|---|---|
| Receivings totales (Sin impuestos) | `SUM(purchase.subtotal)` |
| Receivings totales (Con impuestos) | `SUM(purchase.total)` |
| Número de transacciones | `count(purchase)` |
| Ticket Tamaño promedio | `AVG(purchase.total)` |
| Artículos recibidos | `SUM(purchase_item.qty)` |
| Impuesto | `SUM(purchase.itbis)` |
| Sin impuesto | `SUM(purchase.subtotal)` |

#### F4.5 — Bloque "Gastos"

| Campo | Fuente |
|---|---|
| Gastos totales | `SUM(expense.amount)` del día |

#### F4.6 — Bloque "¿Monitorizar efectivo en caja registradora?"

Sección equivalente al "Cash monitoring" del Wilmax. Si no está habilitado el módulo, muestra `--`. Si está habilitado, muestra:
- Efectivo inicial declarado
- Efectivo esperado (calculado)
- Diferencia
- Botón "Ir a Cierre de Caja"

**Criterios de aceptación:**
- AC-F4.1: Todos los montos se muestran con formato `RD$ X,XXX.XX` (mismo formato que el resto de Shop+).
- AC-F4.2: Si una métrica es `0` o `null`, se muestra `RD$ 0.00`, **no** `--` (excepto F4.6 cuando el módulo está apagado).
- AC-F4.3: Los links `« El día anterior` / `Siguiente día »` cambian la fecha de referencia y recargan **sólo esta sección** (los KPIs y el gráfico no cambian).
- AC-F4.4: Si la fecha cargada > hoy, el link `Siguiente día »` se oculta o deshabilita.
- AC-F4.5: Botón **Imprimir** al final de la sección (consistente con Wilmax) que dispara la impresión nativa del navegador con un CSS `@media print` que oculta el sidebar y header.

---

### F5. Toggle Venta / Devolución en POS

**Ubicación:** Pantalla **Punto de Venta** (`Ventas`), debajo del título "Punto de Venta — Registrar nueva venta", encima de la fila de búsqueda y filtro de productos.

**UI:**
- Dos pills/botones lado a lado, centrados o alineados a la izquierda según convenga al layout actual.
- Pill **Venta**: fondo verde (`bg-green-500` aprox.), texto blanco, activo por defecto.
- Pill **Devolución**: fondo rojo (`bg-red-500` aprox.), texto blanco, inactivo por defecto.
- El pill activo tiene mayor opacidad / sombra; el inactivo se ve atenuado.
- Estado mutuamente excluyente (sólo uno activo a la vez).

**Comportamiento — Modo Venta (default):**
- Idéntico al flujo actual.
- Subtítulo: "Registrar nueva venta".
- Botón inferior: **COBRAR CONTADO** (verde).
- Carrito acumula items con cantidad positiva.

**Comportamiento — Modo Devolución:**
- Subtítulo cambia a: "Registrar devolución".
- Botón principal cambia a: **PROCESAR DEVOLUCIÓN** (rojo).
- El selector de cliente debe permitir buscar **por número de venta original** además de por cliente.
- Los items agregados al carrito muestran la cantidad como negativa o con prefijo "↩".
- El total se muestra en rojo con prefijo `-`.
- Se omiten los botones **CRÉDITO** (no aplica para devolución directa).
- El botón **CANCELAR** sigue funcionando igual.

**Criterios de aceptación:**
- AC-F5.1: Cambiar de Venta a Devolución con carrito no vacío muestra confirmación: "¿Descartar el carrito actual?".
- AC-F5.2: El estado del toggle se mantiene mientras el usuario navega dentro del POS (no persiste entre sesiones).
- AC-F5.3: El registro de devolución crea un registro en la tabla `returns` (o equivalente) referenciando la venta original cuando se proporciona.
- AC-F5.4: Una devolución descuenta del agregado de "Ventas" del día y suma a "Devoluciones" en el dashboard del día actual.
- AC-F5.5: La devolución actualiza el inventario (suma stock) y, si la venta original fue a crédito, ajusta el balance del cliente.

---

### F6. Endpoints Backend

> Especificación a alto nivel. La implementación queda al criterio de la sub-fase backend, respetando las convenciones existentes de Shop+.

| Endpoint | Método | Devuelve |
|---|---|---|
| `/api/dashboard/kpis?branch_id={id}` | GET | `{ total_ventas, total_inventario, total_clientes, total_kits }` |
| `/api/dashboard/sales-chart?branch_id={id}&range={month\|week}` | GET | `[{ date, transactions, total }]` |
| `/api/dashboard/closeout?branch_id={id}&date={yyyy-mm-dd}` | GET | objeto con los 6 bloques de F4 |
| `/api/returns` | POST | crea una devolución |

**Criterios de aceptación:**
- AC-F6.1: Todos los endpoints respetan el JWT y el `branch_id` activo del usuario (RLS o equivalente).
- AC-F6.2: Tiempo de respuesta p95 < 800ms para `/dashboard/closeout` con un día con 100 transacciones.
- AC-F6.3: Si una métrica falla en el cálculo, devuelve 0 con un flag `partial: true` en lugar de 500.

---

## 7. Modelo de Datos — Cambios Necesarios

### 7.1 Tablas existentes (sin cambios estructurales)

`sales`, `sale_items`, `purchases`, `purchase_items`, `expenses`, `customers`, `inventory`, `branches`.

### 7.2 Tabla `returns` (nueva o existente — verificar)

Si no existe:

```sql
CREATE TABLE returns (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id     uuid NOT NULL REFERENCES branches(id),
  customer_id   uuid REFERENCES customers(id),
  original_sale_id uuid REFERENCES sales(id),
  total         numeric(12,2) NOT NULL,
  itbis         numeric(12,2) NOT NULL DEFAULT 0,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid NOT NULL REFERENCES users(id)
);

CREATE TABLE return_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id   uuid NOT NULL REFERENCES returns(id) ON DELETE CASCADE,
  inventory_id uuid NOT NULL REFERENCES inventory(id),
  qty         numeric(10,2) NOT NULL,
  unit_price  numeric(12,2) NOT NULL,
  subtotal    numeric(12,2) NOT NULL
);

CREATE INDEX idx_returns_branch_date ON returns(branch_id, created_at);
```

### 7.3 Vistas materializadas (recomendado, opcional v1)

`vw_dashboard_daily_closeout(branch_id, date, ...)` — refresca cada N minutos para responder rápido al endpoint F6.

---

## 8. Definition of Done por Sub-fase

> Siguiendo la disciplina de **commit-per-sub-phase**. Cada sub-fase se cierra con un commit que referencie el `STATE_OF_THE_PLATFORM.md`.

### Sub-fase 1 — Header & Shell verification

- [ ] Confirmado que el header azul actual cumple con la especificación 5.1 (selector de sucursal, usuario, avatar, botón salir).
- [ ] Si hay desviaciones, se documentan en este PRD antes de tocar código.
- [ ] **Commit:** `chore(dashboard): verify shell baseline before PRD-001 work`.

### Sub-fase 2 — Backend: endpoints del dashboard

- [ ] Endpoints F6 implementados y testeados con datos seed.
- [ ] Tests de integración: 1 caso por endpoint con datos vacíos, 1 con datos típicos.
- [ ] Tiempos de respuesta validados (AC-F6.2).
- [ ] **Commit:** `feat(dashboard/backend): add KPIs, sales chart and closeout endpoints`.

### Sub-fase 3 — Frontend: KPI cards + Quick Actions (F1 + F2)

- [ ] Vista `Panel` con 4 KPI cards funcionando contra el endpoint real.
- [ ] 5 botones de quick action con navegación correcta.
- [ ] Estados de loading (skeleton) implementados.
- [ ] Responsive verificado en desktop, tablet y mobile.
- [ ] **Commit:** `feat(dashboard/ui): KPI cards and quick actions`.

### Sub-fase 4 — Frontend: Gráfico de Ventas (F3)

- [ ] Gráfico de barras con toggle Mes/Semana.
- [ ] Tooltip funcionando.
- [ ] Sin datos = barras a 0, no estado de error.
- [ ] **Commit:** `feat(dashboard/ui): sales information chart with month/week toggle`.

### Sub-fase 5 — Frontend: Cierre del día detallado (F4)

- [ ] 6 bloques renderizados (Ventas, Crédito, Devoluciones, Compras, Gastos, Cash monitoring).
- [ ] Navegación de día anterior / siguiente día.
- [ ] Botón Imprimir + CSS `@media print`.
- [ ] **Commit:** `feat(dashboard/ui): daily closeout detailed section`.

### Sub-fase 6 — Backend: módulo de Devoluciones (F5 backend)

- [ ] Migración para `returns` y `return_items` (si no existían).
- [ ] Endpoint `POST /api/returns` con validaciones.
- [ ] Side-effects: ajuste de inventario y de balance de cliente.
- [ ] Tests: devolución con venta original referenciada, devolución sin referencia, devolución parcial.
- [ ] **Commit:** `feat(returns/backend): returns table, endpoint and side-effects`.

### Sub-fase 7 — Frontend: Toggle Venta/Devolución en POS (F5 frontend)

- [ ] Toggle visible y funcional.
- [ ] Cambio de modo con confirmación si carrito no vacío.
- [ ] Modo Devolución renderiza UI roja, botón "PROCESAR DEVOLUCIÓN".
- [ ] Devolución se persiste y se refleja en el dashboard del día.
- [ ] **Commit:** `feat(pos/ui): venta/devolucion toggle in POS screen`.

### Sub-fase 8 — QA & Documentación

- [ ] Casos de prueba manuales de los 5 ACs principales ejecutados y documentados.
- [ ] Captura del Panel comparada con la referencia Wilmax (Anexo A) — paridad informativa, no visual.
- [ ] `STATE_OF_THE_PLATFORM.md` actualizado.
- [ ] **Commit:** `docs(dashboard): close PRD-001 with QA evidence and state update`.

---

## 9. Plan de Implementación

| Sub-fase | Estimación | Dependencias |
|---|---|---|
| 1 — Shell verification | 0.5 día | — |
| 2 — Backend endpoints | 2 días | 1 |
| 3 — KPIs + Quick Actions | 1.5 días | 2 |
| 4 — Gráfico | 1 día | 2 |
| 5 — Cierre del día detallado | 2 días | 2 |
| 6 — Backend devoluciones | 1.5 días | — (puede ir en paralelo) |
| 7 — Toggle POS frontend | 1.5 días | 6 |
| 8 — QA + docs | 1 día | 3, 4, 5, 7 |
| **TOTAL** | **~11 días** | — |

---

## 10. Métricas de Éxito

| Métrica | Baseline (hoy) | Meta post-lanzamiento |
|---|---|---|
| Tiempo para responder "¿cuánto vendí hoy?" desde login | ~3 navegaciones | 1 navegación (Panel) |
| % de cajeros que registran devoluciones desde el POS | 0% (no existe) | ≥80% en 30 días |
| Tiempo de carga p95 del Panel | N/A | < 1.5s |
| Reportes de inconsistencia entre dashboard y reportes históricos | N/A | 0 en los primeros 30 días |

---

## 11. Riesgos y Mitigaciones

| # | Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|---|
| R1 | El cálculo de "Beneficios" requiere costo unitario que no esté capturado en todas las ventas históricas | Media | Alto | Mostrar "—" en Beneficios cuando falta `cost_of_goods` en lugar de un valor inexacto. Documentar en tooltip. |
| R2 | El endpoint `closeout` se vuelve lento con días de alto volumen | Media | Medio | Vistas materializadas (sección 7.3) o cache de 60s. |
| R3 | Drift visual: alguien introduce el naranja del Wilmax al portar diseños | Alta | Alto | Sección 5 marcada como bloqueante; revisión de UI obligatoria antes de merge. |
| R4 | El módulo de Devoluciones rompe el cierre de caja existente | Media | Alto | Tests de integración entre `returns` y la lógica actual de `cierre_caja`. Sub-fase 6 incluye este caso. |
| R5 | Confusión del cajero entre modo Venta y Devolución (cobrar por error) | Baja | Alto | Diseño: pill rojo muy visible, botón inferior cambia de verde a rojo, confirmación adicional al procesar devolución > RD$ 5,000. |
| R6 | Los KPI cards muestran datos de la sucursal incorrecta tras cambiar selector | Media | Medio | Hook de cambio de sucursal debe invalidar cache del dashboard. Test E2E. |

---

## 12. Preguntas Abiertas — Pendientes de Resolución

1. **[POR CONFIRMAR]** ¿"Total Kits" debe ser `count` de definiciones de kit o suma del stock de kits ensamblados? Wilmax muestra `0` lo cual es ambiguo.
2. **[POR CONFIRMAR]** ¿Las devoluciones requieren aprobación de supervisor por encima de un monto? Si sí, ¿cuál es el umbral?
3. **[POR CONFIRMAR]** El gráfico Mes — ¿cuenta transacciones o monto total? Se asumió **transacciones** por consistencia visual con Wilmax (eje Y máximo 20). Validar.
4. **[POR CONFIRMAR]** ¿El cash monitoring (F4.6) está activo en Shop+ hoy? Si no, ¿qué se muestra? Se asumió "—" + link a Cierre de Caja.

---

## 13. Anexos

### Anexo A — Referencias visuales WilmaxSoft (sólo estructura, no estilo)

- **Imagen 1:** `screencapture-app-wilmaxpos-index-php-reports-closeout-2026-05-09-0-2026-05-09-16_21_42.png` — Reporte de Liquidación. Estructura informativa de F4.
- **Imagen 2:** `screencapture-app-wilmaxpos-index-php-home-2026-05-09-16_21_21.png` — Panel home. Estructura informativa de F1, F2, F3.

### Anexo B — Estado actual de Shop+

- **Imagen 3:** `1778358227329_image.png` — Vista Clientes de Shop+. Referencia del header azul, sidebar oscuro, KPI cards estilo Shop+ y tabla.
- **Imagen 4:** `Screenshot_2026-05-09_at_4_25_43_PM.png` — POS de Shop+ con el marcado manual de las pills "venta" (verde) y "devolucion" (rojo) que define F5.

### Anexo C — Mapeo informativo Wilmax → Shop+

| Sección Wilmax (origen) | Sección Shop+ (destino) | Adaptación |
|---|---|---|
| KPI cards naranja/rojo/verde/amarillo | F1 — KPI cards estilo Shop+ | Misma información, estilo neutral con chip de color suave |
| Quick actions con borde fino | F2 — Quick actions estilo Shop+ | Misma información, una destacada en azul Shop+ (no naranja) |
| Bar chart Mes/Semana | F3 — Bar chart | Color azul Shop+, mismo toggle |
| Tabla Liquidación con secciones grandes negras | F4 — Tabla Cierre del día | Mismo contenido, mismo formato 2 columnas, componente de tabla Shop+ |
| Header naranja con logo POS Wilmax | (ignorado — Shop+ mantiene header azul) | — |
| Sidebar oscuro con ítems repetidos | (ignorado — Shop+ ya tiene sidebar limpio) | — |

---

## 14. Aprobaciones

| Rol | Nombre | Estado | Fecha |
|---|---|---|---|
| DRI / Autor | Cristian | ✓ Draft | 09-05-2026 |
| Stakeholder de producto | — | ☐ Pendiente | — |
| Revisión técnica | — | ☐ Pendiente | — |

---

**Fin del documento — PRD-DASHBOARD-001 v1.0**
