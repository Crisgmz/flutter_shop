# Requerimientos funcionales — Módulo de Cotizaciones

## 1. Propósito

Definir los requerimientos de un módulo de **cotizaciones / proformas** serio dentro de `flutter_shop+`, alineado con un sistema de ventas, facturación e impresión multi-sucursal.

Este documento cubre **solamente necesidades funcionales y operativas** del módulo de cotizaciones. No define pantallas ni detalles visuales.

---

## 2. Objetivo del módulo

El módulo debe permitir que el negocio:

- prepare propuestas comerciales formales para clientes
- gestione cotizaciones con ciclo de vida completo
- controle vigencia, precios, impuestos y condiciones comerciales
- lleve seguimiento comercial hasta ganar o perder la oportunidad
- convierta una cotización aprobada en una venta real sin reescribir información
- imprima, exporte y comparta documentos comerciales consistentes
- mantenga trazabilidad, permisos y reportes

La cotización debe funcionar como un **documento comercial previo a la venta**, no como una venta maquillada ni como un simple borrador informal.

---

## 3. Alcance funcional

El módulo debe cubrir como mínimo:

1. creación y edición de cotizaciones
2. manejo de clientes y prospectos
3. líneas de productos/servicios
4. cálculo de precios, descuentos, impuestos y totales
5. vigencia comercial
6. aprobación interna y/o del cliente
7. versionado y trazabilidad de cambios
8. conversión a venta
9. impresión / PDF / exportación / reenvío
10. seguimiento comercial
11. permisos por rol
12. reportes comerciales y operativos

---

## 4. Principios de negocio

1. **Una cotización no descuenta inventario.**
   - Puede consultar stock disponible o referencial.
   - No debe comprometer stock real automáticamente salvo que en el futuro exista una reserva explícita.

2. **Una cotización no es un comprobante fiscal.**
   - No genera NCF.
   - No entra al flujo fiscal definitivo hasta convertirse en venta/factura.

3. **La cotización debe ser auditable.**
   - Debe saberse quién la creó, quién la modificó, quién la aprobó, cuándo se envió y cuándo se convirtió en venta.

4. **La conversión a venta debe evitar doble digitación.**
   - Cliente, líneas, notas, precios y condiciones aprobadas deben reutilizarse.

5. **Debe existir control comercial real.**
   - Vigencia, seguimiento, pérdida, aprobación y versiones no pueden quedar como texto libre sin estructura.

---

## 5. Actores que interactúan con el módulo

### 5.1 Roles operativos mínimos
- vendedor / ejecutivo comercial
- supervisor comercial
- caja / facturación
- gerente / administrador
- auditor / consulta

### 5.2 Casos de uso por actor

**Vendedor**
- crear cotización
- editar borradores propios
- enviarla al cliente
- registrar seguimiento
- solicitar aprobación excepcional

**Supervisor / gerente**
- aprobar descuentos fuera de política
- aprobar cotizaciones de alto monto
- reabrir o anular según permisos
- consultar pipeline y productividad

**Caja / facturación**
- convertir cotización aprobada en venta
- imprimir proforma o documento comercial
- validar datos fiscales/comerciales antes de facturar

**Administrador**
- configurar numeración, permisos, plantillas y políticas
- acceder a todos los reportes y auditoría

---

## 6. Ciclo de vida de la cotización

## 6.1 Estados requeridos

Se recomienda manejar al menos estos estados:

- `draft` — borrador interno aún no enviado
- `pending_approval` — pendiente de aprobación interna
- `approved_internal` — aprobada internamente y lista para envío o cierre
- `sent` — enviada al cliente
- `under_review` — en negociación / revisión / esperando ajustes
- `accepted` — aceptada por el cliente
- `rejected` — rechazada / oportunidad perdida
- `expired` — vencida por fecha de vigencia
- `converted` — convertida a venta
- `cancelled` — cancelada internamente

## 6.2 Reglas de transición

- una cotización nueva nace en `draft`
- si viola políticas comerciales debe pasar a `pending_approval`
- solo una cotización aprobada o aceptada debe poder convertirse en venta
- una cotización vencida no debe convertirse sin revalidación o nueva versión
- una cotización convertida queda cerrada comercialmente y no debe seguir editándose
- una cotización cancelada o rechazada no debe reaprovecharse sin generar nueva versión o duplicado

## 6.3 Fechas clave a registrar
- fecha de creación
- fecha de última modificación
- fecha de envío
- fecha de aprobación interna
- fecha de aceptación/rechazo del cliente
- fecha de vencimiento
- fecha de conversión a venta
- fecha de cancelación si aplica

---

## 7. Numeración y referencias

Cada cotización debe tener:

- identificador interno UUID
- número comercial legible, por ejemplo `COT-000123`
- secuencia por sucursal o política global definida
- referencia opcional del cliente
- referencia opcional del vendedor
- vínculo a oportunidad, visita, pedido previo o conversación comercial cuando exista

### Requerimientos
- el número comercial no debe cambiar aunque existan nuevas versiones
- las versiones deben colgar de una referencia maestra
- debe poder buscarse por número, cliente, teléfono, documento o vendedor

---

## 8. Datos del cliente

El módulo debe soportar cotizaciones para:

- clientes ya registrados
- prospectos aún no formalizados
- clientes empresa
- clientes persona
- clientes gubernamentales si el negocio lo requiere

## 8.1 Datos mínimos del cliente en la cotización
- nombre o razón social
- tipo de entidad
- documento (cédula / RNC / otro, si aplica)
- teléfono principal
- correo electrónico
- dirección comercial o de entrega
- contacto responsable
- sucursal asociada
- observaciones comerciales

## 8.2 Reglas de negocio del cliente
- la cotización debe conservar una **instantánea comercial** del cliente al momento de emisión
- cambios futuros en la ficha del cliente no deben alterar retrospectivamente documentos ya emitidos
- si el cliente no existe aún, debe permitirse crear prospecto o cliente rápido sin romper la trazabilidad
- si el cliente tiene límite de crédito o balance vencido, esa información debe ser visible como contexto comercial para decisión de conversión

---

## 9. Encabezado del documento de cotización

Campos requeridos en el encabezado:

- número de cotización
- sucursal emisora
- fecha de emisión
- fecha de vencimiento
- cliente / prospecto
- vendedor responsable
- canal de origen (mostrador, WhatsApp, teléfono, correo, visita, web, referido)
- prioridad
- moneda
- lista de precios aplicada
- condiciones comerciales
- tiempo estimado de entrega
- observaciones internas
- observaciones visibles al cliente
- estado actual
- versión actual

---

## 10. Líneas de productos y servicios

Cada cotización debe permitir múltiples líneas.

## 10.1 Datos mínimos por línea
- orden de la línea
- tipo de línea: producto, servicio, texto libre o cargo adicional
- producto/servicio referenciado si viene del catálogo
- descripción comercial editable
- código interno / SKU / referencia
- unidad de medida
- cantidad
- precio unitario
- descuento de línea
- tasa de impuesto
- subtotal de línea
- impuesto de línea
- total de línea
- notas de línea

## 10.2 Comportamientos requeridos
- se deben poder agregar líneas desde catálogo
- se deben poder agregar líneas manuales cuando el artículo no exista en catálogo
- la descripción comercial debe poder ajustarse sin alterar la ficha maestra del producto
- debe permitir líneas de servicio, instalación, transporte, garantía extendida u otros cargos comerciales
- debe soportar reordenar líneas
- debe soportar eliminar líneas con recalculo automático

## 10.3 Contexto de inventario
- si la línea proviene de inventario, debe poder mostrar stock disponible, stock mínimo y advertencias
- una advertencia de stock no debe impedir cotizar automáticamente, pero sí debe quedar visible
- si en el futuro se implementa reserva, debe quedar desacoplada del acto de cotizar

---

## 11. Precios, descuentos e impuestos

## 11.1 Pricing
La cotización debe soportar:

- precio base del catálogo
- lista de precios por tipo de cliente o canal
- precio manual autorizado
- descuentos por línea
- descuentos globales
- recargos globales si el negocio lo necesita
- costo referencial para validaciones internas de margen

## 11.2 Reglas de descuento
- el sistema debe validar topes de descuento por rol
- si el descuento excede la política, debe requerir aprobación
- debe registrarse quién autorizó el descuento excepcional
- el precio final aprobado debe quedar congelado en la versión emitida

## 11.3 Impuestos
La cotización debe manejar:

- productos gravados y exentos
- tasa de impuesto por línea
- subtotal gravado
- subtotal exento
- monto total de impuestos
- total general

## 11.4 Redondeo y precisión
- el sistema debe definir reglas uniformes de redondeo
- los cálculos deben ser reproducibles en impresión, PDF, pantalla y conversión a venta
- no deben existir diferencias entre total mostrado y total convertido

---

## 12. Vigencia y condiciones comerciales

Toda cotización debe tener vigencia explícita.

## 12.1 Requerimientos de vigencia
- fecha de emisión
- fecha de vencimiento
- días de vigencia
- alerta de vencimiento próximo
- bloqueo o advertencia al convertir una cotización vencida

## 12.2 Condiciones comerciales que deben poder guardarse
- tiempo de entrega
- condiciones de pago
- porcentaje de anticipo si aplica
- política de devolución o garantía
- exclusiones o alcances del servicio
- condiciones de instalación o despacho
- notas legales/comerciales

## 12.3 Reglas recomendadas
- la vigencia debe imprimirse y exportarse siempre
- una cotización vencida no debe reactivarse silenciosamente; debe renovarse o versionarse

---

## 13. Flujo de aprobación

El módulo debe soportar aprobación interna antes del cierre comercial cuando aplique.

## 13.1 Casos que pueden requerir aprobación
- descuento por encima del permitido
- margen por debajo del mínimo
- monto total por encima de cierto umbral
- cliente con riesgo crediticio
- condiciones especiales de pago
- entrega extraordinaria o compromiso no estándar

## 13.2 Datos que deben registrarse
- motivo de la solicitud
- usuario solicitante
- usuario aprobador o rechazador
- fecha/hora de decisión
- comentario obligatorio en aprobaciones excepcionales
- versión aprobada

## 13.3 Reglas
- no debe poder enviarse o convertirse una cotización bloqueada por política sin aprobación válida
- si la cotización cambia después de aprobada, la aprobación puede invalidarse y requerir una nueva

---

## 14. Versionado y trazabilidad

El versionado es obligatorio para un flujo comercial serio.

## 14.1 Requerimientos mínimos
- una cotización debe tener documento maestro + número de versión
- ejemplo: `COT-000123 v1`, `v2`, `v3`
- toda modificación relevante posterior al envío debe generar nueva versión o al menos snapshot trazable
- debe poder verse el historial de versiones
- debe saberse cuál fue enviada, cuál fue aprobada y cuál fue convertida

## 14.2 Cambios que deben disparar control de versión
- cambio de líneas
- cambio de cantidades
- cambio de precio
- cambio de descuento
- cambio de impuesto
- cambio de cliente
- cambio de vigencia
- cambio de condiciones de pago o entrega

## 14.3 Auditoría requerida
- quién creó la versión
- a partir de cuál versión nació
- resumen del cambio
- motivo comercial del cambio
- fecha/hora

---

## 15. Envío, impresión y exportación

La cotización debe poder producir una salida formal para el cliente y/o para uso interno.

## 15.1 Formatos mínimos requeridos
- impresión A4 / carta comercial
- PDF descargable
- versión resumida para impresión térmica si el negocio la necesita
- exportación compartible por WhatsApp/correo como PDF o enlace

## 15.2 Contenido mínimo del documento
- branding de empresa/sucursal
- datos del cliente
- número y versión
- fecha de emisión y vigencia
- detalle de líneas
- subtotales, impuestos y total
- condiciones comerciales
- nombre o identificación del vendedor
- observaciones
- firma, aceptación o espacio equivalente si aplica

## 15.3 Requerimientos operativos
- debe existir control de reimpresiones o regeneración de PDF
- debe poder distinguirse documento interno vs documento para cliente
- debe poder registrarse canal de envío: impreso, PDF, correo, WhatsApp, enlace
- debe registrarse fecha/hora del último envío

## 15.4 Integración con impresión
Tomando como referencia el enfoque serio de impresión de `mangospos`, la cotización debe quedar preparada para:

- generación de payload estructurado de impresión
- historial de trabajos de impresión
- reimpresión controlada
- separación entre documento comercial y ejecución física del print job

---

## 16. Conversión a venta

La conversión de cotización a venta es una capacidad central.

## 16.1 Reglas básicas
- solo deben convertirse cotizaciones vigentes y autorizadas
- al convertir, debe crearse una venta nueva enlazada a la cotización origen
- la cotización debe quedar marcada como `converted`
- la venta debe conservar referencia a la cotización y versión fuente

## 16.2 Datos que deben heredarse a la venta
- cliente
- líneas aprobadas
- cantidades
- precios unitarios
- descuentos
- impuestos
- notas relevantes
- vendedor responsable
- condiciones de entrega o despacho cuando corresponda

## 16.3 Validaciones al convertir
- revalidación de existencia/estado del cliente
- revalidación de productos desactivados
- advertencia por precio vencido o vigencia expirada
- advertencia por stock insuficiente
- validación de permisos del usuario que convierte

## 16.4 Casos especiales
- permitir conversión parcial en el futuro si el negocio lo requiere, pero no asumirla como MVP
- si la cotización se modifica después de convertir, no debe alterar la venta ya creada
- una venta anulada no debe reabrir automáticamente la cotización sin decisión explícita

---

## 17. Seguimiento comercial

Una cotización seria necesita seguimiento posterior al envío.

## 17.1 Eventos de seguimiento requeridos
- llamada realizada
- mensaje enviado
- correo enviado
- visita realizada
- respuesta del cliente
- solicitud de ajuste
- recordatorio de vencimiento
- cierre ganado
- cierre perdido

## 17.2 Datos de seguimiento
- tipo de contacto
- fecha/hora
- usuario responsable
- resultado o comentario
- próximo paso
- fecha próxima de seguimiento

## 17.3 Automatismos deseables
- alertas por cotizaciones próximas a vencer
- alertas por cotizaciones enviadas sin seguimiento en X días
- alertas por cotizaciones aceptadas pendientes de convertir
- vista de pipeline por responsable comercial

---

## 18. Motivos de pérdida, rechazo o cancelación

Cuando una cotización no cierre, el sistema debe capturar la causa.

## 18.1 Motivos mínimos sugeridos
- precio alto
- cliente sin presupuesto
- competencia ganó
- no respondió
- producto sin disponibilidad
- condiciones no aceptadas
- error interno
- duplicada
- cancelada por el negocio

## 18.2 Reglas
- `rejected`, `expired` y `cancelled` deben diferenciarse
- debe existir comentario opcional u obligatorio según el motivo
- estos motivos deben alimentar reportes de pérdida comercial

---

## 19. Permisos y seguridad

El módulo debe integrarse con un modelo serio de permisos, siguiendo el tipo de granularidad visto en `mangospos`.

## 19.1 Permisos funcionales mínimos
- `quotations.view`
- `quotations.create`
- `quotations.edit_own`
- `quotations.edit_any`
- `quotations.request_approval`
- `quotations.approve`
- `quotations.reject`
- `quotations.send`
- `quotations.print`
- `quotations.export`
- `quotations.convert_to_sale`
- `quotations.cancel`
- `quotations.reopen`
- `quotations.view_reports`
- `quotations.view_margin`

## 19.2 Reglas recomendadas de acceso
- un vendedor normal solo debería editar sus borradores o sus cotizaciones abiertas si la política lo permite
- aprobar, anular, reabrir o autorizar descuentos excepcionales debe requerir permisos superiores
- ver márgenes, costos o utilidades debe ser restringible
- la información debe respetar aislamiento por sucursal

---

## 20. Reportes requeridos

## 20.1 Reportes operativos
- listado de cotizaciones por estado
- cotizaciones por vendedor
- cotizaciones por sucursal
- cotizaciones por cliente
- cotizaciones próximas a vencer
- cotizaciones vencidas sin cierre

## 20.2 Reportes comerciales
- monto total cotizado por período
- pipeline abierto por etapa
- tasa de conversión cotización → venta
- tiempo promedio entre emisión y cierre
- monto ganado vs perdido
- top vendedores por monto cotizado y convertido
- top clientes cotizados
- motivos de pérdida más frecuentes

## 20.3 Reportes de control
- descuentos otorgados por usuario
- cotizaciones aprobadas excepcionalmente
- cotizaciones reimpresas / reenviadas
- historial de versiones por documento
- cotizaciones convertidas por usuario

---

## 21. Búsqueda, filtros y organización

El módulo debe permitir localizar cotizaciones rápidamente.

## 21.1 Búsquedas mínimas
- por número de cotización
- por cliente
- por documento del cliente
- por teléfono
- por vendedor
- por referencia externa

## 21.2 Filtros mínimos
- sucursal
- estado
- rango de fechas
- vigencia
- vendedor
- cliente
- canal
- prioridad
- cotizaciones convertidas / no convertidas

---

## 22. Integración con módulos actuales de `flutter_shop+`

## 22.1 Clientes
- debe reutilizar `clients`
- debe permitir crear prospecto/cliente rápido con evolución a ficha formal

## 22.2 Productos
- debe reutilizar `products`
- debe usar precio, impuesto y stock como referencia comercial

## 22.3 Ventas
- debe integrarse con `sales` y `sale_items` para la conversión
- debe quedar rastro explícito de la cotización fuente

## 22.4 Impresión
- debe reutilizar la base de impresión ya iniciada en el proyecto
- debe contemplar documentos A4 y eventual térmica

## 22.5 Usuarios / permisos
- debe alinearse con el roadmap de permisos más granulares descrito en `DATABASE.md`

---

## 23. Estructura mínima de información recomendada

Sin imponer aún una migración definitiva, el módulo requerirá como mínimo entidades equivalentes a:

- `quotations`
- `quotation_items`
- `quotation_versions`
- `quotation_events` o `quotation_follow_ups`
- `quotation_approvals`
- `quotation_print_logs` o vínculo a `print_jobs`

## 23.1 Datos esperados en `quotations`
- id
- branch_id
- quote_number
- master_quote_id si hay versionado maestro
- current_version_number
- client_id nullable
- snapshot del cliente
- status
- source_channel
- owner_user_id
- currency_code
- price_list_id nullable
- issue_date
- valid_until
- subtotal
- discount_total
- tax_total
- grand_total
- internal_notes
- customer_notes
- terms_and_conditions
- accepted_at
- rejected_at
- expired_at
- converted_sale_id nullable
- converted_at nullable
- created_by / updated_by / timestamps

## 23.2 Datos esperados en `quotation_items`
- id
- quotation_id
- version_number o relación a versión
- product_id nullable
- sku snapshot
- description
- quantity
- unit_price
- discount_type / discount_value
- discount_amount
- tax_rate
- tax_amount
- subtotal
- total
- unit_of_measure
- sort_order
- line_notes

---

## 24. Reglas de auditoría

Todo el módulo debe dejar evidencia suficiente para revisión posterior.

Se debe registrar como mínimo:

- usuario creador
- usuario editor
- usuario aprobador
- usuario que envió
- usuario que convirtió a venta
- cambios de estado
- cambios de versión
- cambios de precios y descuentos
- impresiones/exportaciones relevantes

---

## 25. Requerimientos no funcionales ligados al negocio

- cálculos consistentes entre app, PDF e impresión
- soporte multi-sucursal
- trazabilidad completa por usuario
- rendimiento aceptable en listados y filtros comerciales
- capacidad de crecimiento a pipeline más robusto sin rehacer el modelo
- preparación para integración futura con flujos de firma, pagos parciales, pedidos o reserva de stock

---

## 26. Reglas MVP vs evolución

## 26.1 MVP recomendado
El MVP serio debería incluir al menos:

- creación de cotización
- cliente/prospecto
- líneas manuales y desde catálogo
- precios, descuentos, impuestos, total
- vigencia
- estados básicos
- PDF / impresión básica
- seguimiento mínimo
- conversión completa a venta
- permisos básicos
- reportes iniciales

## 26.2 Evolución posterior
Después del MVP puede crecer hacia:

- aprobación multinivel
- firma o aceptación formal del cliente
- envío con enlace web
- recordatorios automáticos
- conversión parcial
- reservas de inventario
- integración con CRM / oportunidades
- analítica comercial avanzada

---

## 27. Decisiones clave antes de implementar backend definitivo

Antes de modelar DB o RPCs finales, conviene cerrar estas decisiones:

1. si la numeración será por sucursal o global
2. si el prospecto vivirá dentro de `clients` o en entidad separada
3. si toda edición posterior al envío generará versión obligatoria
4. qué umbrales disparan aprobación
5. si la aceptación del cliente será solo manual o también digital
6. si se permitirá conversión parcial en primera fase
7. qué formato de impresión será obligatorio desde el inicio: A4, PDF, térmica o varios
8. si se mostrará margen/costo a todos o solo a supervisión

---

## 28. Resumen ejecutivo

Para que `flutter_shop+` tenga un módulo de cotizaciones realmente útil para facturación y ventas, el sistema debe tratar la cotización como un **documento comercial completo**, con:

- identidad propia
- estados formales
- cliente y líneas bien estructuradas
- pricing e impuestos confiables
- vigencia y condiciones claras
- aprobación cuando corresponda
- historial y versiones
- seguimiento comercial
- conversión limpia a venta
- impresión/exportación trazable
- permisos granulares
- reportes accionables

Sin esos elementos, el módulo quedaría en una simple pre-venta informal. Con ellos, pasa a ser una pieza real del flujo comercial del producto.
