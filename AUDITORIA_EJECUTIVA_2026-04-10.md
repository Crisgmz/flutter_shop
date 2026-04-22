# Auditoría ejecutiva — `flutter_shop+`

Fecha: 2026-04-10

## Veredicto corto

`flutter_shop+` **ya no es una maqueta vacía**. Tiene una base real de producto: esquema MVP amplio en Supabase, multi-sucursal funcional, RLS, módulos conectados a datos reales, flujo base de ventas/compras/cobros/caja, reportes por vistas y una dirección técnica razonable para impresión y caja más seria.

Pero también hay que decirlo sin maquillaje: **todavía no es un POS/admin serio de producción**. Hoy está más cerca de un **MVP avanzado con buena intención arquitectónica** que de un sistema endurecido para operar negocio real sin sobresaltos.

Mi lectura honesta:
- **Base estructural:** bastante mejor de lo normal para esta etapa.
- **Producto operativo real:** parcial.
- **Seguridad/endurecimiento:** insuficiente en áreas críticas.
- **Fiscal / impresión / cotizaciones:** dirección correcta, implementación incompleta.
- **Capacidad de seguir construyendo encima:** sí, **pero ya no conviene seguir metiendo features sin primero cerrar cimientos**.

---

## 1) Qué está genuinamente sólido

### 1.1 Base de datos MVP bien pensada para la fase actual
Lo mejor del repo hoy probablemente está en Supabase:
- `01_schema.sql` es amplio y coherente para un MVP comercial.
- Hay modelo multi-sucursal real con `branches`, `users_branches`, `current_branch_id()` y `set_current_branch()`.
- Hay RLS por sucursal y rol en casi todas las tablas núcleo.
- Hay triggers de auditoría (`created_by`, `updated_by`, `updated_at`).
- Hay triggers de stock para compras y ventas.
- Hay vistas útiles para dashboard y reportes (`dashboard_kpis_by_branch`, `sales_monthly_summary`, `accounts_receivable_summary`, etc.).

Esto no es cosmético. Aquí sí hay trabajo serio.

### 1.2 Cobertura funcional del frontend ya es amplia
El repo no tiene solo 2-3 pantallas. Tiene un esqueleto grande:
- auth
- dashboard
- ventas
- inventario
- compras
- clientes
- proveedores
- cobros
- caja
- reportes
- impuestos
- sucursales
- usuarios
- configuración
- cotizaciones
- printing foundation

Además, la app está bien organizada en términos de estructura:
- feature-first
- Riverpod
- GoRouter
- shell común
- separación razonable entre data/presentation

Eso permite crecer sin que el repo colapse de inmediato.

### 1.3 La navegación y el shell ya tienen forma de producto real
La app ya tiene:
- layout consistente
- shell de navegación
- visibilidad de módulos por rol en UI
- selector de sucursal
- páginas con densidad razonable de producto

No es aún una UI sobresaliente, pero ya no está en estado “proyecto de laboratorio”.

### 1.4 Hay pensamiento estratégico correcto para impresión y caja
Dos señales buenas:
- `DATABASE.md` y la serie `sql-next/` muestran que ya se está pensando en caja en serio, no solo en “una tabla más”.
- La foundation de impresión está bien orientada: separar documento canónico, template y dispatch. Esa decisión es madura.

Esto importa porque evita meter lógica fiscal/print/agent directamente dentro de cada pantalla.

---

## 2) Qué hoy es más cosmético que robusto

### 2.1 Varias pantallas ya lucen “producto”, pero su backend sigue siendo liviano
Hay bastante UI que da sensación de sistema completo, pero por debajo sigue siendo una capa de CRUD + queries directas a Supabase.

Eso no es malo para MVP, pero sí hay que llamarlo por su nombre: **todavía falta capa transaccional fuerte y reglas de negocio duras**.

Ejemplos:
- ventas
- compras
- cobros
- usuarios/sucursales
- configuración fiscal básica

Funcionan como base, pero no como operación blindada.

### 2.2 Dashboard y reportes están bien para visibilidad, no para control ejecutivo serio todavía
Los reportes actuales sirven para operación inicial:
- ventas por periodo
- últimas ventas
- cuentas por cobrar
- low stock
- uso de NCF

Pero todavía no son un sistema de decisión gerencial completo. Falta:
- cierres confiables por caja/usuario/dispositivo
- conciliación fuerte
- trazabilidad profunda de anulaciones/reimpresiones
- pipeline comercial real para cotizaciones
- reportes fiscales listos para operación dominicana seria

### 2.3 El módulo de cotizaciones hoy se siente adelantado en UI, atrasado en rigor
Hay pantallas, modelos y flujo básico. Pero no está al nivel que el documento `flutter_shop.md` exige.

Hoy cotizaciones parece más un **primer aterrizaje visual/funcional** que un módulo comercial serio.

---

## 3) Qué está incompleto de verdad

### 3.1 Fiscal / NCF sigue incompleto en lo más importante
Esto el propio repo lo admite y el código lo confirma:
- no hay asignación automática seria de NCF al facturar
- no hay flujo fiscal endurecido
- no hay DGII certified flow
- no hay separación madura entre venta comercial y documento fiscal definitivo
- no hay snapshot fiscal/comercial fuerte del cliente al emitir documento

Para RD, esto no es opcional si el objetivo es “serio”.

### 3.2 Impresión todavía es foundation, no capability operativa
Sí existe una base útil:
- `PrintDocumentData`
- templates A4 / 80mm
- builder de payload
- preparación de print job desde ventas

Pero hoy **no existe impresión productiva real**:
- no hay transporte real a impresora
- no hay `print_jobs` persistidos
- no hay agent conectado
- no hay auditoría de reimpresiones
- no hay versionado de plantillas por sucursal

O sea: buena arquitectura inicial, cero cierre operativo.

### 3.3 Caja está usable como MVP simple, pero no lista para operación seria multi-caja
La caja actual sirve para abrir/cerrar sesión por sucursal y sumar pagos/gastos. Eso alcanza para demo o piloto controlado.

Pero no cubre la complejidad real que el propio proyecto ya reconoce:
- una sola caja abierta por sucursal
- no hay concepto real de ubicación de efectivo
- no hay ledger unificado de movimientos
- no hay transferencias entre ubicaciones
- no hay endurecimiento por dispositivo/caja física

La serie `sql-next` va en la dirección correcta, pero todavía no es runtime real.

### 3.4 Permisos finos todavía no existen
Hay roles globales (`admin`, `supervisor`, `cashier`, `accountant`) y visibilidad UI por rol. Bien.

Pero todavía no hay permisos finos por acción tipo:
- anular
- reimprimir
- cerrar caja
- tocar secuencias fiscales
- exportar fiscal
- aprobar descuentos
- convertir cotización

Eso es una limitación fuerte para un admin/POS serio.

### 3.5 Testing y endurecimiento técnico están muy por detrás
Estado observado:
- `flutter analyze` devuelve issues.
- `flutter test` falla.
- No hay suite real que cubra flujos críticos de negocio.

Hoy el sistema depende demasiado de que “el camino feliz” funcione.

---

## 4) Qué es directamente peligroso seguir arrastrando

Esta es la parte más importante del audit.

### 4.1 Cotizaciones está metido en app antes de estar resuelto en base y seguridad
El módulo de cotizaciones es hoy el punto más frágil del repo.

Problemas concretos detectados:
- La tabla de cotizaciones **no forma parte del flujo canónico** `supabase/sql/01-04`; vive en `supabase/sql-next/20260410_quotations_schema.sql`.
- El SQL usa `uuid_generate_v4()` pero el esquema base habilita `pgcrypto`, no `uuid-ossp`. Eso puede romper la migración si no se ajusta el entorno.
- Las políticas RLS actuales del draft de cotizaciones son literalmente `USING (true) WITH CHECK (true)` para todo usuario autenticado.
- Eso rompe el modelo de aislamiento por sucursal y es **demasiado permisivo**.
- `convertToSale()` usa `receipt_type: 'consumidor_final'`, pero el enum real del esquema es `consumer_final`. Eso apunta a fallo de runtime.
- La conversión usa descripciones genéricas (`'Producto de cotización'`) en vez de conservar información comercial correcta.

Conclusión: **cotizaciones no está listo para ser base confiable de negocio**. Está adelantado en superficie y atrasado en integridad.

### 4.2 Las operaciones críticas siguen sin transacción de negocio real
Ventas, compras, cobros y conversión de cotización hacen varias escrituras secuenciales desde cliente:
- crear cabecera
- insertar líneas
- insertar pagos
- actualizar balances
- recalcular cliente
- preparar impresión

Si algo falla a mitad, puedes quedar con estados parciales.

Eso es peligroso en:
- ventas
- cobros
- compras
- futuras anulaciones/fiscal

Para un POS serio, estas operaciones deben migrar a **RPCs/funciones transaccionales** o backend orchestration real.

### 4.3 No hay frenos duros suficientes en inventario/operación
Hay validación de stock en UI para ventas, pero no vi endurecimiento serio del lado de negocio para impedir escenarios como:
- stock negativo por carreras/concurrencia
- doble venta simultánea
- inconsistencias entre venta y pago
- ediciones posteriores que alteren sentido histórico

Mientras el frontend haga la mayor parte del control, el sistema sigue expuesto.

### 4.4 Hay credenciales/config embebidas de desarrollo en cliente
`lib/core/config/env.dart` incluye URL y publishable key por defecto.

Aunque sea “dev fallback”, en un producto que aspira a serio esto es mala señal operativa:
- mezcla entornos
- facilita errores humanos
- incentiva dependencia en un proyecto Supabase ya incrustado en app

No es el peor problema del repo, pero sí una deuda que conviene matar pronto.

### 4.5 El control de acceso visible en UI no equivale a control de negocio
La navegación oculta módulos por rol. Bien.

Pero eso **no reemplaza**:
- permisos finos reales
- enforcement consistente en DB
- funciones dedicadas para acciones críticas

Si el equipo sigue construyendo confiando demasiado en “la UI no muestra el botón”, se va a meter en problemas.

---

## 5) Diagnóstico por áreas

### Ventas
**Estado:** usable como MVP.

Bueno:
- carga de productos/clientes
- carrito funcional
- cálculo básico
- venta contado/crédito
- inserta `sales`, `sale_items`, `payments`
- prepara foundation de impresión

Débil:
- no transaccional
- sin asignación NCF seria
- sin snapshot fiscal del cliente
- sin reglas duras de descuento/aprobación/anulación
- sin impresión operativa real

### Compras
**Estado:** razonable como carga operativa inicial.

Bueno:
- crea compras y líneas
- actualiza costo del producto
- stock entra por trigger

Débil:
- sin capa transaccional fuerte
- sin flujo contable/fiscal serio
- sin trazabilidad avanzada

### Cobros
**Estado:** útil, pero todavía básico.

Bueno:
- registra abonos
- recalcula balance de venta
- recalcula balance del cliente

Débil:
- lógica repartida en cliente
- sin transacción fuerte
- sin políticas más finas de cobranza

### Caja
**Estado:** MVP funcional, no arquitectura definitiva.

Bueno:
- apertura/cierre
- cálculo de expected cash
- sesiones recientes

Débil:
- modelo simplificado por sucursal
- sin caja física/ubicación
- sin ledger formal

### Inventario
**Estado:** aceptable para comenzar.

Bueno:
- categorías/productos
- stock y min stock
- RLS por sucursal

Débil:
- sin movimientos de inventario como libro claro
- sin bloqueo serio de inconsistencias
- sin transferencias inter-sucursal

### Reportes / Dashboard
**Estado:** buen punto de partida.

Bueno:
- vistas ya pensadas en SQL
- información suficiente para un panel MVP

Débil:
- todavía no es capa de control ejecutivo confiable

### Cotizaciones
**Estado:** incompleto y hoy riesgoso.

Bueno:
- ya existe módulo y flujo inicial
- responde a necesidad real del producto

Débil:
- DB no integrada al flujo canónico
- seguridad mal resuelta
- conversión a venta rota o incompleta
- modelo aún superficial frente al requerimiento real

### Impresión
**Estado:** foundation prometedora, no feature terminada.

Bueno:
- abstracción correcta
- camino técnico razonable

Débil:
- sin dispatch real
- sin job persistence
- sin agent ni trazabilidad

---

## 6) Señales de calidad técnica observadas

### Positivas
- repo ya tiene tamaño y organización de producto real, no de experimento chico
- `DATABASE.md` está bien usado como referencia canónica
- el equipo está pensando roadmap, no solo tickets sueltos
- el enfoque multi-sucursal está metido desde base, no injertado tarde

### Negativas
- demasiada lógica crítica todavía en cliente
- testing muy débil
- cotizaciones aún no está al estándar del resto de la base
- algunas decisiones mezclan “current branch” con “default branch” de forma operativamente discutible
- el repo todavía tiene olor de “vamos agregando módulos” más rápido que “vamos endureciendo core”

---

## 7) Resultado ejecutivo: dónde está parado el producto

Si hoy hubiera que describirlo a alguien no técnico pero decisor:

`flutter_shop+` **sí tiene una base seria para convertirse en un POS/admin bueno**.
No está empezando de cero ni está perdido.

Pero también sería un error venderlo internamente como “casi listo”. No lo está.

Hoy el producto está en esta zona:
- **Arquitectura base:** 7/10 para MVP serio
- **Cobertura funcional visible:** 6.5/10
- **Robustez operativa real:** 4/10
- **Fiscal/printing readiness real:** 3.5/10
- **Seguridad/permisos/endurecimiento:** 4/10
- **Capacidad de escalar sin ordenar primero:** baja

La conclusión práctica:

**Sí conviene seguir construyendo sobre este repo, pero no conviene seguir agregando features “bonitas” primero.**
Si hacen eso, van a terminar con un sistema ancho pero blando.

---

## 8) Los 5 próximos sprints que más moverían el producto

## Sprint 1 — Endurecer el core transaccional del POS
Objetivo: dejar de depender de escrituras sueltas desde Flutter para flujos críticos.

Entregables:
- RPC/funciones transaccionales para:
  - crear venta completa
  - registrar cobro
  - crear compra
  - cerrar caja
- validaciones server-side de:
  - stock suficiente
  - balance correcto
  - sesión de caja válida
  - cliente requerido para crédito
- idempotencia mínima en operaciones sensibles

Impacto:
- baja el riesgo operativo más grande del repo
- convierte el sistema de “CRUD con lógica” a “producto con core confiable”

## Sprint 2 — Rehacer cotizaciones bien, no solo terminarlo
Objetivo: convertir cotizaciones en módulo serio y no en feature decorativa.

Entregables:
- integrar esquema de cotizaciones al camino canónico de migraciones
- corregir modelo, estados y seguridad por sucursal
- corregir conversión a venta
- guardar datos de líneas y documento de forma consistente
- preparar impresión A4/proforma desde la misma base documental

Impacto:
- cierra una necesidad clave del producto
- evita seguir apilando deuda sobre una implementación débil

## Sprint 3 — Cerrar fiscal legacy mínimo viable de verdad
Objetivo: que facturar con NCF deje de ser aspiración y pase a ser capability real.

Entregables:
- asignación automática de NCF por secuencia
- validación de disponibilidad y vigencia
- snapshot fiscal de cliente/documento al emitir
- separación clara entre venta y emisión fiscal
- trazabilidad de anulación/reimpresión/estado fiscal

Impacto:
- convierte ventas en un flujo dominicano real, no genérico
- habilita credibilidad comercial del sistema

## Sprint 4 — Llevar impresión de foundation a operación real
Objetivo: cerrar el loop documental del producto.

Entregables:
- persistencia de `print_jobs`
- rutas/plantillas por sucursal
- primer dispatch real (aunque sea PDF/browser para A4 y cola para thermal)
- reimpresión auditada
- plantillas mínimas buenas para venta y cotización

Impacto:
- hace que el sistema “salga del monitor” y se vuelva realmente utilizable
- además fuerza orden en documento, auditoría y estados

## Sprint 5 — Caja seria fase 1 + permisos finos
Objetivo: preparar operación real y control administrativo.

Entregables:
- adoptar fase 1 de `cash_locations` / `cash_movements`
- empezar a dejar de modelar caja solo por sucursal
- permisos finos por acción crítica
- restricciones de reimpresión, anulación, cierre y configuración fiscal

Impacto:
- sube mucho la credibilidad del sistema para negocio serio
- evita que el admin crezca sobre base demasiado blanda

---

## 9) Decisión recomendada

### Sí haría
- seguir usando este repo como base principal
- invertir los siguientes sprints en endurecer core, fiscal, cotizaciones e impresión
- usar `mangospos` como referencia de nivel, no como excusa para copiar sin adaptar

### No haría
- meter más módulos “visibles” antes de resolver transacciones, cotizaciones y fiscal
- dar por bueno el módulo de cotizaciones tal como está
- intentar llegar a “producción seria” sin RPCs/acciones transaccionales
- confiar en la UI como barrera principal de permisos

---

## 10) Conclusión final

`flutter_shop+` **sí tiene futuro técnico**.
La base no está mal. De hecho, para el punto en que va, está mejor pensada que muchos sistemas que ya se venden.

Pero ahora mismo el repo está entrando en una etapa delicada: ya tiene suficiente amplitud como para parecer más maduro de lo que realmente es.

La jugada correcta no es “seguir rellenando módulos”.
La jugada correcta es:

1. endurecer transacciones,
2. arreglar cotizaciones en serio,
3. cerrar fiscal legacy mínimo,
4. hacer impresión operativa,
5. madurar caja y permisos.

Si hacen eso, el proyecto puede dar un salto real hacia un POS/admin serio.
Si no, se va a volver un sistema vistoso pero frágil.
