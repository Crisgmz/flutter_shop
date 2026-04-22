# QA / Guardrail — Alcance mínimo obligatorio de Cotizaciones

Fecha: 2026-04-10  
Repo: `flutter_shop+`  
Base de contraste principal: `docs/quotations/REQUISITO_MINIMO_COTIZACIONES.md`

---

## Veredicto ejecutivo

**El módulo NO cumple todavía el alcance mínimo obligatorio completo.**

Hoy el estado real es este:

- **Crear cotizaciones:** `PARCIALMENTE CUMPLE`
- **Ver cotizaciones:** `PARCIALMENTE CUMPLE`
- **Editar cotizaciones:** `NO CUMPLE`
- **Borrar cotizaciones:** `PARCIALMENTE CUMPLE`
- **Fecha de vencimiento:** `PARCIALMENTE CUMPLE`
- **Convertir cotización a venta:** `PARCIALMENTE CUMPLE / BLOQUEADO FUNCIONALMENTE`

### Juicio corto

La base actual ya no es humo: hay tabla propuesta, listado, creación, borrado condicional y una conversión transaccional por RPC bastante mejor que el enfoque viejo.

Pero el mínimo obligatorio **sigue abierto** por cuatro razones duras:

1. **No existe flujo real para abrir/ver detalle de una cotización específica.**
2. **No existe flujo real de edición.**
3. **La conversión depende de que la cotización esté `approved`, pero no existe flujo visible para llevar una cotización a `approved`.**
4. **La persistencia de cotizaciones sigue dependiendo de `supabase/sql-next/20260410_quotations_schema.sql`, no del camino canónico principal `supabase/sql/01-04`.**

---

## Fuente revisada

Se revisaron primero:

- `CLAUDE.md`
- `DATABASE.md`
- `flutter_shop.md`
- `PLAN_MAESTRO_FLUTTER_SHOP.md`
- `docs/quotations/REQUISITO_MINIMO_COTIZACIONES.md`

Y luego el estado actual del módulo en:

- `lib/features/quotations/data/quotations_models.dart`
- `lib/features/quotations/data/quotations_repository.dart`
- `lib/features/quotations/presentation/quotation_create_page.dart`
- `lib/features/quotations/presentation/quotations_page.dart`
- `lib/app/router.dart`
- `supabase/sql-next/20260410_quotations_schema.sql`
- docs relacionados de auditoría/sprint dentro de `docs/quotations/` y `docs/architecture/`

---

## Checklist contra el requisito mínimo

## 1) Crear cotizaciones

**Estado:** `PARCIALMENTE CUMPLE`

### Lo que sí existe

- Hay ruta para crear: `'/cotizaciones/nueva'` en `lib/app/router.dart:64-65`.
- Existe pantalla de creación: `QuotationCreatePage` en `lib/features/quotations/presentation/quotation_create_page.dart:11-200`.
- Se puede:
  - seleccionar cliente (`quotation_create_page.dart:311-345`)
  - agregar productos del catálogo (`quotation_create_page.dart:260+` y `_addItem` en `42-52`)
  - cambiar cantidades (`54-64`)
  - guardar observaciones (`323-333`)
  - elegir fecha de vigencia (`66-86`, `343-345`)
- El repositorio persiste cabecera + líneas:
  - `createQuote()` en `quotations_repository.dart:182-287`
  - inserta en `quotations` (`247-251`)
  - inserta en `quotation_items` (`257-278`)
- Se calculan subtotal, impuesto y total con helpers centralizados:
  - `QuotationsMath` en `quotations_models.dart:308-317`
  - uso en `quotations_repository.dart:215-217`

### Lo que falta o está débil

- **No hay soporte real de descuento editable** en UI ni en input del repositorio.
  - El payload de líneas fuerza `discount_amount: 0` en `quotations_repository.dart:269`.
- **La creación no es atómica desde Flutter**:
  - primero inserta cabecera (`247-251`)
  - luego inserta líneas (`278`)
  - si falla el segundo paso, puede quedar una cotización huérfana o parcial.
- **No hay líneas manuales/no catálogo**. Para el mínimo inmediato esto no bloquea si el negocio acepta solo catálogo, pero sí limita el uso comercial real.

### Conclusión QA

Crear existe, pero no está lo bastante endurecido para llamarlo “cerrado” sin reservas.

### Criterio de aceptación mínimo para cerrar este punto

- [ ] Crear una cotización con cliente, líneas, cantidades, precios y vigencia funciona extremo a extremo.
- [ ] Si falla el guardado de líneas, no queda cabecera huérfana.
- [ ] La cotización creada aparece luego en el listado con total y vigencia correctos.
- [ ] Si el alcance mínimo incluye descuentos operativos, deben poder capturarse o el producto debe declarar explícitamente que para el mínimo solo se soporta impuesto automático y descuento `0`.

---

## 2) Ver cotizaciones

**Estado:** `PARCIALMENTE CUMPLE`

### Lo que sí existe

- Existe listado principal en `/cotizaciones` con carga desde `quotationsFoundationProvider`.
- `fetchQuotes()` trae:
  - id
  - código
  - estado
  - fechas
  - monto
  - cliente
  - `converted_sale_id`
  - `notes`
  en `quotations_repository.dart:12-63`.
- La tabla/listado muestra:
  - código
  - cliente
  - estado
  - vigencia
  - monto
  en `quotations_page.dart:132-196`.
- En mobile también se muestra estado + vigencia + monto en `_QuoteMobileCard` (`291-351`).
- La UI marca una cotización vencida de forma derivada usando:
  - `isExpired` (`quotations_models.dart:26-27`)
  - `effectiveStatus` (`36`)

### Lo que falta

El requisito mínimo no pide solo listar. Pide también:

- **abrir una cotización existente**
- **revisar sus datos principales**

Eso **no existe hoy** como flujo de detalle.

### Evidencia concreta

- En router solo están:
  - `'/cotizaciones'`
  - `'/cotizaciones/nueva'`
  según `lib/app/router.dart:62-65`
- No existe ruta tipo:
  - `'/cotizaciones/:id'`
  - `'/cotizaciones/:id/editar'`
- No existe `QuotationDetailPage` ni método tipo `fetchQuoteById`.
- En la tabla desktop no hay acción de abrir/ver, solo convertir/eliminar (`quotations_page.dart:165-190`).
- En mobile la tarjeta ni siquiera tiene acciones (`quotations_page.dart:291-351`).

### Impacto

Hoy el usuario puede ver un resumen superficial, pero **no puede abrir la cotización como documento** para inspeccionar líneas, observaciones, cliente snapshot o datos completos.

### Criterio de aceptación mínimo para cerrar este punto

- [ ] Desde el listado se puede abrir una cotización específica.
- [ ] Existe vista detalle con al menos:
  - [ ] cliente
  - [ ] líneas/productos
  - [ ] cantidades
  - [ ] precios
  - [ ] observaciones
  - [ ] estado
  - [ ] fecha de creación
  - [ ] fecha de vencimiento
  - [ ] total
- [ ] En mobile también existe una forma real de abrir esa cotización.

---

## 3) Editar cotizaciones

**Estado:** `NO CUMPLE`

### Hallazgo central

No encontré implementación real de edición ni en UI, ni en router, ni en repositorio.

### Evidencia concreta

- `QuotationsRepositoryContract` expone solo:
  - `loadFoundation`
  - `fetchQuotes`
  - `fetchProducts`
  - `fetchClients`
  - `createQuote`
  - `convertToSale`
  - `deleteQuote`
  en `quotations_models.dart:298-305`
- No existe `updateQuote`, `editQuote`, `saveDraftChanges`, `fetchQuoteDetail`, etc.
- No existe ruta de edición en `lib/app/router.dart:62-65`.
- `QuotationCreatePage` está diseñada como creación nueva, no como editor cargado desde una cotización existente.
- Tampoco existe acción “Editar” en el listado de `quotations_page.dart:165-190`.

### Riesgo funcional

Este es uno de los huecos más claros contra el requisito mínimo obligatorio. No es un edge case: **editar es parte explícita del mínimo**.

### Criterio de aceptación mínimo para cerrar este punto

- [ ] Existe acción de editar desde listado y/o detalle.
- [ ] Solo se puede editar en estados permitidos por regla de negocio.
- [ ] Se pueden modificar al menos:
  - [ ] cliente
  - [ ] líneas/productos
  - [ ] cantidades
  - [ ] precios
  - [ ] observaciones
  - [ ] fecha de vencimiento
- [ ] Una cotización `converted` no se comporta como editable normal.
- [ ] Los cambios persisten en cabecera y líneas sin dejar residuos viejos.
- [ ] La actualización deja rastro mínimo de auditoría/evento.

---

## 4) Borrar cotizaciones

**Estado:** `PARCIALMENTE CUMPLE`

### Lo que sí existe

- Hay acción de eliminar en desktop cuando `quote.canDelete` es verdadero (`quotations_page.dart:179-188`).
- Hay validación previa de negocio en cliente/repo:
  - `canDelete` solo para `draft`, `rejected`, `expired` en `quotations_models.dart:29-32`
  - `deleteQuote()` vuelve a validar estado y `converted_sale_id` en `quotations_repository.dart:318-345`
- La regla mínima “una cotización ya convertida no debe poder borrarse como si no hubiera existido” sí está contemplada.

### Lo que falta o está débil

- **No hay acción de borrar en mobile**. `_QuoteMobileCard` no tiene ninguna acción (`quotations_page.dart:291-351`).
- **No hay detalle** desde el cual borrar con contexto completo.
- La eliminación depende del estado cargado, pero no deja un rastro de auditoría visible; simplemente borra:
  - `await _client.from('quotations').delete().eq('id', quoteId);` en `quotations_repository.dart:345`
- En DB, la policy de delete usa `can_manage_branch_data()` (`sql-next:305-310`), mientras la UI ofrece botón según `canDelete`; si el rol no cuadra, el usuario verá botón pero la operación fallará por permisos.

### Criterio de aceptación mínimo para cerrar este punto

- [ ] Eliminar funciona en desktop y mobile.
- [ ] Una cotización convertida no puede eliminarse.
- [ ] Una cotización en estado no permitido no ofrece acción de borrar o devuelve mensaje claro.
- [ ] La UI no promete borrar si RLS/rol real lo va a negar silenciosamente.
- [ ] Si la estrategia del negocio es hard delete, debe estar explícitamente aceptada; si no, migrar a cancelación/soft delete.

---

## 5) Fecha de vencimiento

**Estado:** `PARCIALMENTE CUMPLE`

### Lo que sí existe

- La fecha de vencimiento es obligatoria en DB:
  - `valid_until timestamptz not null` en `sql-next:47`
- La UI permite seleccionarla al crear:
  - `showDatePicker` en `quotation_create_page.dart:66-86`
- El repositorio valida que sea futura al crear:
  - `quotations_repository.dart:197-200`
- El listado la muestra claramente:
  - desktop `quotations_page.dart:155`
  - mobile `333`
- El modelo interpreta vencimiento en tiempo real:
  - `isExpired` y `effectiveStatus` en `quotations_models.dart:26-36`
- La RPC de conversión también bloquea cotizaciones vencidas y las marca `expired` si corresponde:
  - `sql-next:413-418`

### Lo que falta

- **No existe edición de fecha de vencimiento**, porque no existe edición en general.
- El vencimiento se refleja por cálculo en cliente, pero **no hay evidencia de una rutina general que sincronice el estado persistido a `expired` fuera del flujo de conversión**.
- No hay detalle de cotización donde la vigencia se vea junto al resto del documento y sus líneas.

### Criterio de aceptación mínimo para cerrar este punto

- [ ] Toda cotización se crea con `valid_until` obligatorio.
- [ ] La vigencia puede editarse mientras el estado lo permita.
- [ ] La cotización vencida se identifica claramente en listado y detalle.
- [ ] Una cotización vencida no puede convertirse a venta sin revalidación explícita.

---

## 6) Convertir cotización a venta

**Estado:** `PARCIALMENTE CUMPLE / BLOQUEADO FUNCIONALMENTE`

### Lo que sí existe

Este punto mejoró bastante a nivel técnico:

- La conversión ya no es una cadena frágil de inserts desde Flutter.
- El repositorio usa RPC:
  - `convertToSale()` en `quotations_repository.dart:291-315`
- Existe función SQL transaccional:
  - `convert_quotation_to_sale(...)` en `sql-next:365-550`
- La RPC:
  - valida sesión (`383-385`)
  - valida acceso/permiso (`387-403`)
  - bloquea reconversión (`405-407`)
  - bloquea estados no válidos (`409-410`)
  - bloquea vencidas (`413-418`)
  - valida líneas (`421-427`)
  - valida stock (`429-440`)
  - crea `sales` (`451-489`)
  - crea `sale_items` desde `quotation_items` (`491-517`)
  - marca la cotización como `converted` (`519-524`)
  - registra evento (`526-544`)

### El problema que impide cerrar este punto

**La conversión solo funciona si la cotización está `approved`**:

- modelo/UI: `canConvert => status == QuoteStatus.approved && !isExpired` (`quotations_models.dart:28`)
- DB/RPC: `if v_quote.status <> 'approved' then raise exception` (`sql-next:409-410`)

Pero hoy:

- no existe flujo para aprobar
- no existe cambio de estado visible a `sent`, `under_review` o `approved`
- no existe edición/detalle desde donde operar ese ciclo

Resultado real:

> La infraestructura de conversión existe, pero el flujo comercial mínimo está **bloqueado** porque no hay manera normal dentro del módulo de llegar a una cotización convertible.

### Además

- En mobile no hay acción de convertir (`_QuoteMobileCard`, `quotations_page.dart:291-351`).
- El diálogo dice “Esto generará una factura” (`quotations_page.dart:210`), pero la RPC crea una `sale` con defaults:
  - `receipt_type = consumer_final` por default (`sql-next:367`)
  - `sale_status = pending` por default (`368`)
  Esto no necesariamente rompe el mínimo de cotizaciones, pero sí puede inducir expectativas fiscales/comerciales erróneas.

### Criterio de aceptación mínimo para cerrar este punto

- [ ] Existe una forma real dentro del producto de llevar una cotización a estado convertible.
- [ ] Convertir traslada correctamente:
  - [ ] cliente
  - [ ] líneas
  - [ ] cantidades
  - [ ] precios
  - [ ] impuestos/descuentos aplicables
- [ ] La cotización queda marcada como `converted` y enlazada a la venta.
- [ ] La venta conserva referencia a la cotización origen.
- [ ] La cotización convertida ya no puede editarse/borrarse como una normal.
- [ ] El flujo existe también en mobile o se declara explícitamente que no hay soporte mobile para ese mínimo.

---

## Gaps transversales que el agente de implementación NO debe ignorar

## A. Falta de detalle + falta de edición = el mínimo no cierra

Aunque el listado y la creación existan, el requisito mínimo no queda satisfecho sin:

- vista detalle
- edición
- reglas de estado visibles

Sin eso, el módulo sigue sintiéndose “foundation con persistencia”, no flujo comercial mínimo completo.

## B. El flujo real `quote -> sale` está mejor técnicamente, pero incompleto operativamente

La RPC ya es una base seria. El bloqueo ya no es tanto técnico como de producto/flujo:

- no hay approve
- no hay cambio de estado
- no hay forma visible de preparar una cotización hasta el estado convertible

## C. Persistencia aún fuera del camino canónico principal

`quotations`, `quotation_items`, `quotation_events` y `convert_quotation_to_sale` están en:

- `supabase/sql-next/20260410_quotations_schema.sql`

No aparecen en el camino canónico principal `supabase/sql/01-04`.

### Riesgo

Un ambiente puede tener UI de cotizaciones desplegada pero no tener la migración additive ejecutada.

### Guardrail

**No declarar “mínimo terminado” mientras el esquema de cotizaciones siga fuera del camino canónico que realmente se instala/replica en los ambientes.**

## D. Creación todavía puede dejar datos parciales

`createQuote()` hace múltiples escrituras cliente-side (`quotations_repository.dart:247-278`).

### Riesgo

Si falla el insert de líneas después de crear la cabecera, queda inconsistencia.

### Guardrail

Antes de cerrar el mínimo, endurecer creación con una estrategia transaccional real o con compensación explícita.

## E. Desktop y mobile no tienen la misma capacidad operativa

- Desktop: convertir y borrar sí aparecen en la tabla.
- Mobile: la tarjeta solo muestra información; no hay abrir, editar, convertir ni borrar.

### Guardrail

No marcar el requisito como cumplido “en la app” si solo está razonablemente operable en desktop.

---

## Qué SÍ se puede considerar resuelto o encaminado

- [x] Existe módulo aislado de cotizaciones en Flutter.
- [x] Ya no depende raro de modelos de ventas para crear cotizaciones como antes.
- [x] Hay estados formales definidos en código/SQL (`draft`, `sent`, `under_review`, `approved`, `rejected`, `expired`, `converted`).
- [x] Hay fecha de vencimiento obligatoria.
- [x] La conversión a venta dejó de ser un hack cliente-side y pasó a RPC transaccional.
- [x] Hay snapshots comerciales básicos del cliente y snapshots básicos de producto en líneas.
- [x] Hay base mínima de auditoría vía `quotation_events`.

---

## Qué falta exactamente para poder decir “cumple el mínimo obligatorio”

### Bloqueantes reales

- [ ] **Agregar vista detalle de cotización**.
- [ ] **Agregar edición real de cotización**.
- [ ] **Agregar transición operativa de estados suficiente para llegar a `approved` o ajustar la regla mínima de conversión.**
- [ ] **Alinear mobile con capacidades mínimas del módulo.**
- [ ] **Meter el esquema de cotizaciones al flujo canónico de migraciones/ambientes.**

### Endurecimientos altamente recomendados antes de cerrar

- [ ] Hacer `createQuote` transaccional o compensado.
- [ ] Alinear visibilidad de botones con permisos/RLS reales.
- [ ] Definir si el mínimo soporta o no descuentos manuales.
- [ ] Añadir pruebas de flujo completo: crear -> ver -> editar -> borrar -> convertir.

---

## Smoke tests de aceptación recomendados para el agente implementador

## Caso 1 — Crear y ver

- [ ] Crear una cotización con cliente existente, 2 líneas, vigencia futura y observación.
- [ ] Confirmar que aparece en listado.
- [ ] Abrirla en detalle.
- [ ] Verificar cliente, líneas, montos, vigencia y estado.

## Caso 2 — Editar

- [ ] Editar cliente.
- [ ] Cambiar cantidad de una línea.
- [ ] Cambiar precio de una línea.
- [ ] Editar observación.
- [ ] Cambiar fecha de vencimiento.
- [ ] Guardar y reabrir.
- [ ] Confirmar persistencia correcta.

## Caso 3 — Borrar válido

- [ ] Borrar una cotización `draft` no convertida.
- [ ] Confirmar que desaparece del listado.
- [ ] Confirmar que no quedan líneas huérfanas.

## Caso 4 — Borrar inválido

- [ ] Intentar borrar una cotización convertida.
- [ ] Confirmar que no se permite.

## Caso 5 — Vencimiento

- [ ] Crear cotización con vigencia corta.
- [ ] Confirmar que al vencer se identifica claramente como expirada.
- [ ] Intentar convertirla y confirmar bloqueo correcto.

## Caso 6 — Convertir a venta

- [ ] Llevar una cotización a estado convertible por flujo normal del producto.
- [ ] Convertirla.
- [ ] Verificar que la venta nueva conserva cliente, líneas, cantidades, precios e impuestos.
- [ ] Verificar que la cotización queda `converted` y enlazada a la venta.
- [ ] Verificar que ya no se puede editar/borrar como una normal.

---

## Recomendación final para el agente de implementación

**No gastes el siguiente sprint en “mejorar la pantalla” primero.**

Orden correcto para cerrar el mínimo:

1. **Detalle**
2. **Edición**
3. **Transición de estado suficiente para conversión**
4. **Ajuste mobile**
5. **Endurecimiento de create**
6. **Subir esquema al camino canónico**

Si eso no se hace, el módulo seguirá pareciendo avanzado en superficie pero incompleto en operación real.

---

## Conclusión final

Hoy Cotizaciones está **más creíble que antes**, pero **todavía no pasa QA contra el requisito mínimo obligatorio**.

Lo que falta no es cosmético. Es justamente el núcleo que el requisito pidió como base real:

- abrir/ver detalle
- editar
- manejar el ciclo suficiente para convertir
- cerrar las reglas de consistencia del flujo

Mientras eso no esté, **no debería darse el módulo por “mínimo cumplido”**.
