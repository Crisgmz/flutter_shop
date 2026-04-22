# PLAN_MAESTRO_FLUTTER_SHOP.md

## Plan maestro de ejecución para `flutter_shop+`

Este documento organiza el trabajo pendiente del sistema en prioridades reales de producto.

La UI general se considera suficientemente buena para continuar. Por tanto, el foco pasa del polish visual a cerrar el núcleo operativo, fiscal, transaccional y de control.

---

## 1. Bloqueantes

### 1.1 POS transaccional
Objetivo: que una venta no pueda quedar a medias ni deje inconsistencias entre cabecera, líneas, stock, pagos y caja.

#### Hay que resolver
- flujo atómico de venta + líneas + pago
- validación previa de stock
- validación de precios, impuestos y totales
- normalización de `receipt_type`
- relación consistente con sucursal, usuario y caja/sesión
- rollback coherente ante fallos

#### Definición de terminado
- la venta no deja datos parciales
- no hay inconsistencias entre ventas, líneas, stock y pagos
- el flujo resiste errores sin corrupción lógica

---

### 1.2 Cotizaciones reales
Objetivo: convertir cotizaciones en un módulo serio, no en una aproximación visual o documental.

#### Hay que resolver
- módulo propiamente aislado
- esquema canónico consistente
- RLS correcta
- corrección del flujo `quote -> sale`
- estados formales:
  - borrador
  - enviada
  - aprobada
  - rechazada
  - vencida
  - convertida
- versionado básico
- auditoría básica
- permisos mínimos por acción

#### Definición de terminado
- cotizaciones ya no depende raro de ventas
- puede convertirse en venta de manera limpia
- deja de sentirse placeholder

---

### 1.3 Facturación fiscal mínima viable
Objetivo: pasar de ventas con hints fiscales a una facturación dominicana mínima pero seria.

#### Hay que resolver
- asignación automática de NCF
- validación por tipo de comprobante
- control de secuencia vigente
- bloqueo si no hay secuencia disponible
- snapshot fiscal del cliente
- estados mínimos del documento

#### Tipos mínimos
- consumidor final
- crédito fiscal
- gubernamental
- régimen especial
- exportación

#### Definición de terminado
- se puede emitir con reglas fiscales mínimas reales
- no depende de decisiones manuales peligrosas

---

### 1.4 Impresión operativa
Objetivo: llevar impresión desde foundation a operación real.

#### Hay que resolver
- dispatch real
- historial de impresión
- reimpresión controlada
- plantillas A4 y 80mm bien definidas
- relación con sucursal y destino de impresión

#### Definición de terminado
- imprimir ya es capacidad operativa real
- no solo preparación de datos

---

## 2. Alta prioridad

### 2.1 Caja seria
#### Hay que resolver
- `cash_session_id` obligatorio cuando corresponda
- movimientos más claros
- ingresos, egresos y ajustes
- cierre con validaciones
- relación entre venta, cobro y caja
- arqueo más serio

### 2.2 Permisos finos
#### Hay que resolver
- permisos por acción:
  - vender
  - anular
  - reimprimir
  - emitir fiscal
  - cerrar caja
  - exportar
  - aprobar cotización
  - editar descuentos especiales
- alineación RLS por sucursal y rol

### 2.3 Cleanup técnico
#### Hay que resolver
- partir pantallas grandes
- sacar lógica de widgets
- romper dependencias débiles entre módulos
- consolidar theme/tokens/shared widgets
- eliminar hardcodes de color
- resolver `flutter analyze`
- elevar el piso de testing

---

## 3. Fase 2

### 3.1 e-CF ready
- separar mejor documento comercial y fiscal
- estados compatibles con DGII
- base para envío, aceptación y rechazo

### 3.2 Reportes serios
- ventas por tipo de documento
- consumo NCF
- anulaciones
- cobranzas
- conversión de cotizaciones
- productividad por sucursal y usuario

### 3.3 Dashboard más operativo
- ventas del día
- caja abierta o cerrada
- cotizaciones por vencer
- cobros pendientes
- alertas fiscales

### 3.4 Compras y gastos más profundos
- mejores estados
- mejor trazabilidad
- mejor relación con inventario

---

## 4. No tocar todavía

### 4.1 Microajustes visuales obsesivos
- detalles cosméticos menores
- polish fino sin impacto operativo

### 4.2 Rediseños grandes por gusto
- cambios visuales sin impacto en operación real

### 4.3 Features fancy no críticas
- automatizaciones decorativas
- integraciones secundarias
- extras no esenciales

### 4.4 e-CF completo
Primero cerrar:
- POS
- cotizaciones
- NCF legacy
- impresión real
- caja
- permisos

---

## 5. Orden recomendado

### Sprint 1
- POS transaccional
- normalización crítica
- corrección de inconsistencias base

### Sprint 2
- rehacer cotizaciones bien
- flujo serio
- seguridad correcta
- conversión a venta limpia

### Sprint 3
- NCF legacy mínimo viable
- snapshot fiscal
- reglas de emisión

### Sprint 4
- impresión operativa real
- historial y reimpresión

### Sprint 5
- caja seria
- cierre, arqueo y movimientos

### Sprint 6
- permisos finos
- cleanup técnico
- analyze/test más sanos

---

## 6. Regla de decisión

### Sí hacer ahora si
- quita riesgo
- cierra flujo real
- evita corrupción o inconsistencia
- acerca a operación seria
- desbloquea otros módulos

### No hacer ahora si
- solo se ve más bonito
- no cambia operación real
- aumenta deuda
- tapa un hueco estructural con UI

---

## 7. Resumen ejecutivo

La prioridad actual de `flutter_shop+` no debe ser embellecer más el sistema.

La prioridad debe ser:
- hacerlo más real
- más seguro
- más transaccional
- más fiscal
- más operable
- más mantenible

Ese es el camino para convertirlo en un sistema comercial serio.