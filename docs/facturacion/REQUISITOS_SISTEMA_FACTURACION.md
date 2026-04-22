# Requisitos del sistema de facturación y comprobantes — Shop+ RD

## 1. Propósito del documento

Este documento define **las necesidades y requisitos funcionales/operativos** para un sistema de facturación serio dentro de `flutter_shop+`, orientado a operación real en República Dominicana.

El objetivo es dejar claro **qué debe soportar el producto** en materia de:

- ventas con comprobante
- recibos y facturas
- NCF/comprobantes legacy
- preparación para e-factura / e-CF
- roles y permisos
- comportamiento por sucursal
- impresión A4 y 80mm
- datos de cliente
- flujo de estados
- reportes y auditoría
- validaciones críticas
- futuras integraciones

> Este documento **no define UI**, pantallas detalladas ni SQL final. Es una especificación práctica de necesidades del negocio.

---

## 2. Alcance

El módulo de facturación debe cubrir al menos los siguientes escenarios:

1. **Venta rápida / mostrador**
2. **Venta POS normal con cierre inmediato**
3. **Venta a crédito**
4. **Emisión de recibos no fiscales**
5. **Emisión de comprobantes fiscales NCF tradicionales**
6. **Preparación estructural para e-CF / facturación electrónica**
7. **Reimpresión, anulación y trazabilidad**
8. **Operación multi-sucursal con control por usuario y caja**

No es objetivo de este documento cubrir:

- diseño visual del POS
- detalle de widgets o componentes Flutter
- integración fiscal certificada inmediata con DGII
- contabilidad completa externa

---

## 3. Principios de negocio

El sistema debe diseñarse bajo estos principios:

### 3.1 La venta y el documento fiscal no son exactamente lo mismo
Una venta puede nacer como operación comercial y luego convertirse en:

- recibo simple
- factura con NCF legacy
- documento preparado para e-CF
- documento anulado o ajustado posteriormente

Por tanto, el sistema debe separar claramente:

- **transacción comercial**
- **cobro/pago**
- **documento fiscal**
- **impresión**
- **envío o validación externa futura**

### 3.2 La numeración fiscal debe ser controlada y auditable
La asignación de NCF o secuencias equivalentes:

- no puede duplicarse
- no debe perder trazabilidad
- debe registrar usuario, sucursal, fecha, tipo de comprobante y motivo de cualquier anulación o corrección

### 3.3 Debe operar por sucursal
Cada sucursal puede tener diferencias en:

- secuencias disponibles
- impresoras
- cajas
- usuarios autorizados
- configuración fiscal operativa
- serie o punto de emisión

### 3.4 Debe soportar operación real, no demo
El sistema debe contemplar casos de operación diaria:

- cambio de cliente antes de facturar
- reimpresión por pérdida del ticket
- venta a consumidor final vs empresa con RNC
- agotamiento o vencimiento de secuencia
- devoluciones / anulaciones posteriores
- cierres de caja y conciliación

---

## 4. Entidades de negocio que el módulo debe contemplar

Sin imponer esquema final, el sistema debe ser capaz de manejar estas entidades conceptuales:

- venta
- ítems de venta
- pagos
- cliente
- sucursal
- usuario
- caja / sesión de caja
- tipo de comprobante
- secuencia fiscal
- documento fiscal emitido
- estado fiscal del documento
- historial de eventos/auditoría
- trabajo de impresión / reimpresión
- configuración fiscal del emisor
- configuración de impresoras por sucursal / caja

---

## 5. Tipos de documentos que el producto debe soportar

## 5.1 Documentos comerciales mínimos
El sistema debe poder distinguir al menos:

- **cotización** (si entra al flujo comercial, pero sin valor fiscal)
- **pedido/venta en borrador**
- **recibo o ticket no fiscal**
- **factura / documento fiscal**
- **comprobante de venta a crédito**
- **anulación o reverso operativo**
- **nota de crédito futura**
- **nota de débito futura**

## 5.2 Tipos fiscales legacy esperados
Para República Dominicana, el sistema debe quedar listo para soportar, como mínimo, comprobantes tipo:

- consumidor final
- crédito fiscal
- gubernamental
- regímenes especiales
- exportación

Y debe contemplar en histórico o expansión futura:

- nota de crédito
- nota de débito
- compras / gastos menores / otros tipos especiales, si el producto los incorpora luego

## 5.3 Diferencia entre documento interno y documento fiscal
Todo documento fiscal emitido debe poder relacionarse con:

- la venta que lo originó
- el cliente usado al momento de emisión
- los pagos aplicados
- la sucursal que lo emitió
- el usuario/cajero responsable
- la caja o sesión de caja asociada

---

## 6. Requisitos del flujo de facturación

## 6.1 Flujo base de una venta facturable
El sistema debe soportar el flujo:

1. crear venta
2. agregar productos/servicios
3. calcular importes
4. seleccionar o registrar cliente
5. elegir tipo de documento
6. validar reglas fiscales/comerciales
7. confirmar cobro o condición de crédito
8. asignar comprobante si aplica
9. generar representación imprimible
10. dejar registro auditable

## 6.2 Venta sin cliente formal
Debe permitirse vender a consumidor final con datos mínimos cuando el tipo de comprobante lo permita.

## 6.3 Venta con cliente identificado
Cuando el documento requiera identificación fiscal o comercial, debe poder capturarse y validarse:

- nombre o razón social
- RNC / cédula
- teléfono
- correo
- dirección
- tipo de entidad

## 6.4 Venta a crédito
El sistema debe poder emitir ventas a crédito dejando claro:

- monto original
- balance pendiente
- vencimiento
- condición del crédito
- abonos posteriores
- documento asociado

## 6.5 Edición antes de emitir
Mientras la venta esté en borrador o pendiente de cierre, debe poder editarse.

## 6.6 Bloqueo después de emitir
Una vez emitido un comprobante fiscal, el sistema **no debe permitir edición destructiva directa** del documento final. Cualquier corrección debe quedar por flujo controlado:

- anulación operativa autorizada
- nota de crédito futura
- nueva emisión correcta
- evento auditado

---

## 7. Requisitos sobre cliente y datos fiscales

## 7.1 Maestro de clientes
Debe existir un registro de clientes suficientemente serio para soportar:

- consumidor ocasional
- cliente frecuente
- empresa con RNC
- entidad gubernamental
- cliente con crédito

## 7.2 Datos mínimos por cliente
El sistema debe contemplar como campos de cliente:

- código interno
- nombre / razón social
- tipo de entidad
- RNC o cédula
- teléfono
- correo
- dirección
- límite de crédito
- balance actual
- estado activo/inactivo
- observaciones

## 7.3 Validación documental
Debe validarse, al menos a nivel de formato y obligatoriedad:

- que RNC/cédula no esté vacío cuando el tipo de comprobante lo exige
- que no se permitan duplicados conflictivos por sucursal/compañía según definición final
- que el nombre fiscal exista cuando se emita factura fiscal empresarial

## 7.4 Snapshot fiscal del cliente
Al emitir un documento, el sistema debe guardar una **copia de los datos fiscales usados en ese momento**, sin depender solo del maestro de clientes. Esto evita que una edición posterior del cliente altere documentos históricos.

---

## 8. Requisitos sobre NCF / comprobantes legacy

## 8.1 Configuración de secuencias
El sistema debe permitir administrar secuencias por:

- sucursal
- tipo de comprobante
- serie/prefijo
- rango autorizado
- vigencia
- estado activa/inactiva

## 8.2 Control de consumo
Cada secuencia debe controlar:

- número inicial
- número final
- siguiente número
- cantidad restante
- vencimiento
- última emisión
- alertas por agotamiento o vencimiento

## 8.3 Asignación segura
La asignación del comprobante debe ser:

- única
- atómica
- auditable
- resistente a concurrencia entre varios usuarios/cajas

## 8.4 Tipos legacy/históricos
El sistema debe poder:

- consultar comprobantes históricos legacy
- diferenciar documentos emitidos en formato tradicional vs futuros electrónicos
- mantener trazabilidad de ambos mundos sin mezclar reglas

## 8.5 Reglas mínimas del NCF
El sistema debe impedir:

- emitir con secuencia inactiva
- emitir con secuencia vencida
- emitir si el rango ya se agotó
- reutilizar un número ya emitido
- cambiar manualmente un NCF ya asignado sin flujo autorizado

---

## 9. Preparación para e-factura / e-CF

## 9.1 Objetivo
Aunque la integración certificada no esté lista aún, la arquitectura del producto debe quedar preparada para e-CF.

## 9.2 Separación requerida
La venta no debe depender rígidamente del proveedor o del canal de facturación electrónica. Debe existir desacople entre:

- venta
- documento fiscal local
- payload electrónico
- envío
- respuesta/acuse
- eventos de reintento

## 9.3 Estados necesarios para documento electrónico
El sistema debe poder representar estados como:

- borrador
- generado
- pendiente de envío
- en cola
- enviado
- aceptado
- rechazado
- cancelado/anulado

## 9.4 Evidencia y trazabilidad
Debe ser posible guardar o referenciar:

- payload generado
- respuesta del proveedor / DGII
- identificadores externos
- errores de validación
- timestamps de envío y respuesta
- historial de intentos

## 9.5 Convivencia legacy + e-factura
El producto debe soportar una transición gradual, donde una empresa pueda operar por un tiempo con:

- algunos documentos legacy
- algunos flujos preparados para e-factura
- configuración preferente por negocio/sucursal

---

## 10. Roles, permisos y autorizaciones

## 10.1 Requisito general
No basta con roles globales simples. El módulo debe poder restringir acciones críticas por permiso.

## 10.2 Roles base esperados
Como mínimo deben existir perfiles equivalentes a:

- administrador
- supervisor
- cajero
- contabilidad

Y debe contemplarse crecimiento futuro a permisos más finos.

## 10.3 Acciones críticas que requieren permiso explícito
El sistema debe poder controlar, como mínimo:

- ver ventas
- crear venta
- editar venta en borrador
- cobrar
- emitir comprobante fiscal
- reimprimir ticket
- reimprimir factura
- anular venta
- anular comprobante
- cambiar cliente antes de facturar
- vender a crédito
- aprobar descuentos
- gestionar secuencias NCF
- cambiar configuración fiscal
- ver reportes fiscales
- exportar reportes
- cerrar caja

## 10.4 Autorización reforzada
Para acciones sensibles, debe existir capacidad de requerir:

- motivo obligatorio
- PIN o credencial de supervisor
- registro de quién autorizó
- fecha/hora exacta

Aplica especialmente a:

- anulación
- reimpresión fiscal
- reapertura
- cambio manual excepcional de condición fiscal
- emisión con secuencia de contingencia

---

## 11. Requisitos multi-sucursal

## 11.1 Contexto por sucursal
Toda operación de facturación debe quedar asociada a una sucursal activa.

## 11.2 Aislamiento operativo
Una sucursal no debe mezclar inadvertidamente:

- ventas de otra sucursal
- secuencias de otra sucursal
- caja de otra sucursal
- impresoras de otra sucursal
- usuarios sin acceso

## 11.3 Configuración por sucursal
Cada sucursal debe poder tener configuración propia para:

- nombre comercial visible
- dirección y teléfono impresos
- caja por defecto
- impresora de recibos
- impresora A4
- secuencias fiscales activas
- comportamiento por tipo de documento

## 11.4 Reportería consolidada y por sucursal
El sistema debe permitir:

- consultar por sucursal
- consolidar múltiples sucursales a nivel gerencial
- mantener trazabilidad de origen de cada documento

---

## 12. Requisitos de caja, pagos y relación con facturación

## 12.1 Relación con caja
Toda venta cobrada debe poder asociarse a:

- caja o punto de cobro
- sesión de caja
- usuario que cobró
- método(s) de pago usados

## 12.2 Métodos de pago
Debe soportarse como mínimo:

- efectivo
- tarjeta
- transferencia
- pago móvil
- mixto
- crédito

## 12.3 Pago mixto
El sistema debe soportar una misma venta con múltiples métodos de pago, manteniendo:

- desglose por método
- referencias externas cuando aplique
- monto por método
- cambio entregado si hubo efectivo

## 12.4 Facturación y crédito
Cuando la venta sea a crédito, debe poder emitirse el documento correspondiente sin exigir pago total inmediato, pero dejando el saldo correctamente registrado.

---

## 13. Requisitos de impresión

## 13.1 Formatos obligatorios
El sistema debe estar listo para imprimir al menos en:

- **80mm térmico**
- **A4 / carta**

## 13.2 Casos de impresión térmica 80mm
Debe soportar impresión de:

- ticket de venta
- recibo de pago
- factura simplificada cuando aplique
- reimpresión de ticket

## 13.3 Casos de impresión A4
Debe soportar impresión de:

- factura formal
- documento fiscal con mayor detalle
- copia administrativa
- documento listo para archivo o envío PDF

## 13.4 Contenido mínimo impreso
Toda representación impresa relevante debe poder incluir, según el caso:

- nombre del negocio
- sucursal
- dirección y contacto
- RNC del emisor
- número de documento
- tipo de comprobante
- fecha y hora
- cajero/usuario
- cliente
- RNC/cédula del cliente si aplica
- detalle de ítems
- subtotales
- descuentos
- impuestos
- total
- método(s) de pago
- balance pendiente si es crédito
- NCF o identificador fiscal
- estado del documento
- referencia de anulación o reimpresión, si aplica

## 13.5 Reimpresiones
Toda reimpresión debe:

- quedar registrada
- indicar si es copia o reimpresión
- conservar referencia al documento original
- requerir permiso según política del negocio

## 13.6 Enrutamiento de impresión
La solución debe quedar preparada para definir impresora por:

- sucursal
- caja
- tipo de documento
- formato (A4/80mm)

---

## 14. Flujo de estados del documento

## 14.1 Estados mínimos del ciclo comercial/fiscal
El sistema debe poder representar al menos:

- borrador
- pendiente de cobro
- cobrada
- emitida
- pendiente fiscal
- enviada
- aceptada
- rechazada
- anulada

> No todos los estados tienen que mostrarse al usuario final igual, pero sí deben existir conceptualmente para control interno.

## 14.2 Reglas del ciclo de vida

### Borrador
- editable
- sin numeración fiscal final

### Cobrada / completada
- venta cerrada comercialmente
- lista para documento si aplica

### Emitida
- documento ya generado
- no editable de forma libre

### Enviada / aceptada / rechazada
- estados reservados para readiness de e-factura

### Anulada
- documento preservado históricamente
- jamás eliminado como si nunca existió
- debe guardar motivo, usuario y referencia

---

## 15. Anulaciones, devoluciones y correcciones

## 15.1 Anulación operativa
Debe existir un flujo controlado para anular una venta/documento antes o después del cobro, según reglas del negocio.

## 15.2 Registro obligatorio
Toda anulación debe registrar:

- motivo
- usuario ejecutor
- autorizador si aplica
- fecha/hora
- documento afectado
- impacto económico

## 15.3 Corrección posterior
Para documentos fiscales ya emitidos, el sistema debe quedar listo para soportar en futuro:

- nota de crédito
- nota de débito
- reverso parcial o total
- referencia al documento original

## 15.4 No borrado destructivo
No debe existir eliminación silenciosa de documentos emitidos.

---

## 16. Reportes requeridos

## 16.1 Reportes operativos mínimos
El módulo debe poder producir al menos:

- ventas del día
- ventas por rango de fecha
- ventas por sucursal
- ventas por usuario/cajero
- ventas por método de pago
- ventas a crédito
- balances pendientes por cliente
- reimpresiones realizadas
- anulaciones realizadas

## 16.2 Reportes fiscales mínimos
Debe existir base para reportes como:

- consumo de secuencias NCF
- documentos emitidos por tipo
- documentos anulados
- documentos pendientes/rechazados en flujo electrónico futuro
- resumen fiscal por período

## 16.3 Exportación
Los reportes relevantes deben poder exportarse o prepararse para exportación a:

- PDF
- Excel/CSV
- formatos requeridos por procesos contables o fiscales futuros

## 16.4 Auditoría
Debe existir consulta trazable de eventos tales como:

- emisión
- reimpresión
- anulación
- cambio de cliente
- reapertura
- agotamiento de secuencia
- errores fiscales

---

## 17. Validaciones críticas

## 17.1 Validaciones de emisión
Antes de emitir un documento, el sistema debe validar al menos:

- que la venta tenga ítems válidos
- que el total no sea negativo
- que exista sucursal activa
- que exista usuario autorizado
- que el tipo de comprobante sea compatible con los datos del cliente
- que la secuencia esté disponible y vigente
- que la configuración fiscal mínima del emisor exista

## 17.2 Validaciones del cliente
Según el tipo de documento, validar:

- nombre requerido
- RNC/cédula requerido
- formato básico del documento
- dirección cuando sea necesaria por política o tipo de documento

## 17.3 Validaciones de pagos
El sistema debe impedir incoherencias como:

- cobros mayores/menores sin regla válida
- pagos mixtos que no cierran con el total
- ventas a crédito marcadas como completamente pagadas por error

## 17.4 Validaciones de integridad histórica
Una vez emitido el documento, deben protegerse:

- numeración
- montos históricos
- snapshot del cliente
- usuario emisor
- sucursal emisora

---

## 18. Requisitos de auditoría y trazabilidad

## 18.1 Eventos que deben quedar registrados
Como mínimo:

- creación de venta
- edición relevante
- emisión de comprobante
- asignación de NCF
- impresión
- reimpresión
- anulación
- cambios de estado
- errores de validación
- intentos de integración externa

## 18.2 Datos mínimos del evento
Cada evento debe conservar:

- fecha/hora
- usuario
- sucursal
- referencia del documento/venta
- acción
- detalle resumido
- motivo cuando aplique

## 18.3 Consulta para supervisión
Debe poder revisarse el historial de un documento sin depender de logs técnicos externos.

---

## 19. Requisitos no funcionales relevantes

## 19.1 Concurrencia
El sistema debe soportar varios usuarios/cajas trabajando al mismo tiempo sin duplicar numeraciones ni corromper estados.

## 19.2 Rendimiento
La emisión, cierre y reimpresión deben sentirse operativamente rápidas en POS.

## 19.3 Tolerancia a crecimiento
La estructura debe permitir crecer de:

- roles simples a permisos finos
- NCF legacy a e-CF
- una sucursal a varias
- impresión local simple a ruteo más avanzado

## 19.4 Trazabilidad primero
Ante cualquier duda entre “más simple” y “más auditable”, debe priorizarse la opción auditable.

---

## 20. Integraciones futuras que el diseño debe permitir

El sistema debe quedar listo para integrarse más adelante con:

- proveedor de e-factura / e-CF
- DGII o capa intermediaria autorizada
- envío de PDF por correo o WhatsApp
- sistemas contables
- módulos de cuentas por cobrar
- reportes fiscales formales
- impresión distribuida por agente local o cola de impresión

Para eso, el diseño debe evitar dependencias rígidas entre una venta y un proveedor externo único.

---

## 21. Checklist funcional mínimo de aceptación

Se puede considerar que el módulo cubre lo esencial cuando permita:

- crear una venta y cerrarla correctamente
- elegir tipo de comprobante
- capturar cliente con datos fiscales cuando aplique
- emitir ticket/recibo/factura según reglas
- asignar NCF de forma segura
- operar por sucursal con aislamiento
- restringir emisión/anulación/reimpresión por permisos
- imprimir en 80mm y A4
- registrar reimpresiones y anulaciones
- consultar consumo de secuencias
- dejar la arquitectura lista para e-factura
- producir reportes operativos y fiscales básicos

---

## 22. Decisiones de producto que aún deben cerrarse

Antes de implementar en serio este módulo, conviene definir explícitamente:

1. qué tipos de comprobantes serán prioridad en fase 1
2. si la emisión fiscal ocurre al cobrar o en un paso separado
3. si todas las sucursales tendrán secuencias propias o compartidas
4. si la venta a crédito emite documento al instante o al aprobarse
5. qué acciones requerirán autorización de supervisor
6. cuáles documentos serán obligatorios en A4 y cuáles en 80mm
7. cómo se manejará la transición legacy → e-factura
8. si habrá una sola empresa emisora o crecimiento futuro a multi-company

---

## 23. Resumen ejecutivo

`flutter_shop+` necesita un módulo de facturación que no sea solo “imprimir un ticket”, sino una base seria para operación comercial y fiscal.

Eso implica que el sistema debe contemplar simultáneamente:

- venta
- cobro
- cliente
- secuencia fiscal
- documento emitido
- impresión
- permisos
- sucursal
- auditoría
- preparación para e-CF

Si estas piezas se modelan separadas pero conectadas, el producto podrá crecer sin romper operación real cuando entre en una fase más estricta de cumplimiento fiscal y facturación electrónica.
