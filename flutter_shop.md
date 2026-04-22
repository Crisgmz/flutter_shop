# flutter_shop.md

# Requerimientos del sistema de facturación y cotizaciones

Este documento resume las necesidades funcionales del sistema `flutter_shop+` para que sirva como guía de producto y de implementación futura.

El objetivo es definir **qué debe hacer el sistema**, no cómo se verá visualmente ni cómo se modelará técnicamente en detalle.

---

## 1. Objetivo general del sistema

`flutter_shop+` debe convertirse en un sistema comercial y administrativo serio para operación multi-sucursal en República Dominicana, capaz de manejar:

- ventas de contado y crédito
- cobros
- cotizaciones
- facturación con comprobantes fiscales legacy
- preparación para facturación electrónica
- impresión profesional en A4 y 80mm
- control por roles/permisos
- trazabilidad, auditoría y reportes

---

## 2. Requerimientos del sistema de facturación

### 2.1 Tipos de documentos comerciales/fiscales
El sistema debe soportar, como mínimo:

- venta simple / recibo
- factura de consumo
- factura con comprobante fiscal
- cotización
- reimpresión de documento
- documento de crédito / pendiente
- preparación para futuras notas de crédito y anulaciones formales

### 2.2 Comprobantes fiscales legacy (NCF)
El sistema debe manejar correctamente los comprobantes fiscales tradicionales de RD.

Debe soportar:
- consumidor final
- crédito fiscal
- gubernamental
- régimen especial
- exportación

Cada documento fiscal debe poder tener:
- tipo de comprobante
- secuencia asignada
- vigencia
- validaciones de disponibilidad
- control por sucursal
- trazabilidad de emisión

### 2.3 Preparación para e-CF / facturación electrónica
Aunque no se implemente completa desde el inicio, el sistema debe quedar listo para:

- generar documentos electrónicos
- guardar estado del documento electrónico
- registrar eventos de envío/respuesta
- permitir integración con proveedor/firma/certificado futuro
- desacoplar la venta de la transmisión electrónica

Estados previstos para facturación electrónica:
- borrador
- generado
- en cola
- enviado
- aceptado
- rechazado
- cancelado

### 2.4 Datos del cliente para facturación
El sistema debe poder facturar tanto a:
- cliente general
- persona física
- empresa
- entidad gubernamental

Debe manejar, según el caso:
- nombre o razón social
- RNC o cédula
- tipo de cliente
- dirección
- correo
- teléfono
- condiciones de pago
- límite de crédito

Además, al facturar, debe guardarse un **snapshot fiscal/comercial** del cliente para que el documento histórico no cambie si luego se edita el perfil.

### 2.5 Flujo de facturación
El flujo mínimo esperado es:

1. seleccionar cliente o cliente general
2. agregar productos/servicios
3. aplicar precios, descuentos e impuestos
4. elegir tipo de comprobante
5. validar secuencia disponible
6. definir forma de pago
7. emitir venta/factura
8. preparar impresión
9. dejar trazabilidad y auditoría

### 2.6 Estados del documento
Una factura/venta debe poder pasar por estados como:
- borrador
- completada
- crédito
- pendiente
- anulada

Y si se conecta luego con capa fiscal/electrónica, extenderse con estados tributarios sin romper el flujo comercial.

### 2.7 Relación con caja y pagos
La facturación debe estar alineada con caja.

Debe contemplar:
- pagos en efectivo
- tarjeta
- transferencia
- móvil
- crédito
- pagos mixtos

También debe poder integrarse con:
- sesión de caja
- ubicación de caja
- arqueo posterior
- reimpresiones de recibo
- cobros posteriores sobre ventas a crédito

### 2.8 Operación por sucursal
El sistema debe trabajar correctamente por sucursal.

Cada sucursal debe poder tener:
- secuencias fiscales propias si aplica
- configuración operativa propia
- caja/cajas
- impresoras/rutas de impresión
- usuarios asignados
- reportes filtrados por sucursal

### 2.9 Roles y permisos
La facturación no puede estar abierta a cualquiera.

Debe existir control por roles y permisos para acciones como:
- ver facturas
- crear facturas
- anular facturas
- reimprimir
- emitir comprobantes fiscales
- ver reportes fiscales
- gestionar secuencias NCF
- exportar información

Roles típicos esperados:
- admin
- supervisor
- cashier
- accountant

### 2.10 Impresión
El sistema de facturación debe soportar:
- formato **80mm** para ticket/recibo
- formato **A4** para factura/proforma/documento formal

Debe poder imprimir:
- encabezado de negocio/sucursal
- cliente
- líneas de productos/servicios
- subtotales
- descuentos
- impuestos
- total
- forma de pago
- cajero/usuario
- número de documento
- NCF cuando aplique

También debe contemplar:
- reimpresión
- selección de plantilla
- selección futura de impresora/ruta
- PDF/exportación cuando haga falta

### 2.11 Auditoría
Toda facturación seria debe dejar rastro.

Debe auditarse:
- quién creó el documento
- quién lo editó
- quién lo anuló
- cuándo se imprimió o reimprimió
- cambios importantes en estado
- emisión fiscal/electrónica

### 2.12 Reportes mínimos de facturación
El sistema debe poder producir reportes como:
- ventas del día
- ventas por rango de fecha
- ventas por sucursal
- ventas por usuario/cajero
- ventas a crédito
- cuentas por cobrar
- consumo de NCF
- documentos anulados
- total por tipo de comprobante
- base para reportes fiscales futuros

---

## 3. Requerimientos del sistema de cotizaciones

### 3.1 Propósito del módulo
Cotizaciones no debe ser una pantalla decorativa.

Debe servir para:
- preparar propuestas comerciales
- negociar con clientes
- guardar oportunidades de venta
- convertir cotizaciones aprobadas en ventas
- imprimir o enviar cotizaciones
- dar seguimiento comercial

### 3.2 Estados del ciclo de vida
Una cotización debe poder manejar estados como:
- borrador
- enviada
- en revisión
- aprobada
- rechazada/perdida
- expirada
- convertida a venta

### 3.3 Datos del cliente/prospecto
La cotización debe poder crearse para:
- cliente existente
- prospecto nuevo
- cliente empresa
- cliente general/provisional si hace falta

Debe guardar:
- nombre del cliente o prospecto
- contacto
- teléfono
- correo
- documento/RNC si aplica
- observaciones comerciales
- canal de entrada
- vendedor responsable

### 3.4 Encabezado de la cotización
La cotización debe tener como mínimo:
- número/código de cotización
- sucursal
- fecha de creación
- fecha de vigencia
- estado
- cliente
- vendedor/owner
- canal
- prioridad
- notas u observaciones

### 3.5 Líneas de cotización
Debe soportar líneas con:
- producto o servicio
- descripción manual cuando no sea un producto del catálogo
- cantidad
- precio unitario
- descuento
- impuesto
- subtotal y total de línea
- orden lógico de líneas

### 3.6 Pricing, descuentos e impuestos
La cotización debe respetar reglas reales del negocio:
- precio base
- descuentos por línea o generales
- impuestos
- total final
- visibilidad clara del cálculo

Y debe quedar lista para que más adelante se apliquen:
- listas de precios
- condiciones especiales
- validaciones de margen
- aprobación por descuento extraordinario

### 3.7 Vigencia
Cada cotización debe tener vigencia explícita.

Debe permitir:
- fecha de vencimiento
- alerta de vencimiento
- marcar como expirada
- renovar o duplicar si se necesita

### 3.8 Aprobación interna
Si el negocio lo necesita, algunas cotizaciones deben poder requerir aprobación antes de enviarse o antes de convertirse en venta.

Casos típicos:
- descuentos altos
- montos elevados
- clientes nuevos con condiciones especiales
- precios por debajo de margen esperado

### 3.9 Versionado
Una cotización seria necesita historial.

Debe contemplar:
- versiones
- cambios de precio
- cambios en líneas
- cambios de estado
- trazabilidad de quién modificó qué

### 3.10 Conversión a venta
Una cotización aprobada debe poder convertirse en venta con el menor retrabajo posible.

La conversión debe heredar, según aplique:
- cliente
- líneas
- precios
- descuentos
- impuestos
- notas relevantes

Y debe evitar duplicidad o inconsistencias.

### 3.11 Impresión y exportación
Las cotizaciones deben poder:
- imprimirse en A4
- exportarse a PDF
- reenviarse
- reimprimirse
- tener una presentación formal y profesional

Idealmente el sistema debe compartir parte de la infraestructura de impresión con el módulo de facturación.

### 3.12 Seguimiento comercial
El módulo de cotizaciones debe servir para trabajo comercial real.

Debe permitir a futuro:
- ver cotizaciones por vencer
- ver cotizaciones aprobadas pendientes de convertir
- ver cotizaciones perdidas
- ver owner comercial
- dar seguimiento por canal
- medir monto en pipeline

### 3.13 Permisos
El módulo debe tener permisos finos para:
- ver cotizaciones
- crear
- editar
- enviar
- aprobar
- rechazar
- convertir en venta
- imprimir/exportar
- ver reportes comerciales

### 3.14 Reportes mínimos de cotizaciones
Debe poder reportarse:
- cotizaciones creadas por período
- monto total cotizado
- monto aprobado
- monto perdido
- tasa de conversión a venta
- cotizaciones por vendedor
- cotizaciones por sucursal
- cotizaciones por estado
- cotizaciones vencidas

---

## 4. Relación entre facturación y cotizaciones

Estos dos módulos no deben vivir separados conceptualmente.

Relaciones clave:
- una cotización puede convertirse en una venta/factura
- una cotización puede imprimirse como proforma
- una venta puede tener origen en una cotización
- una factura puede necesitar snapshot de información comercial previa
- ambos deben compartir parte de:
  - clientes
  - catálogo
  - impuestos
  - impresión
  - auditoría
  - permisos

---

## 5. Integraciones y futuro

El sistema debe quedar listo para crecer hacia:
- facturación electrónica
- impresión distribuida/local agent
- múltiples impresoras por sucursal
- workflow de aprobación comercial
- workflow de aprobación fiscal
- conversión cotización → venta → cobro → documento fiscal
- exportes contables/fiscales

---

## 6. Decisiones de producto que aún conviene cerrar

Antes de implementación completa, conviene definir:

1. qué tipos de comprobantes van primero
2. si la cotización puede tener líneas manuales además de catálogo
3. si habrá aprobaciones internas por monto/descuento
4. cómo será la conversión de cotización a venta
5. qué se imprimirá en A4 y qué en 80mm
6. qué roles pueden anular/reimprimir/emitir
7. si una sucursal maneja secuencias propias o compartidas
8. qué tanto se separa venta comercial de emisión fiscal

---

## 7. Conclusión

`flutter_shop+` no necesita solo pantallas nuevas.
Necesita una estructura seria para:
- vender
- cotizar
- facturar
- imprimir
- cobrar
- auditar
- crecer hacia fiscal/electrónico

Este documento sirve como base funcional para construir correctamente esos módulos dentro del sistema.
