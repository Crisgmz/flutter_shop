# Quotations / Cotizaciones Foundation

Primera base seria en-repo para el módulo de **Cotizaciones** dentro de `flutter_shop+`.

## Qué queda instalado

- Ruta y entrada de navegación: `/cotizaciones`
- Pantalla propia dentro del shell del app
- Modelos base de dominio para cotización y pipeline
- Repositorio/contrato que arma una fundación segura sin escribir en DB
- Uso de contexto real cuando existe:
  - clientes activos de la sucursal
  - productos activos de la sucursal
- Presentación pensada para evolucionar a:
  - composer de cotización
  - quote → sale
  - impresión / envío
  - persistencia Supabase

## Decisión de alcance

Todavía no se agregan tablas nuevas ni migraciones. Eso fue intencional.

La meta de esta entrega es dejar a **Cotizaciones** como módulo real del producto, visible en navegación, con lenguaje operativo, estados, pipeline y contrato de datos; pero sin inventar persistencia apresurada ni tocar la base actual sin diseño final.

## Modelo funcional inicial

Estados previstos:
- `draft`
- `shared`
- `underReview`
- `approved`
- `rejected`
- `expired`

Campos funcionales ya reflejados por el modelo:
- código comercial (`COT-001`, etc.)
- cliente
- estado
- fecha de creación
- vigencia
- total
- cantidad de líneas
- owner comercial
- canal
- prioridad
- resumen

## Siguiente fase recomendada

### Backend
Crear:
- `quotations`
- `quotation_items`

Campos mínimos sugeridos para `quotations`:
- `id`
- `branch_id`
- `quote_number`
- `client_id`
- `status`
- `valid_until`
- `subtotal`
- `tax_amount`
- `total`
- `notes`
- `sales_owner_id` o equivalente
- `source_channel`
- `priority`
- `converted_sale_id` nullable
- auditoría (`created_at`, `created_by`, `updated_at`, `updated_by`)

Campos mínimos sugeridos para `quotation_items`:
- `id`
- `quotation_id`
- `product_id` nullable
- `description`
- `quantity`
- `unit_price`
- `tax_rate`
- `discount_amount`
- `line_total`
- `sort_order`

### Flujo
1. crear borrador
2. agregar líneas desde catálogo o manuales
3. enviar / compartir
4. negociar / revisar
5. aprobar
6. convertir a venta
7. imprimir / reenviar / versionar

## Alineación con el roadmap del repo

Esto encaja con:
- mejora de UI/UX
- futuro bridge con impresión (`PrintDocumentType.quote` ya existe)
- ventas/cobros
- futura trazabilidad fiscal/comercial

## Regla de implementación

Cuando se haga la persistencia real:
1. leer `CLAUDE.md`
2. leer `DATABASE.md`
3. revisar SQL actual en `supabase/sql/`
4. mantener el flujo quote → sale desacoplado y limpio
