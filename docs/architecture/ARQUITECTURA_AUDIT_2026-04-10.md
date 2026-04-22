# Auditoría arquitectónica y de calidad — `flutter_shop+`

**Fecha:** 2026-04-10  
**Enfoque:** Flutter architecture / code quality / readiness for scaling  
**Alcance revisado:** `CLAUDE.md`, `DATABASE.md`, `flutter_shop.md`, estructura actual de `lib/`, `supabase/`, providers, router, theming, responsive, widgets compartidos, y estado de `flutter analyze`.

---

## Resumen ejecutivo

El proyecto **sí tiene una base arquitectónica reconocible y razonable** para un MVP administrativo:

- organización **feature-first** clara
- `GoRouter` con `ShellRoute`
- `Riverpod` simple y consistente
- separación básica `data/` + `presentation/`
- capa de tokens visuales (`AppTokens`)
- soporte explícito de contexto por sucursal vía Supabase RPC

Pero esa base **todavía no está endurecida**. El mayor problema no es “falta de patrón”, sino **falta de consolidación**:

1. la UI está muy concentrada en páginas gigantes
2. el estado de negocio vive demasiado cerca de la pantalla
3. hay mucha duplicación visual y funcional
4. el uso de Riverpod es correcto pero todavía muy superficial
5. la capa compartida existe, pero **no gobierna realmente** el código
6. hay desviaciones directas contra las convenciones del propio repo (`CLAUDE.md`)
7. varias piezas nuevas (especialmente cotizaciones) todavía están en modo “foundation/MVP”, no listas para escalar sin refactor

**Diagnóstico corto:**
- **Base buena:** sí
- **Arquitectura madura:** no todavía
- **Escalable con el estado actual:** parcialmente, pero con alto costo de mantenimiento
- **Riesgo principal:** crecimiento por copia/pega de pantallas en lugar de composición modular

---

## 1. Lo que está bien resuelto hoy

### 1.1 Organización general del proyecto
La estructura general es clara y fácil de entender:

- `lib/app/` para bootstrap y routing
- `lib/core/` para config/theme/bootstrap
- `lib/features/<feature>/data + presentation`
- `lib/shared/` para formatters, responsive y widgets reutilizables

Esto hace que el proyecto sea navegable y evita el caos típico de un `lib/` plano.

### 1.2 Routing centralizado y shell común
`lib/app/router.dart` está bien planteado para el tamaño actual:

- redirección auth-aware
- `ShellRoute` para módulos autenticados
- rutas en español alineadas con negocio
- helper `_page(... NoTransitionPage ...)`

Eso da una base aceptable para backoffice y POS híbrido.

### 1.3 Separación mínima entre acceso a datos y UI
En casi todos los módulos se repite el patrón:

- repository en `data/`
- providers en `presentation/`
- page/widget que consume providers

Ejemplos consistentes:
- `inventory`
- `clients`
- `suppliers`
- `expenses`
- `reports`
- `dashboard`

No es Clean Architecture estricta, pero para este tipo de producto puede funcionar bien si se disciplina.

### 1.4 Uso de Riverpod simple y legible
El uso dominante de `Provider`, `FutureProvider`, `StateProvider` es sencillo y entendible. No hay una sobre-ingeniería innecesaria con notifiers complejos donde todavía no hacen falta.

### 1.5 Soporte multi-sucursal visible en toda la app
Hay una intención arquitectónica coherente entre frontend y DB:

- `current_branch_id()`
- `set_current_branch(...)`
- `invalidateBranchScopedData(ref)`
- repos filtrando por sucursal
- documentación DB consistente con ese modelo

Eso es importante porque el sistema ya nace con una restricción de dominio real.

---

## 2. Hallazgos principales

## 2.1 Organización por feature: correcta en forma, débil en profundidad

### Lo bueno
Cada feature tiene su carpeta y casi todas respetan:

- `data/`
- `presentation/`

### Lo problemático
La separación interna es todavía muy superficial. En la práctica, muchas features se reducen a:

- un repository grande
- una página gigantesca
- unos providers mínimos

Ejemplos de páginas sobredimensionadas:

- `settings_page.dart` — **946 líneas**
- `branches_page.dart` — **904 líneas**
- `users_page.dart` — **734 líneas**
- `inventory_page.dart` — **733 líneas**
- `purchases_page.dart` — **693 líneas**
- `dashboard_page.dart` — **620 líneas**
- `sales_page.dart` — **608 líneas**
- `clients_page.dart` — **566 líneas**
- `quotation_create_page.dart` — **483 líneas**
- `quotations_page.dart` — **468 líneas**

### Impacto
Cuando una feature vive dentro de una sola page:

- el widget hace layout + interacción + validación + flujos + dialogs
- extraer tests se vuelve más difícil
- cualquier cambio pequeño tiene alto riesgo de regresión visual
- la reutilización se degrada
- el onboarding del código empeora

### Conclusión
La organización por feature existe, pero **todavía no hay submódulos internos por caso de uso o por componentes**. Eso es el principal cuello de botella de mantenibilidad.

---

## 2.2 Routing: bien planteado, pero todavía poco desacoplado del dominio

### Estado actual
El routing central en `lib/app/router.dart` es limpio y suficiente para esta etapa.

### Hallazgos
1. El sistema usa `ShellRoute` correctamente para la navegación autenticada.
2. La visibilidad de módulos por rol está resuelta en `shell_nav_items.dart` + `shell_providers.dart`.
3. La protección real no es una guardia de ruta rica; se apoya más en navegación visible/invisible y una vista de “acceso restringido”.

### Riesgos
- Si el producto crece, el router central va a terminar siendo un archivo de coordinación demasiado manual.
- No existe todavía un modelo de rutas por feature o rutas registradas modularmente.
- La autorización está más cerca de UI/shell que de una política reutilizable.

### Observación importante
En `CLAUDE.md` se declara explícitamente:

> Do NOT use `Navigator.push` — use `context.go()` / `context.push()`.

No vi `Navigator.push`, lo cual está bien, pero sí hay abundante `Navigator.of(context).pop()` en dialogs/forms, lo cual es normal. El problema real de routing no es ese, sino que la **autorización sigue siendo bastante superficial** comparada con lo que piden `DATABASE.md` y `flutter_shop.md`.

### Veredicto
**Routing bueno para MVP.** Aún no es un routing listo para crecer por permisos finos, deep links complejos o features plug-in.

---

## 2.3 Riverpod/provider: consistente, pero aún demasiado “UI-driven”

### Patrón dominante observado
Se usa este patrón repetidamente:

- `RepositoryProvider`
- `FutureProvider<List/...>` para carga
- `StateProvider<T>` para búsqueda, filtros, selección
- invalidación manual con `ref.invalidate(...)`

### Lo bueno
- simple
- fácil de leer
- poca magia
- coherente entre módulos

### Lo débil
#### a) Mucho estado de negocio está dentro del widget
Ejemplo claro:
- `sales_page.dart`
- `quotation_create_page.dart`

Ahí el carrito, cantidades, cálculos, selección de cliente, flags de submit, etc., viven mayormente dentro del `StatefulWidget`.

Eso hace que:
- la lógica no sea reusable
- el flujo no sea testeable sin widget test pesado
- el módulo no pueda escalar bien a borradores, recuperación de sesión, offline futuro, etc.

#### b) Providers muy planos
La mayoría de providers son solamente wrappers para fetch de repositorio. Falta una capa intermedia para:

- coordinación de casos de uso
- manejo más explícito de errores
- agregación de estados de pantalla
- estados derivados reutilizables

#### c) Invalidación manual muy repetitiva
Hay bastante `ref.invalidate(...)` disperso. Funciona, pero a escala genera:

- dependencia de recordar qué refrescar
- coupling entre acciones UI y refresh de datos
- bugs sutiles cuando una acción toca varios datasets

#### d) Reuso accidental entre módulos
`quotation_create_page.dart` depende de providers y modelos de `sales`:

- `salesProductsProvider`
- `salesClientsProvider`
- `salesSearchProvider`
- `SaleCartItem`
- `SalesProduct`

Esto es una señal clara de que la frontera de módulos no está cerrada.

### Conclusión
**Riverpod está bien usado para datos simples, pero todavía no modela correctamente los flujos de negocio.** Hoy ayuda a cargar datos; todavía no estructura realmente el dominio.

---

## 2.4 Widgets compartidos: existen, pero no están gobernando la UI

### Activos compartidos detectados
- `ModulePage`
- `PageHeader`
- `EmptyStateCard` / `ErrorCard`
- `AppPageLayout`
- `ResponsiveLayout`
- `ui_custom.dart` (`KPICard`, `StatusBadge`, `SectionHeader`, `DataTableShell`)

### Problema principal
La capa compartida no se aplica de forma consistente. Hay una convivencia de:

- componentes compartidos reales
- componentes privados repetidos dentro de cada page
- estilos hardcodeados dentro de páginas

### Caso concreto
`ui_custom.dart` pretende ser una base reutilizable, pero su adopción es parcial y el grep muestra que sigue muy pegado a páginas específicas. No parece una librería establecida como lenguaje visual dominante del proyecto.

### Síntomas
- headers hechos ad-hoc en varias pantallas
- cards KPI con variaciones manuales
- tablas con shells distintos según módulo
- filtros/search bars casi idénticos implementados varias veces
- dialogs formularios repetidos con layout muy parecido

### Conclusión
La capa shared **existe más como toolkit opcional que como contrato de composición**. Eso explica por qué la UI tiende a duplicarse.

---

## 2.5 Theming, tokens y responsive: buena intención, cumplimiento incompleto

### Lo bueno
El proyecto sí tiene base de diseño:

- `AppTheme.light`
- `AppTokens`
- breakpoints compartidos
- helpers como `adaptivePadding()` y `kpiCrossAxisCount()`

Eso es exactamente lo correcto para un backoffice Flutter.

### Lo malo
En `CLAUDE.md` se establece una regla explícita:

> Hardcode colors — do not. Use `AppTokens` or `Theme.of(context)`.

El repo no cumple esa regla de forma consistente.

### Evidencia
Se detectaron **165 ocurrencias de `Color(0x...)`** en `lib/`.

Los casos más notorios están en:
- `sales_page.dart`
- `quotation_create_page.dart`
- `quotations_page.dart`
- `app_shell.dart`
- `login_page.dart`
- `dashboard_page.dart`
- varios widgets shared

### Qué implica eso
- el sistema visual no está centralizado de verdad
- la personalización futura de tema será cara
- dark mode sería difícil
- consistencia de contraste/semántica de color queda a criterio de cada screen

### Responsive
La capa responsive existe, pero también está incompleta en adopción:

- algunas pantallas usan `ResponsiveLayout` y `adaptivePadding`
- otras resuelven el layout manualmente dentro del widget
- los split panes y grids están armados screen por screen

### Conclusión
**Hay tokens, pero no hay enforcement.** El diseño system está empezado, no consolidado.

---

## 2.6 Deuda técnica y duplicación: hoy ya es visible

### 2.6.1 Duplicación de UX y layout
`sales_page.dart` y `quotation_create_page.dart` son el ejemplo más claro.

Comparten casi el mismo patrón de:
- buscador
- grid de productos
- panel lateral
- lista de líneas
- controles de cantidad
- totales
- botones de acción

Pero están implementados como dos pantallas separadas con mucha lógica y UI copiada/adaptada.

Eso indica que hace falta una capa tipo:
- `catalog_selection_panel`
- `document_cart_panel`
- `line_item_controls`
- `document_totals_summary`
- `draft_document_controller`

### 2.6.2 Duplicación de acceso a categorías/productos
`sales_repository.dart` e `inventory_repository.dart` comparten patrones muy parecidos para:
- categorías
- productos
- `_currentBranchId()`
- mapping de category names

No necesariamente hay que unificar todo en un mega-repo, pero sí falta una pieza compartida para consultas base o mappers del catálogo.

### 2.6.3 Duplicación de `_currentBranchId()`
El método `_currentBranchId()` aparece repetido en múltiples repositories.

Eso genera:
- código repetido
- más superficie de cambio
- poca estandarización de errores cuando falta branch actual

### 2.6.4 Duplicación de patterns CRUD
Muchos módulos repiten el mismo ciclo:
- provider de repo
- provider de lista
- buscador local en page
- dialog de crear/editar
- invalidate al guardar

Eso ya pide una mini infraestructura reusable o un patrón más declarativo.

---

## 2.7 Fronteras entre módulos: aquí está uno de los riesgos más serios

### Hallazgo clave
El módulo de cotizaciones no está realmente aislado. Depende de ventas para piezas centrales:

- modelos (`SalesProduct`, `SaleCartItem`)
- providers (`salesProductsProvider`, `salesClientsProvider`, `salesSearchProvider`)

### Por qué importa
Esto parece práctico hoy, pero trae varios problemas:

1. Cambios en ventas pueden romper cotizaciones sin querer.
2. Cotizaciones queda impedido de evolucionar con reglas propias.
3. Se mezcla el concepto de “documento comercial” con un módulo particular.
4. Se complica la introducción futura de proformas, pedidos o borradores de factura.

### Recomendación estructural
Extraer un subdominio o capa compartida de `commercial_documents` / `catalog_selection` / `document_drafts` sería mucho más sano que seguir cruzando features directamente.

### Otro hallazgo
La seguridad de cotizaciones en `supabase/sql-next/20260410_quotations_schema.sql` está todavía en modo provisional:

```sql
CREATE POLICY "Allow all for authenticated users on quotations" ... USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated users on quotation_items" ... USING (true) WITH CHECK (true);
```

Eso contradice la línea general del esquema principal, que sí usa `has_branch_access(...)` y helpers por rol.

### Conclusión
**Las fronteras de módulos todavía no están endurecidas**, especialmente en nuevas funcionalidades.

---

## 2.8 Placeholder code / foundation code / implementación provisional

No encontré pantallas llenas de `TODO` o placeholders burdos, lo cual es positivo. Pero sí encontré varias señales de código todavía provisional o “MVP fuerte”:

### Cotizaciones
`quotations_repository.dart` contiene señales claras:

- `itemsCount: 0` con comentario de que “podría contarse luego”
- `receipt_type: 'consumidor_final'` al convertir a venta, mientras el enum/documentación usan `consumer_final`
- `description: 'Producto de cotización'` en `sale_items` en vez de snapshot completo del producto
- `_generateCode()` y `_generateSaleNumber()` basados en timestamp simple
- policies DB abiertas a cualquier usuario autenticado

### Riesgo
No es código falso, pero sí es código **de fundación provisional**, todavía no alineado con los requerimientos fuertes de `flutter_shop.md`.

### Impacto
Estas piezas van a crear deuda si se consideran “ya resueltas” y se siguen construyendo features encima sin endurecerlas.

---

## 2.9 Repositorios: correctos para fetch CRUD, todavía demasiado anchos para escalar

### Lo bueno
Los repositories son legibles y directos. Para un proyecto de negocio con Supabase, eso tiene valor.

### Lo malo
Varios repositories están empezando a mezclar demasiadas responsabilidades:

- acceso a datos
- orquestación de transacciones de negocio
- armado de payloads
- cálculos
- decisiones operativas
- integración con impresión

Ejemplo fuerte: `sales_repository.dart` (**510 líneas**)

Ahí conviven:
- fetch de catálogos
- checkout de venta
- pagos
- actualización de balance cliente
- preparación de impresión
- queries posteriores de branch/client/cashier/items/payments

### Riesgo
Cuando entren más reglas fiscales, descuentos, mixed payments, anulaciones, reimpresiones y e-CF-ready flows, ese repository se volverá un cuello de botella.

### Recomendación
Separar gradualmente en piezas tipo:
- `sales_catalog_repository`
- `sales_checkout_service`
- `sales_print_service`
- `sales_read_repository`

No hace falta hacer eso de golpe, pero el repo actual ya muestra presión.

---

## 2.10 Estado de calidad estática y testing

### `flutter analyze`
Resultado observado:
- **17 issues**
- sin fallos catastróficos, pero sí con señales de disciplina relajada

Incluye:
- imports sin usar
- APIs deprecated (`withOpacity`, `DropdownButtonFormField.value`)
- dependencia no declarada para test (`shared_preferences` en `test/widget_test.dart`)

### Tests
Solo vi un test base:
- `test/widget_test.dart`

Es esencialmente un smoke test de login screen.

### Lectura arquitectónica
El problema no es solo que “faltan tests”. El problema es que la estructura actual de varias pantallas **dificulta escribirlos**:

- demasiado estado dentro del widget
- poca separación entre decisiones y rendering
- dialogs/forms incrustados
- lógica de negocio repartida entre UI y repository

### Conclusión
La cobertura de calidad hoy es **insuficiente para una fase de escalado funcional**.

---

## 3. Evaluación por áreas

## 3.1 Feature organization
**Estado:** aceptable  
**Madurez:** media-baja

Fortaleza:
- estructura por feature clara

Debilidad:
- features demasiado monolíticas internamente

Diagnóstico:
- bien para navegar el repo
- todavía mal para escalar equipos/casos de uso

---

## 3.2 Routing
**Estado:** bueno para MVP  
**Madurez:** media

Fortaleza:
- `ShellRoute`
- redirects auth
- paths consistentes

Debilidad:
- permisos finos aún no integrados de forma robusta al routing
- router centralizado manualmente

---

## 3.3 Riverpod / providers
**Estado:** correcto  
**Madurez:** media-baja

Fortaleza:
- patrón homogéneo
- simple de entender

Debilidad:
- demasiada lógica sigue en widgets
- providers no representan bien flujos complejos

---

## 3.4 Shared widgets
**Estado:** parcial  
**Madurez:** media-baja

Fortaleza:
- sí existen primitivas compartidas

Debilidad:
- no gobiernan la construcción de pantallas
- siguen coexistiendo demasiadas implementaciones ad-hoc

---

## 3.5 Theming / tokens / responsive
**Estado:** base buena, cumplimiento incompleto  
**Madurez:** media-baja

Fortaleza:
- diseño system iniciado

Debilidad:
- hardcoded colors y estilos aún dominan varias pantallas
- responsive no está suficientemente sistematizado

---

## 3.6 Technical debt y duplicación
**Estado:** visible y creciendo  
**Madurez:** baja

Fortaleza:
- deuda todavía controlable

Debilidad:
- ya hay duplicación estructural, no solo cosmética

---

## 3.7 Module boundaries
**Estado:** frágil  
**Madurez:** baja

Fortaleza:
- la intención modular existe

Debilidad:
- features nuevas se apoyan demasiado en otras features concretas
- falta una capa shared/domain para conceptos transversales

---

## 3.8 Readiness for scaling
**Estado:** parcial  
**Madurez:** media-baja

El proyecto está listo para:
- seguir agregando módulos parecidos a los actuales
- iterar UX del backoffice
- cubrir operaciones básicas

El proyecto **no está listo aún** para escalar con bajo costo en:
- permisos finos por acción
- fiscalidad fuerte
- flujos documentales complejos
- borradores persistentes
- offline futuro
- múltiples tipos de documento con lógica compartida
- crecimiento sostenido sin aumento fuerte de duplicación

---

## 4. Riesgos de mantenibilidad más importantes

### Riesgo 1 — crecimiento por páginas gigantes
Cada nueva capacidad se está resolviendo agregando más código a pages grandes. Eso ralentiza cualquier cambio transversal.

### Riesgo 2 — duplicación silenciosa entre módulos comerciales
Ventas y cotizaciones ya están mostrando el patrón. Si luego llegan pedidos/proformas/devoluciones, el costo se va a multiplicar.

### Riesgo 3 — sistema visual no consolidado
Mientras existan tantos `Color(0x...)` y estilos ad-hoc, cualquier refresh visual será caro y propenso a inconsistencias.

### Riesgo 4 — seguridad y permisos desalineados entre frontend y DB
La documentación pide endurecimiento de roles/permisos, pero nuevas piezas como cotizaciones todavía usan políticas muy abiertas.

### Riesgo 5 — repositories demasiado cargados
Cuando entren reglas fiscales y operativas más serias, varios repositories actuales van a explotar en complejidad.

### Riesgo 6 — testing insuficiente
Sin refactor de estructura, la falta de tests se volverá más grave a medida que aumente la superficie funcional.

---

## 5. Juicio específico sobre cotizaciones

El módulo de cotizaciones **sirve como foundation funcional**, pero todavía no está a la altura de los requerimientos descritos en `flutter_shop.md` y `docs/quotations/*`.

### Lo que sí logra
- lista y métricas básicas
- creación de cotización simple
- conversión a venta
- base de esquema en DB

### Lo que lo hace débil hoy
- fuerte dependencia del módulo de ventas
- seguridad SQL provisional
- snapshots/document metadata insuficientes
- generación de códigos simplificada
- falta de capa propia para draft/document lifecycle
- UX y lógica muy parecidas a venta directa, no a un flujo comercial autónomo

### Veredicto
No lo catalogaría como placeholder, pero sí como **módulo fundacional aún no endurecido**.

---

## 6. Recomendaciones estructurales concretas

## 6.1 Extraer subcomponentes y controllers por feature
Prioridad alta para:
- `sales_page.dart`
- `quotation_create_page.dart`
- `inventory_page.dart`
- `users_page.dart`
- `branches_page.dart`
- `settings_page.dart`

Meta:
- que ninguna screen principal concentre todo el flujo
- mover formularios, grids, summary panels y dialogs a widgets privados/compartidos
- mover estado complejo a controllers/providers dedicados

---

## 6.2 Crear una capa transversal para documentos comerciales
En vez de hacer que cotizaciones dependa de ventas, extraer una base común para:

- selección de productos
- líneas de documento
- totales
- selección de cliente
- notas
- borradores

Nombre posible:
- `shared/commercial/`
- `features/commercial_documents/`
- `lib/domain/documents/` (si quieren ir un poco más formal)

---

## 6.3 Endurecer tokens y theme como contrato real
Acciones concretas:
- reducir hardcoded `Color(0x...)`
- crear semantic colors en `AppTokens`
- mover estilos recurrentes a theme extensions o helpers consistentes
- estandarizar chips, search bars, cards KPI, table shells, empty states

Objetivo: que el diseño no dependa de cada pantalla.

---

## 6.4 Introducir controllers/use-cases en flujos complejos
Especialmente para:
- ventas
- cotizaciones
- caja/cierre
- usuarios/sucursales

No hace falta “clean architecture académica”, pero sí separar:
- fetch
- mutación
- cálculos
- validaciones
- side effects

---

## 6.5 Unificar acceso a contexto de sucursal
Extraer un helper o servicio común para:
- branch context actual
- validación de branch activa
- errores estándar
- refresh branch-scoped

Hoy está funcional, pero repetido.

---

## 6.6 Alinear DB nueva con el estándar de seguridad existente
Cotizaciones no debería quedarse con RLS abierta tipo `USING (true)`.

Debe alinearse al patrón del esquema principal:
- `has_branch_access(...)`
- helpers por rol
- permisos por acción cuando madure el modelo

---

## 6.7 Subir el piso de calidad automática
Mínimo recomendado:
- dejar `flutter analyze` limpio
- corregir deprecations actuales
- agregar tests de repositories críticos y controllers
- mantener smoke tests de navegación/auth

---

## 7. Plan priorizado de limpieza técnica

## Prioridad 1 — Contener el crecimiento del caos visual y estructural
**Objetivo:** bajar el costo de cambio inmediato

1. Refactorizar las 4 pantallas más grandes en subwidgets y secciones internas:
   - `settings_page.dart`
   - `branches_page.dart`
   - `users_page.dart`
   - `inventory_page.dart`
2. Extraer patrones repetidos:
   - search/filter bars
   - summary/KPI cards
   - dialog forms base
   - data table wrappers
3. Limpiar `flutter analyze` a cero.

**Impacto:** alto  
**Esfuerzo:** medio

---

## Prioridad 2 — Endurecer fronteras de dominio
**Objetivo:** evitar que nuevos módulos sigan naciendo por copia/pega

1. Separar cotizaciones de ventas.
2. Extraer modelos/flows compartidos de documento comercial.
3. Evitar que una feature consuma providers de otra feature como dependencia primaria.
4. Reducir lógica de negocio dentro de widgets stateful.

**Impacto:** muy alto  
**Esfuerzo:** medio-alto

---

## Prioridad 3 — Consolidar design system real
**Objetivo:** que `AppTokens` deje de ser decorativo

1. Reemplazar hardcoded colors más repetidos por semantic tokens.
2. Estandarizar cards, chips, paneles laterales y headers.
3. Definir componentes oficiales para grids, summaries y estados vacíos.
4. Revisar `ui_custom.dart` y decidir: o se adopta en serio, o se simplifica/reorganiza.

**Impacto:** alto  
**Esfuerzo:** medio

---

## Prioridad 4 — Preparar escalado de negocio real
**Objetivo:** que ventas/cotizaciones/fiscal no colapsen al crecer

1. Partir repositories anchos en servicios/casos de uso más específicos.
2. Introducir controllers/notifiers para flujos complejos.
3. Preparar snapshots de cliente/producto/documento donde el requerimiento lo pide.
4. Alinear conversión de cotización → venta con enums y reglas reales del esquema.

**Impacto:** muy alto  
**Esfuerzo:** alto

---

## Prioridad 5 — Endurecer seguridad y consistencia backend/frontend
**Objetivo:** evitar deuda peligrosa de permisos

1. Reemplazar políticas permisivas de cotizaciones por RLS alineada al esquema principal.
2. Diseñar la transición de roles simples a permisos finos.
3. Mantener consistencia entre navegación visible, autorización real y políticas SQL.

**Impacto:** muy alto  
**Esfuerzo:** medio-alto

---

## Prioridad 6 — Subir testabilidad antes de seguir expandiendo features
**Objetivo:** bajar riesgo de regresión

1. Añadir tests unitarios a lógica de cálculo/documentos.
2. Añadir tests de repository para flows críticos.
3. Añadir smoke/integration tests mínimos de router + auth + shell.
4. Sólo después de eso seguir expandiendo módulos grandes.

**Impacto:** alto  
**Esfuerzo:** medio

---

## Conclusión final

`flutter_shop+` **no está mal estructurado**. De hecho, tiene una base bastante sensata para un producto de operación comercial multi-sucursal. El problema es otro: **la app ya empezó a crecer más rápido que su disciplina interna**.

Si se sigue agregando funcionalidad al ritmo actual sin limpiar:
- aumentará la duplicación
- las pages se volverán más frágiles
- cotizaciones/ventas se mezclarán cada vez más
- theming y reusable UI perderán consistencia
- el costo de introducir permisos fuertes, fiscalidad seria y nuevos tipos de documento va a subir mucho

Si se hace ahora una limpieza arquitectónica enfocada, el proyecto todavía está en una zona muy recuperable.

**Mi juicio final:**
- **Base:** buena
- **Mantenibilidad actual:** media-baja
- **Escalabilidad real:** parcial
- **Momento ideal para refactor:** ahora, antes de meter más capas de negocio encima
