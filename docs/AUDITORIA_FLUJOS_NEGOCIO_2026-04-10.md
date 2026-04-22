# Auditoría de flujos de negocio — `flutter_shop+`

Fecha: 2026-04-10  
Enfoque: POS, facturación, cotizaciones, caja/cobros, inventario, sucursales, usuarios/permisos y reportes  
Referencia revisada primero: `CLAUDE.md`, `DATABASE.md`, `flutter_shop.md`  
Referencia comparativa usada donde aporta: ideas de arquitectura y madurez vistas en `mangospos`, sobre todo para caja/impresión.

---

## 1) Resumen ejecutivo

`flutter_shop+` **ya tiene una base operativa real** para un MVP comercial con:

- ventas POS básicas
- compras
- inventario por sucursal
- clientes y suplidores
- cobros sobre ventas a crédito
- caja base por sesión
- secuencias NCF configurables
- reportes simples por sucursal
- multi-sucursal con RLS en Supabase

Pero **todavía no está listo como sistema comercial serio para República Dominicana** si el estándar esperado es:

- facturación fiscal confiable
- trazabilidad documental completa
- cotizaciones convertibles de verdad
- impresión productiva
- arqueo/caja robusto
- permisos finos
- controles operativos para errores de cajero/negocio
- preparación fiscal/electrónica realmente defendible

Mi conclusión directa:

- **Lo comercial básico existe.**
- **Lo fiscal existe más como estructura/promesa que como flujo real.**
- **Cotizaciones está a medio camino y hoy puede ser engañoso presentarlo como módulo terminado.**
- **Impresión está en fundación técnica, no en operación.**
- **Caja y cobros funcionan en lo mínimo, pero no con el rigor que exige una operación seria de varias cajas/sucursales.**

---

## 2) Qué flujos son reales hoy

## 2.1 POS / ventas

### Sí es real hoy

- catálogo de productos por sucursal
- búsqueda por nombre / SKU / barcode
- carrito básico
- venta de contado
- venta a crédito
- cálculo de subtotal + ITBIS desde `tax_rate`
- creación de `sales`
- creación de `sale_items`
- creación de `payments` en ventas de contado
- actualización de balance del cliente cuando la venta es a crédito
- descuento automático de stock por trigger al insertar `sale_items`

### Evidencia

- `lib/features/sales/data/sales_repository.dart`
- `supabase/sql/01_schema.sql`

### Juicio

Esto sí es un flujo funcional de MVP.  
No es demo vacía. Sí registra transacciones reales.

---

## 2.2 Cobros / cuentas por cobrar

### Sí es real hoy

- lista de ventas con balance pendiente
- registro de abonos
- actualización de `paid_amount`, `balance_due` y `status`
- recálculo del balance agregado del cliente
- consulta de pagos recientes

### Evidencia

- `lib/features/cobros/data/cobros_repository.dart`
- vista `accounts_receivable_summary`

### Juicio

También es flujo real, pero básico. Sirve para registrar abonos, no para una cartera seria con reglas de crédito y vencimientos.

---

## 2.3 Inventario

### Sí es real hoy

- categorías y productos por sucursal
- costo, precio, ITBIS, stock mínimo y stock actual
- creación/edición de productos
- compras que aumentan stock vía trigger
- ventas que descuentan stock vía trigger
- reporte de bajo stock

### Evidencia

- `lib/features/inventory/data/inventory_repository.dart`
- `lib/features/purchases/data/purchases_repository.dart`
- triggers en `supabase/sql/01_schema.sql`

### Juicio

Inventario sí existe como operación real, pero todavía muy enfocado en existencia simple, no en control robusto de movimientos.

---

## 2.4 Compras

### Sí es real hoy

- registro de compras
- líneas de compra
- impuestos en compra
- actualización de costo del producto
- incremento de stock por trigger

### Juicio

Real y útil para un MVP. Aún lejos de compras más serias con recepción parcial, cuentas por pagar, costos promedio y trazabilidad documental fuerte.

---

## 2.5 Sucursales y usuarios

### Sí es real hoy

- perfiles de usuario
- asignación usuario ↔ sucursal
- sucursal por defecto / cambio de sucursal actual
- creación/edición de sucursales
- asignación de usuarios a sucursales
- roles globales simples
- RLS por sucursal en Supabase

### Evidencia

- `users_branches`
- `current_branch_id()`
- `set_current_branch()`
- repositorios de `users` y `branches`

### Juicio

La base multi-sucursal sí es real y bien encaminada. El problema no es la existencia del modelo, sino su **profundidad operativa**.

---

## 2.6 Reportes

### Sí es real hoy

- ventas semanales/mensuales por vistas SQL
- cuentas por cobrar resumidas
- inventario bajo stock
- uso de NCF desde secuencias
- dashboard con últimas ventas y KPIs básicos
- módulo fiscal que arma CSV simples de 606/607

### Juicio

Sí hay reporting real. Pero es **gerencial básico**, no reporting de control comercial/fiscal serio.

---

## 3) Qué está incompleto, engañoso o sólo “medio hecho”

## 3.1 Facturación fiscal: el mayor gap

El repo habla varias veces de:

- NCF
- facturación seria RD
- readiness para DGII / e-CF
- comprobantes fiscales
- fiscal invoice

Pero el flujo real actual **no materializa eso de forma confiable**.

### Problemas concretos

#### a) No hay asignación automática real de NCF al vender

`CLAUDE.md` y `DATABASE.md` ya lo admiten: la asignación automática de NCF no está terminada.

Consecuencia:

- una venta puede quedar con `receipt_type = fiscal_credit`
- pero sin NCF asignado
- sin consumo de secuencia
- sin validación de disponibilidad
- sin control de vencimiento
- sin trazabilidad de emisión fiscal

Eso significa que hoy **“factura fiscal” es más una etiqueta que un documento fiscal real**.

#### b) `dgii_status` existe, pero no está integrado a un flujo tributario real

La tabla `sales` tiene `dgii_status`, pero no existe:

- cola de envío
- integración DGII
- eventos de transmisión
- respuesta certificada
- auditoría de reintentos
- desacople entre documento comercial y documento fiscal electrónico

Hoy ese campo funciona más como placeholder.

#### c) El POS permite incoherencias fiscales

En `sales_page.dart` se puede elegir `fiscal_credit`, pero el flujo no exige de forma consistente:

- cliente formal
- RNC/cédula
- razón social
- validación fiscal del tercero
- secuencia NCF disponible
- configuración fiscal de la sucursal

Peor aún: la restricción de cliente solo se fuerza si la venta es a crédito.  
Una venta de contado con `fiscal_credit` puede terminar tratándose como si bastara un “cliente general”, lo cual para operación dominicana seria es incorrecto.

#### d) No existe snapshot fiscal del cliente al emitir

La venta referencia `client_id`, pero no guarda una copia histórica de:

- nombre fiscal al momento de emisión
- RNC/cédula usada
- dirección fiscal
- tipo de entidad

Eso es un problema serio porque el documento histórico puede quedar dependiendo del maestro actual del cliente.

#### e) No hay flujo formal de anulación / nota de crédito / corrección

Existe `voided` como estado, pero no encontré un flujo operativo serio para:

- anular venta ya emitida
- justificar motivo
- restringir autorización
- revertir o no stock según política
- revertir o no balance cliente
- registrar evidencia de quién lo hizo
- preparar futura nota de crédito

Para un sistema comercial serio, esto es crítico.

### Veredicto sobre facturación

**Facturación fiscal NO está lista.**  
Hay base de datos y lenguaje de producto, pero el flujo real aún no soporta una operación fiscal seria de RD.

---

## 3.2 Cotizaciones: visible, parcialmente persistida, pero no madura

Este módulo es el punto más engañoso entre “se ve real” y “todavía no está cerrado”.

### Lo que sí existe

- ruta `/cotizaciones`
- pantalla propia
- listado desde tabla `quotations`
- creación de cotización
- items de cotización
- intento de convertir cotización en venta
- pipeline visual de estados

### Problemas críticos

#### a) El documento fundacional y el estado real del código ya no coinciden del todo

`docs/quotations/QUOTATIONS_FOUNDATION.md` dice explícitamente que la primera fase **no agregaba tablas ni persistencia**.  
Pero el repo actual sí tiene un repositorio que escribe en `quotations` y `quotation_items`.

Eso vuelve el estado del módulo confuso para cualquiera que revise solo docs.

#### b) Las tablas de cotización no están en el esquema canónico principal

No están en `supabase/sql/01_schema.sql`.  
Están en `supabase/sql-next/20260410_quotations_schema.sql`.

Consecuencia:

- el módulo puede existir en Flutter
- pero quedar roto en ambientes que solo tengan el esquema principal desplegado

Eso lo convierte en un flujo **potencialmente bloqueado por despliegue**.

#### c) La migración propuesta de cotizaciones es débil y riesgosa

`20260410_quotations_schema.sql` tiene problemas para un sistema serio:

- usa `uuid_generate_v4()` sin que este archivo garantice la extensión correspondiente
- relaciones sin el mismo rigor multi-sucursal del esquema principal
- políticas RLS abiertas con `USING (true) WITH CHECK (true)`
- no sigue el patrón de auditoría fuerte del resto del esquema
- status como `TEXT` libre, no enum controlado

Para un módulo comercial serio, esa migración está más cerca de prototipo que de capa productiva.

#### d) El flujo de aprobación está incompleto

La UI solo muestra acción “Convertir a venta” cuando la cotización está `approved`, pero no vi un flujo serio para:

- aprobar
- rechazar
- enviar
- poner en revisión
- expirar
- versionar

O sea: existe pipeline visual, pero no ciclo comercial operativo completo.

#### e) Conversión a venta con bug que puede romper el flujo

En `QuotationsRepository.convertToSale()` se usa:

- `receipt_type: 'consumidor_final'`

Pero el enum real del sistema es:

- `consumer_final`

Eso puede romper la inserción de la venta directamente en DB.  
Este hallazgo es importante porque convierte el flujo quote → sale en **bloqueado o defectuoso**.

#### f) La conversión ignora reglas críticas del negocio

La conversión actual:

- no valida stock antes de convertir
- no crea pago ni define condición comercial clara
- no exige caja abierta
- no actualiza balance del cliente para una venta a crédito
- no prepara impresión útil
- inserta descripción genérica: `Producto de cotización`
- no deja claro si debe ser contado, crédito, proforma o borrador

Eso significa que hoy **convertir una cotización no es todavía un cierre comercial serio**.

### Veredicto sobre cotizaciones

**Cotizaciones existe, pero no está madura.**  
Tiene valor como fundación visible, pero hoy no debería venderse como flujo comercial cerrado.

---

## 3.3 Impresión: muy prometida, poco operativa

### Lo que sí existe

- modelos canónicos de documentos de impresión
- servicios para preparar `PreparedPrintJobData`
- estrategia 80mm / A4
- builders de payload
- adaptadores de venta a documento imprimible
- documentación bastante sensata

### Lo que NO existe operativamente

- ejecución real a impresora
- asignación de impresoras por sucursal/caja
- `print_jobs` persistidos
- historial de impresiones
- reimpresión auditada
- manejo de fallos/reintentos
- PDF operativo visible al usuario
- flujo formal desde POS para imprimir al completar

### Hallazgo importante

En `SalesRepository.checkoutSale()` sí se prepara un `preparedPrintJob`, pero `sales_page.dart` solo muestra un diálogo de venta exitosa.  
No vi que el resultado se despache, imprima o se use para una acción real.

O sea:

- la preparación documental existe
- la operación de impresión no

### Veredicto sobre impresión

**Impresión está en fundación técnica, no en producción.**  
Para un comercio serio dominicano, esto todavía es insuficiente.

---

## 3.4 Caja: funcional en lo mínimo, insuficiente para operación seria

### Lo que sí existe

- apertura de caja
- cierre de caja
- monto de apertura
- monto esperado
- conteo al cierre
- diferencia
- asociación opcional de pagos/gastos a `cash_session_id`
- gastos
- pagos/cobros impactan métricas

### Problemas críticos

#### a) Solo permite una caja abierta por sucursal

La restricción:

- `cash_sessions_open_unique` sobre `branch_id`

impide varios escenarios reales:

- dos cajeros simultáneos en la misma sucursal
- caja 1 y caja 2
- una caja principal y una rápida
- separación por dispositivo o terminal

Para retail serio esto queda corto muy rápido.

#### b) Caja no es obligatoria para registrar operación monetaria

Ventas de contado, cobros y gastos buscan una sesión abierta, pero si no existe, el `cash_session_id` puede quedar `null`.

Eso permite que el sistema siga operando sin disciplina de caja.

En otras palabras:

- el módulo de caja existe
- pero no gobierna realmente la operación

Esto es un gap serio.

#### c) No existe ubicación de efectivo / ledger unificado

El propio documento `docs/cash-architecture-foundation.md` ya reconoce la carencia:

- no hay `cash_locations`
- no hay `cash_movements`
- no hay transferencias entre ubicaciones
- no hay caja chica / bóveda / banco / tránsito

Eso deja la caja en estado muy básico.

#### d) No hay control de retiro, depósito, ajuste o transferencia

No vi flujos serios para:

- retiro parcial de efectivo
- depósito a banco
- transferencia caja → bóveda
- ajuste manual con autorización
- reposición de fondo

#### e) Falta trazabilidad operativa del cajero

No vi amarre serio entre:

- sesión
n- terminal/dispositivo
- ubicación física
- responsable del arqueo
- impresiones del cierre

### Veredicto sobre caja

**Caja sirve para apertura/cierre básico, no para control operativo serio.**

---

## 3.5 Cobros: reales, pero sin gestión de cartera robusta

### Lo que falta

- vencimiento real por factura
- política de crédito por cliente
- bloqueo por límite de crédito
- antigüedad de saldos
- promesas de pago
- recargos/intereses si aplica
- recibo formal de cobro
- aplicación avanzada de pagos mixtos o a múltiples facturas

### Hallazgo importante

`clients.credit_limit` existe, pero no vi una validación real en ventas a crédito.  
Entonces el sistema guarda el límite, pero no gobierna el negocio con él.

### Veredicto

Cobros es funcional, pero todavía no es cartera robusta.

---

## 4) Flujos con riesgo operativo alto

## 4.1 Venta y sus escrituras no son transaccionales

En el POS, la venta se arma en pasos separados:

1. insert `sales`
2. insert `sale_items`
3. insert `payments` si aplica
4. update cliente si es crédito
5. preparar impresión

No vi un RPC o transacción de base que garantice atomicidad total.

Riesgo:

- venta creada sin ítems
- venta creada sin pago
- venta creada con ítems pero falló actualización de cliente
- inconsistencia ante caídas de red o errores parciales

Para un sistema serio, esta es una deuda fuerte.

---

## 4.2 Conversión quote → sale también carece de transacción robusta

Mismo problema, y peor porque además tiene bug del `receipt_type`.

---

## 4.3 Inventario puede quedar débil ante errores de flujo

El ajuste de stock depende de triggers sobre `sale_items` y `purchase_items`, lo cual está bien como base.  
Pero no vi controles más serios para:

- impedir stock negativo desde DB
- reservar stock para cotización/pedido
- trazabilidad por movimiento
- devoluciones
- transferencias entre sucursales
- conteos físicos / ajustes

### Veredicto

Inventario funciona, pero no es todavía un kardex serio.

---

## 5) Usuarios y permisos: base buena, granularidad insuficiente

## Lo que sí existe

- roles globales: `admin`, `supervisor`, `cashier`, `accountant`
- `role_override` por sucursal
- helpers RLS (`can_operate_pos`, `can_manage_branch_data`, etc.)

## Lo que falta para una operación seria

- permisos granulares por acción
- permisos por módulo y subacción
- permisos de anulación
- permisos de reimpresión
- permisos de emitir fiscal
- permisos de exportar 606/607
- permisos de ver costos
- permisos de cambiar NCF/secuencias
- permisos de cierre de caja
- permisos por dispositivo/caja

### Hallazgo

`flutter_shop.md` y `DATABASE.md` ya empujan hacia un modelo más granular, pero el código actual todavía está en roles simples.

### Veredicto

**Hay control base, no control fino.**  
Para negocio serio multiusuario, esto todavía no basta.

---

## 6) Reportes: útiles, pero todavía de supervisión básica

## Lo que sí resuelven

- tendencia de ventas
- cuentas por cobrar resumidas
- bajo stock
- uso de secuencias NCF
- dashboard de últimas ventas

## Lo que falta

- ventas por cajero
- ventas por hora / turno
- utilidad / margen
- desglose por método de pago
- arqueo detallado de caja
- documentos anulados
- reimpresiones
- ventas por tipo de comprobante con consistencia fiscal real
- auditoría de cambios
- aging de cartera
- compras por suplidor
- impuestos listos para formatos regulatorios reales

## Hallazgo fiscal importante

El módulo de impuestos arma CSV “606/607”, pero por lo revisado es un export simplificado, no una implementación robusta alineada a formato oficial/validado DGII.

Eso sirve como base interna, no como cumplimiento serio todavía.

---

## 7) Preparación fiscal dominicana: qué tan lista está realmente

## Lo positivo

- enums de `receipt_type`
- `ncf_sequences`
- `dgii_status`
- vistas/reportes de uso NCF
- documentación del producto bastante clara sobre la dirección deseada

## Lo negativo

Falta casi todo lo que convierte eso en una solución seria de RD:

- asignación segura de NCF
- consumo transaccional de secuencia
- bloqueo por vencimiento/agotamiento
- validación fuerte según tipo de comprobante
- snapshot fiscal del cliente
- anulación fiscal controlada
- reimpresión auditada
- correlación con impresora/ruta/documento
- documentos electrónicos / eventos / firma / proveedor
- separación limpia entre venta, documento fiscal e impresión

### Veredicto

**Está “ready para diseñarse”, no “ready para operar”.**

---

## 8) Principales inconsistencias entre discurso y realidad

Estas son las que más me preocupan porque pueden confundir a negocio o stakeholders:

### 1. “Facturación fiscal”
En realidad hoy hay:
- tipo de comprobante
- secuencias configurables
- campos fiscales

Pero no un flujo fiscal completo y confiable.

### 2. “Cotizaciones”
Sí existe visualmente y con algo de persistencia, pero:
- no está en el esquema canónico
- la migración es floja
- la aprobación no está cerrada
- la conversión tiene bug importante

### 3. “Impresión”
Existe arquitectura y preparación documental, pero no impresión productiva real.

### 4. “Caja”
Existe sesión de caja, pero la operación monetaria todavía puede ocurrir sin disciplina obligatoria de caja.

---

## 9) Qué está bloqueado o casi bloqueado hoy

## Bloqueo 1 — quote → sale

Muy probablemente bloqueado o defectuoso por `receipt_type: 'consumidor_final'` en vez de `consumer_final`.

## Bloqueo 2 — cotizaciones según ambiente

Si el ambiente no ejecutó `supabase/sql-next/20260410_quotations_schema.sql`, la UI de cotizaciones queda montada sobre tablas inexistentes.

## Bloqueo 3 — impresión real

No bloqueado técnicamente a nivel de preparación de datos, pero sí bloqueado como flujo de negocio porque falta dispatch/ejecución/seguimiento.

## Bloqueo 4 — facturación fiscal seria

Bloqueada por ausencia de asignación/consumo fiscal real de NCF y por falta de reglas/documento tributario completo.

---

## 10) Evaluación por módulo

## POS
**Estado:** funcional MVP  
**Nivel:** real pero básico  
**Riesgo:** medio-alto por falta de atomicidad, caja opcional y fiscal débil

## Facturación
**Estado:** parcial / estructural  
**Nivel:** no apto aún para operación fiscal seria RD  
**Riesgo:** muy alto

## Cotizaciones
**Estado:** parcial  
**Nivel:** visible pero incompleto y con bugs/gaps de despliegue  
**Riesgo:** alto

## Caja
**Estado:** básico  
**Nivel:** útil para una sola caja simple  
**Riesgo:** alto para multi-caja real

## Cobros
**Estado:** funcional  
**Nivel:** básico  
**Riesgo:** medio

## Inventario
**Estado:** funcional  
**Nivel:** MVP aceptable  
**Riesgo:** medio por falta de movimientos y controles avanzados

## Sucursales
**Estado:** bueno  
**Nivel:** base real y útil  
**Riesgo:** medio-bajo

## Usuarios/permisos
**Estado:** base correcta  
**Nivel:** insuficiente para operación estricta  
**Riesgo:** medio-alto

## Reportes
**Estado:** útil  
**Nivel:** supervisión básica  
**Riesgo:** medio

---

## 11) Lo más importante a corregir antes de vender esto como sistema serio RD

Ordenado por impacto negocio/operación:

1. **Cerrar de verdad el flujo de facturación fiscal**
   - asignación NCF
   - validaciones por tipo
   - snapshot del cliente
   - trazabilidad de emisión

2. **Endurecer caja para que no sea opcional en flujos monetarios**
   - ventas cash, cobros cash, gastos cash
   - sesión obligatoria
   - evolución hacia location-aware cash

3. **Arreglar y endurecer cotizaciones**
   - migración canónica
   - RLS correcta
   - aprobación real
   - conversión quote → sale sin bugs

4. **Convertir impresión en flujo operativo real**
   - dispatch
   - historial
   - reimpresión auditada
   - A4/80mm utilizables

5. **Transaccionalizar operaciones críticas**
   - venta completa
   - cobro
   - conversión de cotización
   - emisión fiscal

6. **Agregar permisos finos**
   - anular
   - reimprimir
   - emitir fiscal
   - cerrar caja
   - ver costos
   - exportar fiscal

7. **Fortalecer cartera e inventario**
   - límite de crédito real
   - vencimientos
   - movimientos inventario
   - devoluciones / ajustes / transferencias

---

## 12) Conclusión final

Si la pregunta es:

> “¿Shop+ ya tiene flujos reales?”

La respuesta es:

**Sí, varios.** Especialmente POS básico, compras, inventario, cobros, sucursales y reportes simples.

Si la pregunta es:

> “¿Está listo para ser un sistema comercial serio dominicano con facturación, cotizaciones, impresión y caja confiables?”

La respuesta es:

**Todavía no.**

La brecha principal no es visual; es **operativa y documental**:

- facturación fiscal no cerrada
- cotizaciones aún inconsistentes
- impresión no productiva
- caja demasiado básica
- permisos demasiado gruesos
- poca trazabilidad para eventos sensibles

El repo va en una dirección correcta, pero hoy todavía está entre **MVP comercial funcional** y **ERP/POS serio RD en construcción**.
