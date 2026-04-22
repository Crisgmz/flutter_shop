# Audit UI/UX y coherencia de producto — flutter_shop+

Fecha: 2026-04-10  
Enfoque: UI/UX, estructura de producto, densidad visual, navegación y sensación de sistema real  
Referencia revisada: `CLAUDE.md`, `DATABASE.md`, `flutter_shop.md`, módulos principales en `lib/features/*`, y documentación/estructura de `mangospos` como benchmark de producto más completo.

---

## Resumen ejecutivo

`flutter_shop+` **ya no se siente como demo vacía**. Tiene base real de producto: shell con navegación por roles, módulo de ventas conectado, dashboard/reports alimentados por vistas reales, inventario/clientes/compras con CRUD funcional, y una intención clara de evolucionar hacia un POS/admin serio para RD.

Pero hoy el producto todavía se percibe como **mitad sistema operativo real / mitad primera capa UI**.

La principal debilidad no es “que falten módulos”, sino que **la experiencia entre módulos no parece diseñada como un solo producto**. Hay dos lenguajes conviviendo:

1. **Backoffice modular relativamente consistente** (`ModulePage`, tablas, filtros, KPIs, dialogs).
2. **Flujos core hechos aparte** (`Ventas`, `Nueva Cotización`) con un layout más custom, más suelto, menos sistémico.

Eso rompe coherencia. En una app seria tipo POS/admin, el usuario debería sentir que:
- todo pertenece al mismo sistema,
- la navegación responde a una jerarquía clara,
- los módulos críticos tienen más profundidad que los auxiliares,
- y ninguna pantalla “importante” se ve más inmadura que una tabla secundaria.

Hoy pasa lo contrario en varios puntos: **Ventas y Cotizaciones, que deberían ser el corazón comercial, todavía se sienten menos sólidas estructuralmente que Inventario o Clientes**.

---

## Veredicto general

### Lo mejor del proyecto hoy

- Existe una **base real de arquitectura feature-first** y eso ya ordena el producto mejor que muchos POS improvisados.
- El shell tiene **control por rol**, secciones de navegación y contexto por sucursal.
- `Dashboard`, `Reports`, `Inventory`, `Clients`, `Purchases` ya trabajan sobre datos reales o estructuras realistas.
- Hay intención explícita de producto serio en documentos como `flutter_shop.md`, `DATABASE.md`, `docs/quotations/*` y `docs/facturacion/*`.
- La app ya piensa en temas de negocio correctos: multi-sucursal, NCF, crédito, impresión, cobranzas, permisos.

### Lo más flojo hoy

- **Coherencia visual y estructural insuficiente** entre módulos.
- **Ventas/POS demasiado básico** para el peso que tiene dentro del producto.
- **Cotizaciones todavía no alcanza el estándar de módulo comercial serio** que los propios documentos del repo describen.
- El shell superior y la navegación se sienten **funcionales pero genéricos**, sin el nivel de contexto operativo que esperas en una app de caja/admin.
- Hay varios detalles que delatan “primera iteración” o “placeholder operativo”, aunque los datos sean reales.

### Diagnóstico corto

Si hoy alguien compara `flutter_shop+` con la expectativa de un POS/admin serio, diría:

> “La base está bien encaminada, pero el producto todavía no tiene una capa de diseño y priorización suficientemente madura en los módulos que más venden el sistema.”

---

## 1) Dashboard

Archivos observados:
- `lib/features/dashboard/presentation/dashboard_page.dart`
- `lib/features/dashboard/data/dashboard_repository.dart`

### Qué está bien

- El dashboard sí consume datos reales desde vistas (`dashboard_kpis_by_branch`, `sales_monthly_summary`, `latest_sales_view`).
- Tiene buena estructura base: KPIs, gráfica, últimas ventas.
- La jerarquía visual es clara y entendible.
- La lectura general es limpia; no está recargado.
- La tabla de últimas ventas ya se siente como panel administrativo real, no mock puro.

### Qué está débil

- El dashboard se siente **demasiado genérico** para ser home de un sistema serio.
- Muestra resumen, pero no da suficiente sensación de “centro operativo”.
- Falta un bloque de acciones rápidas relevantes: abrir venta, crear cotización, revisar crédito, revisar bajo stock, etc.
- No hay un bloque fuerte de “alertas operativas” ni “cosas que requieren atención hoy”.
- La gráfica es funcional, pero visualmente parece **hecha a medida de primera iteración**, menos refinada que el resto del backoffice.
- El encabezado de la gráfica dice “Ventas por Mes / Resumen anual” incluso cuando existe selector semanal; eso baja credibilidad.

### Qué se siente fake/placeholder

- No porque use mocks, sino porque **la composición se siente demasiado escolar**: KPIs + chart + últimas ventas, sin narrativa operativa.
- En un producto serio, el dashboard debería explicar el negocio del día, no solo listar métricas.

### Recomendación

Convertir el dashboard en un **home operacional**, no solo estadístico. Debería priorizar:
- estado de caja,
- ventas hoy,
- cuentas por cobrar vencidas o por vencer,
- cotizaciones abiertas/por vencer,
- inventario crítico,
- últimas ventas/acciones rápidas.

---

## 2) Shell / Sidebar / Topbar

Archivos observados:
- `lib/features/shell/presentation/app_shell.dart`
- `lib/features/shell/presentation/shell_nav_items.dart`
- `lib/shared/widgets/app_page_layout.dart`
- `lib/shared/widgets/module_page.dart`

### Qué está bien

- Buena separación entre shell y módulos.
- La navegación por secciones (`Operación`, `Catálogo`, `Control`, `Administración`) está bien planteada.
- Hay filtrado por rol y eso le da estructura de producto real.
- El sidebar oscuro funciona visualmente y da identidad básica.
- El `AppPageLayout` ya distingue módulos `wide` vs `standard`, lo cual es correcto para un admin serio.

### Qué está débil

- La topbar está **subutilizada**: casi todo el peso visual se va a selector de sucursal + usuario, pero se pierde el contexto de página.
- El `title` del topbar prácticamente no aporta experiencia; visualmente queda vacío.
- No hay breadcrumbs, estado de sesión, shortcuts, búsqueda global ni contexto de módulo.
- El sidebar todavía se ve “v1” literal y conceptualmente. De hecho el badge `Shell v1` es una pista de prototipo que conviene remover.
- La navegación mezcla módulos de muy distinto peso sin dejar clara su prioridad operacional.
- “Ventas” y “Cotizaciones” no reciben protagonismo suficiente dentro de la experiencia general.

### Problemas de producto/arquitectura de navegación

- `Compras` vive dentro de `Catálogo`, pero por negocio se siente más cerca de operación/abastecimiento que de catálogo puro.
- `Cierre de Caja` como etiqueta de nav limita la percepción del módulo; operativamente es más que “cerrar”, es caja/sesión/arqueo.
- El sistema todavía no se siente como un producto con “núcleo comercial” y “núcleo administrativo” claramente separados.

### Qué se siente fake/placeholder

- `Shell v1` en UI.
- Topbar que parece marco técnico más que capa de producto.
- Ausencia de estado operativo persistente (caja abierta/cerrada, sucursal activa más visible, usuario/rol más contextual).

### Recomendación

Rediseñar shell con estos objetivos:
- topbar con título real + contexto de módulo,
- mejor jerarquía de navegación,
- indicadores operativos persistentes,
- y un lenguaje de producto más “serio admin/POS” y menos “layout base”.

---

## 3) POS / Ventas

Archivos observados:
- `lib/features/sales/presentation/sales_page.dart`
- `lib/features/sales/data/sales_repository.dart` (referencia funcional vía rutas halladas)

### Qué está bien

- Ya existe flujo real de carrito y checkout.
- La pantalla es rápida de entender.
- El grid de productos es limpio y utilitario.
- El panel derecho de carrito es claro.
- La venta a crédito está contemplada, lo cual es importante para el tipo de producto.
- El módulo ya se siente más real que un mock visual simple.

### Qué está débil

Este módulo todavía está **demasiado corto** para ser el corazón del sistema.

- Visualmente parece más una “pantalla de catálogo + carrito” que un POS serio.
- Falta profundidad transaccional visible:
  - métodos de pago reales en UI,
  - desglose de cobro,
  - cambio,
  - descuentos,
  - edición de precios/cantidades con más control,
  - validaciones mejor expuestas,
  - feedback post-venta más robusto que un alert dialog.
- No se siente integrado con caja, impresión y comprobantes de manera visible.
- No existe una experiencia fuerte de selección de cliente, documento fiscal y contexto de crédito.
- La densidad visual es mejorable: hoy el módulo gasta mucho espacio en chrome y relativamente poco en información de trabajo.
- No hay sensación de flujo profesional “izquierda catálogo / derecha ticket / abajo pagos / arriba contexto”.

### Problemas UX importantes

- En desktop, la estructura general es correcta, pero aún se siente de MVP.
- En mobile, el flujo depende de alternar hacia carrito; funciona, pero no parece pensado fino para operación sostenida.
- El diseño está mucho más hardcodeado que el resto del sistema: colores específicos, cards custom, header propio, etc. Eso rompe consistencia con `ModulePage` y el lenguaje compartido.

### Comparación contra expectativa seria / mango como referencia

Frente a la ambición que se ve en `mangospos`, aquí falta:
- un POS con mayor peso operacional,
- más estados de interacción,
- más contexto por cliente/documento/pago,
- y un layout que se sienta herramienta de caja, no solo formulario bonito.

### Qué se siente fake/placeholder

- No porque el checkout no funcione, sino porque la UI **todavía no comunica robustez de POS**.
- El mensaje de éxito en dialog simple no está a la altura del flujo principal del producto.
- La ausencia de una capa visible de comprobante/pago/imprimir deja el cierre comercial algo “abstracto”.

### Recomendación

Este módulo debe ser prioridad máxima de rediseño. El objetivo no es “hacerlo más lindo”, sino **hacer que se vea y se sienta como el motor comercial del sistema**.

---

## 4) Cotizaciones

Archivos observados:
- `lib/features/quotations/presentation/quotations_page.dart`
- `lib/features/quotations/presentation/quotation_create_page.dart`
- `lib/features/quotations/data/quotations_repository.dart`
- `docs/quotations/QUOTATIONS_FOUNDATION.md`
- `docs/quotations/REQUERIMIENTOS_COTIZACIONES.md`

### Qué está bien

- Ya existe módulo visible y conectado.
- La idea de métricas + pipeline + listado reciente es correcta.
- La intención comercial del módulo está mucho mejor pensada a nivel de documentos que a nivel visual.
- Tener `Nueva cotización` separada ya es mejor que esconderlo en un modal improvisado.

### Qué está débil

Aquí hay un gap fuerte entre **lo que el repo dice que Cotizaciones debe ser** y lo que la UI actual realmente expresa.

- La pantalla principal todavía es superficial: métricas, pipeline y tabla/listado, pero con poca densidad operativa real.
- No hay filtros serios, búsqueda, agrupación, seguimiento, prioridad, owner, canal, vigencia accionable, etc.
- El pipeline es demasiado esquemático para un módulo comercial serio.
- La tabla no muestra suficiente información para gestionar cotizaciones como pipeline real.
- La creación de cotización se siente demasiado parecida a una venta simplificada, no a un documento comercial robusto.
- Falta vigencia editable real, condiciones comerciales, notas visibles al cliente, canal, responsable, contexto de aprobación.

### Problemas graves de percepción

- En mobile, `QuotationCreatePage` deja la propuesta en una situación débil: se ve catálogo, pero el detalle lateral desaparece y queda solo un FAB de guardar. Eso hace que la experiencia móvil sea poco confiable para un flujo importante.
- La conversión a venta en `quotations_repository.dart` usa decisiones muy crudas (`receipt_type` fijo, descripción `'Producto de cotización'`). Eso no solo es técnico: **también afecta la credibilidad del módulo**.

### Qué se siente fake/placeholder

- El módulo se vende como pipeline comercial serio, pero todavía se comporta visualmente como una primera base.
- El documento `QUOTATIONS_FOUNDATION.md` dice explícitamente que la fundación original era sin tocar DB todavía, pero el repo ya avanzó a escrituras reales. A nivel producto, eso deja sensación de evolución apresurada y no totalmente alineada.
- El create flow parece “clon de ventas adaptado”, no módulo diseñado desde cero para cotizaciones.

### Recomendación

Cotizaciones debe rediseñarse como **módulo comercial de verdad**, no como preventa ligera. Debe quedar entre POS y CRM liviano.

---

## 5) Inventario

Archivos observados:
- `lib/features/inventory/presentation/inventory_page.dart`
- `lib/features/inventory/data/inventory_repository.dart`

### Qué está bien

- Es uno de los módulos más sólidos hoy.
- Usa `ModulePage` y se integra bien al lenguaje backoffice.
- Tiene filtros claros, tabla razonable, cards móviles, CRUD funcional.
- La información mostrada es la correcta para una primera versión seria.
- La relación entre búsqueda, categoría, bajo stock y acciones es clara.

### Qué está débil

- Sigue siendo más “catálogo de productos con stock” que “módulo de inventario”.
- Falta profundidad operativa: movimientos, ajustes, historial, transferencias, entradas/salidas, kardex.
- El formulario de producto es útil, pero todavía denso de forma básica; no tiene secciones ni mejor agrupación visual.
- La tabla funciona, pero aún no se siente optimizada para gestión intensiva.

### Qué se siente fake/placeholder

- Menos fake que otros módulos. Aquí el problema no es demo, sino **alcance todavía corto**.
- Se llama “Inventario”, pero la experiencia actual representa más bien “Productos + stock actual”.

### Recomendación

No necesita reinvención visual completa. Necesita:
- fortalecer profundidad funcional,
- mejorar el formulario,
- y preparar subflujos de inventario serio.

---

## 6) Compras

Archivos observados:
- `lib/features/purchases/presentation/purchases_page.dart`
- `lib/features/purchases/data/purchases_repository.dart`

### Qué está bien

- La estructura general es correcta.
- El módulo sí se siente administrativo y no decorativo.
- El dialog de nueva compra ya cubre un flujo real mínimo.
- Los KPIs y la tabla aportan claridad.

### Qué está débil

- La entrada principal al módulo es demasiado plana: lista + búsqueda + KPIs.
- “Nueva compra” se resuelve dentro de dialog amplio; para algo operativo puede quedarse corto si el flujo crece.
- Falta vista de detalle, estados más accionables, historial del proveedor, impacto en stock, y lectura de cuentas por pagar.
- Si el producto quiere verse serio, compras debe respirar más como “abastecimiento/control”, menos como CRUD largo en modal.

### Qué se siente fake/placeholder

- No fake por datos, pero sí por **superficie de producto**: parece resuelto para cumplir funcionalmente, no para operar cómodamente en volumen.

### Recomendación

Mantener la base, pero mover el rediseño de Compras después de POS/Cotizaciones/Shell. Aquí la arquitectura visual base ya aguanta una segunda iteración.

---

## 7) Clientes

Archivos observados:
- `lib/features/clients/presentation/clients_page.dart`
- `lib/features/clients/data/clients_repository.dart`

### Qué está bien

- Es de los módulos más coherentes del backoffice.
- La búsqueda y filtro de inactivos están bien.
- Los KPIs son simples pero útiles.
- La tabla tiene la información correcta para una fase temprana.
- El alta/edición vía dialog es funcional y razonable.

### Qué está débil

- El módulo todavía se siente “maestro de clientes” y no “relación comercial con clientes”.
- No hay vistas de detalle, historial de compras, balance con contexto, crédito, últimas cotizaciones, actividad reciente.
- El formulario resuelve mucho en vertical simple; podría agruparse mejor para dar sensación de ficha seria.
- El balance por cobrar está presente, pero la pantalla no se articula aún con cobranzas/cotizaciones/ventas como producto conectado.

### Qué se siente fake/placeholder

- Menos fake que Cotizaciones o POS. Aquí más bien se siente **demasiado básico**.
- El sistema ya apunta a crédito y cuentas por cobrar, pero la experiencia de cliente todavía no comunica ese nivel.

### Recomendación

No rehacer primero. Mejor evolucionarlo a:
- ficha de cliente,
- contexto comercial,
- relación con ventas/cobros/cotizaciones.

---

## 8) Reportes

Archivos observados:
- `lib/features/reports/presentation/reports_page.dart`
- `lib/features/reports/data/reports_repository.dart`

### Qué está bien

- Consume vistas reales y eso ya lo pone por encima de una pantalla demo.
- El selector semanal/mensual es correcto.
- Los bloques cubren áreas lógicas: ventas, cuentas por cobrar, bajo stock, NCF.
- El módulo es útil como tablero operativo rápido.

### Qué está débil

- A nivel de UX, todavía se siente más como “agrupación de widgets” que como módulo de reportes serio.
- Falta profundidad analítica, filtros más ricos, exportación, drill-down, comparativas y consistencia visual entre bloques.
- La visualización principal de ventas mediante barras/progress simplifica demasiado el valor del módulo.
- La composición no comunica prioridades ni relaciones entre reportes.

### Qué se siente fake/placeholder

- No por datos, sino porque el módulo parece **versión 1 de reporting interno**, no un centro de análisis.

### Recomendación

Después de consolidar dashboard y módulos core, reportes debe tomar un lenguaje propio más analítico: filtros arriba, resumen ejecutivo, bloques comparativos y accesos a listados/exportación.

---

## 9) Consistencia visual y de sistema

### Problema principal

Hay una inconsistencia fuerte entre:
- módulos construidos con `ModulePage` + `DataTableShell` + lenguaje de tokens,
- y módulos hechos con UI custom más libre (`Ventas`, `Nueva Cotización`, partes del dashboard).

Eso produce:
- headers distintos,
- densidades distintas,
- radios/bordes/colores distintos,
- diferente nivel de refinamiento,
- y sensación de que varias pantallas vienen de etapas o manos distintas.

### Ejemplos claros

- `SalesPage` no usa `ModulePage`; arma su propio header y layout.
- `QuotationCreatePage` tampoco sigue el patrón del sistema.
- En shell/topbar hay bastante hardcode visual fuera de una capa de componentes más madura.
- Algunos módulos usan cards simples; otros usan shells o tablas encapsuladas; otros mezclan ambos.

### Resultado

El producto no termina de sentirse una sola suite.

---

## 10) Densidad, spacing y jerarquía

### Lo bueno

- En general la app evita verse abarrotada.
- Hay uso correcto de espacios 12/16/24 en muchas pantallas.
- La lectura básica es limpia.

### El problema

Para un sistema administrativo/POS serio, varias pantallas están **demasiado aireadas para la cantidad de valor que muestran**.

- POS desperdicia espacio útil en vez de aumentar contexto transaccional.
- Cotizaciones muestra poca información por pantalla para lo que debería administrar.
- Dashboard tiene buen aire, pero poca densidad operativa.
- Diálogos de inventario/clientes/compras cumplen, pero podrían agruparse mejor para reducir fatiga visual.

### Recomendación

No hace falta “apretar todo”. Hace falta **más densidad inteligente**:
- más información útil por viewport,
- mejores secciones,
- menos espacios muertos en módulos críticos,
- y más jerarquía visual entre info primaria y secundaria.

---

## 11) Navegación y coherencia del flujo

### Qué está bien

- La navegación principal es entendible.
- Las rutas están claras y el `ShellRoute` está bien planteado.
- El producto no se siente caótico a nivel técnico.

### Qué está mal desde UX/producto

- Falta una narrativa clara entre módulos core:
  - venta,
  - cotización,
  - cliente,
  - cobro,
  - caja,
  - reportes.
- La app tiene piezas del flujo comercial, pero todavía no las expresa como un sistema conectado.
- La navegación lateral es buena para “entrar a módulos”, pero pobre para “moverse dentro de una operación”.

### Ejemplo

Si un usuario crea una cotización, aprueba, convierte a venta, cobra, reimprime y revisa cliente/cxc, la app todavía no cuenta esa historia con claridad.

---

## 12) Coherencia general de producto

### Punto fuerte

La dirección de producto sí existe. Eso se nota mucho en documentación y módulos base.

### Punto débil

La capa visual todavía no traduce esa dirección con suficiente rigor.

El repo habla de:
- facturación seria,
- cotizaciones serias,
- impresión A4/80mm,
- roles/permisos,
- fiscal RD,
- multi-sucursal,
- cuentas por cobrar,
- producto admin robusto.

Pero la experiencia visible aún proyecta más bien:
- “admin modular en progreso”,
- con un POS funcional,
- y cotizaciones todavía en transición.

### Conclusión de coherencia

El producto **sí tiene alma de sistema serio**, pero todavía no la comunica de forma homogénea en la UI.

---

## Qué está bien de verdad

1. **Arquitectura base bien encaminada.**  
   El orden por features y repositorios permite crecer sin colapsar.

2. **Backoffice base ya usable.**  
   Inventario, clientes, compras y reportes ya tienen suficiente estructura para no sentirse humo.

3. **Pensamiento de producto correcto.**  
   La documentación apunta a decisiones maduras: fiscalidad RD, multi-sucursal, permisos, impresión, trazabilidad.

4. **El sistema ya opera con datos reales en varias áreas.**  
   Eso hace que el problema actual sea de UX/profundidad/coherencia, no de puro maquillaje.

---

## Qué está flojo de verdad

1. **POS todavía no tiene presencia de módulo principal.**
2. **Cotizaciones todavía no parece un módulo comercial serio.**
3. **Shell/topbar no terminan de articular el producto.**
4. **Hay inconsistencia visual entre módulos clave.**
5. **Dashboard/reportes no cuentan suficiente historia operativa.**

---

## Qué se siente fake / placeholder / “todavía no llega”

- Badge visible `Shell v1` en sidebar.
- Topbar con poco contexto real.
- `QuotationCreatePage` muy cerca de un clon simplificado de ventas.
- Conversión de cotización a venta con defaults técnicos poco creíbles (`receipt_type` fijo, descripción genérica).
- Dashboard demasiado plantillado para el nivel de producto que el repo promete.
- Reportes útiles pero todavía con sensación de versión 1 interna.
- Cierres de flujo importantes resueltos con dialogs/snackbars demasiado básicos.

---

## Prioridades de rediseño

### Prioridad 1 — POS / Ventas
Porque es el corazón del producto. Si este módulo no se siente premium-operativo, el sistema entero pierde credibilidad.

### Prioridad 2 — Shell / Sidebar / Topbar
Porque es el marco mental de toda la suite. Si el shell se siente genérico, todos los módulos pierden fuerza.

### Prioridad 3 — Cotizaciones
Porque es la pieza donde más se nota la distancia entre visión documental y experiencia real.

### Prioridad 4 — Dashboard
Porque debe convertirse en centro operativo real y no solo resumen básico.

### Prioridad 5 — Reports
Porque hoy sirve, pero todavía no parece módulo de análisis serio.

### Prioridad 6 — Clientes
Porque ya funciona, pero necesita evolucionar a ficha comercial conectada.

### Prioridad 7 — Compras
Porque la base es correcta; no urge antes que POS/shell/cotizaciones.

### Prioridad 8 — Inventario
Porque es de lo más sólido hoy; conviene expandirlo funcionalmente más que rehacerlo visualmente primero.

---

## Orden recomendado de rediseño accionable

## Fase 1 — Unificar lenguaje de producto
Objetivo: que toda la app parezca una sola suite.

Hacer primero:
- redefinir shell/topbar/sidebar,
- consolidar headers, acciones, contenedores, tablas, filtros,
- fijar reglas de densidad y spacing por tipo de pantalla,
- normalizar componentes compartidos para módulos core.

## Fase 2 — Rehacer POS como módulo flagship
Objetivo: que Ventas se sienta inmediatamente como el centro del sistema.

Debe incluir:
- layout más robusto,
- mejor jerarquía catálogo/ticket/pago,
- mejor tratamiento de cliente/comprobante/pago,
- feedback de cierre más profesional,
- conexión visual con caja e impresión.

## Fase 3 — Rehacer Cotizaciones como módulo comercial serio
Objetivo: pasar de preventa ligera a pipeline comercial real.

Debe incluir:
- listado serio con filtros,
- detalle de documento,
- create/edit con vigencia, términos y contexto comercial,
- mejor lectura de estado/pipeline,
- mejor enlace con cliente y venta.

## Fase 4 — Dashboard operativo
Objetivo: home con sentido diario.

Debe incluir:
- alertas,
- quick actions,
- estado de caja,
- pendientes comerciales,
- bajo stock,
- vencimientos y actividad reciente.

## Fase 5 — Reports y vista analítica
Objetivo: pasar de panel de widgets a módulo de consulta gerencial/operativa.

## Fase 6 — Fichas conectadas (Clientes / Compras / Inventario)
Objetivo: profundizar los módulos ya sólidos y conectarlos mejor entre sí.

---

## Recomendación final

`flutter_shop+` **sí tiene base para verse como un producto serio**. No está lejos por arquitectura; está lejos sobre todo por **coherencia, priorización visual y profundidad en los módulos que más importan**.

La mejor decisión ahora no es seguir agregando pantallas sueltas. La mejor decisión es:

1. **consolidar el lenguaje del sistema**,
2. **subir POS a nivel flagship**,
3. **subir Cotizaciones a nivel comercial serio**,
4. y luego reorganizar Dashboard/Reports alrededor de ese núcleo.

Si eso se hace en ese orden, el producto dejará de sentirse “admin prometedor con partes fuertes” y empezará a sentirse como una **suite comercial/POS real, consistente y vendible**.

---

## Nota breve sobre comparación con mangospos

Tomando `mangospos` como referencia útil, la mayor diferencia no es solo cantidad de pantallas. Es que `mangospos` proyecta una ambición de producto más explícita en sus flujos core y en su mapa funcional, mientras que `flutter_shop+` hoy todavía proyecta más claridad técnica que madurez de experiencia.

La buena noticia es que `flutter_shop+` ya tiene mejor base para ordenar esa experiencia sin tener que rehacer el proyecto completo. Lo que falta es una segunda capa de diseño/producto más disciplinada.
