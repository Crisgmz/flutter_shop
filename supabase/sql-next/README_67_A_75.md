# Migraciones 67 → 75

Correcciones de fondo agrupadas por tema. Se ejecutan **a mano en el SQL Editor
de Supabase**, en el orden de este documento (que es el orden alfabético de los
nombres de archivo). Todas son **idempotentes**: se pueden correr dos veces sin
romper nada.

Prerrequisito: la última migración aplicada debe ser
`20260717_66_tax_inclusive_pricing.sql`.

| # | Archivo | Obligatoria | Tema |
|---|---------|-------------|------|
| 67 | `20260814_67_reports_profit_permission.sql` | Sí | Permiso "Ver ganancia" |
| 68 | `20260814_68_services_skip_inventory.sql` | Sí | Servicios no mueven stock |
| 69 | `20260814_69_returns_cash_and_imeis.sql` | Sí | Devoluciones ↔ caja, método de reembolso, IMEIs |
| 70 | `20260814_70_imei_restore_on_void_and_edit.sql` | Sí | IMEIs vuelven al inventario al anular/editar |
| 71 | `20260814_71_sales_history_entries_view.sql` | Sí | Vista unificada ventas + devoluciones |
| 72 | `20260814_72_quotation_receipt_type.sql` | Sí | Tipo de comprobante en cotizaciones |
| 73 | `20260814_73_optional_purchases_due_date_cleanup.sql` | **No — opcional** | Saneo de cuentas por pagar |
| 74 | `20260814_74_optional_closeout_profit_no_tax.sql` | **No — opcional** | "Beneficios" del cierre sin ITBIS |
| 75 | `20260814_75_checkout_respects_track_inventory.sql` | Sí | El checkout respeta `track_inventory` |

> **69 debe correrse antes que 70 y 71.** La 70 usa el helper
> `restore_product_imeis` (lo re-declara igual, así que también sobrevive sola)
> y la 71 lee `returns.cash_session_id` y `returns.refund_method`, que crea la 69.

> **75 cierra lo que abre la 68**, así que va después de ella. El orden
> alfabético ya lo garantiza; las dos opcionales (73 y 74) están en el medio pero
> son independientes, se pueden saltar sin afectar a la 75.

---

## 67 — Permiso "Ver ganancia" (`reports.profit`)

Inserta el permiso `reports.profit` en `public.permissions` y lo concede a
`admin`, `supervisor` y `accountant` en `public.role_permissions`.

**`cashier` queda fuera a propósito.** Así el cajero no ve el margen por
defecto, y el switch por usuario (`public.user_permissions`) es lo que se lo
habilita caso por caso.

Las asignaciones usan `on conflict … do nothing`: si un admin revocó el permiso
a mano, volver a correr la migración **no** se lo devuelve.

**Si no la corres:** el código Dart que pregunta por `reports.profit` no
encuentra el permiso y — según cómo resuelva el default — o esconde la ganancia
a todo el mundo, o la muestra a todo el mundo. La pantalla de permisos por
empleado tampoco lista el switch.

---

## 68 — Servicios sin inventario

Corrige el bug de fondo: un producto con `is_service = true` **sí** descontaba
stock, porque los triggers de stock nunca miraron ese flag. Resultado típico:
"Mano de obra" con stock −47 y apareciendo en el reporte de bajo stock.

- `create or replace` de los 4 triggers de stock con el mismo cuerpo, agregando
  a cada `update public.products` los predicados
  `coalesce(is_service,false) = false and coalesce(track_inventory,true) = true`:
  `apply_sale_item_stock`, `apply_purchase_item_stock`,
  `apply_return_item_stock`, `apply_inventory_movement_stock`.
  Un servicio simplemente no mueve stock, en ninguna dirección. No lanza error.
- Backfill: a todo servicio se le apaga `track_inventory` y se le pone
  `stock = 0`, `min_stock = 0`.
- `public.inventory_low_stock_view` y `public.report_inventory_status_view`
  excluyen servicios y productos sin control de inventario.

No crea columnas: `products.is_service` y `products.track_inventory` ya existen
desde `20260421_structural_backoffice_foundation.sql`.

**Si no la corres:** los servicios siguen acumulando stock negativo, el reporte
de bajo stock se llena de basura y la validación de "stock insuficiente" puede
bloquear la venta de un servicio.

> Esta migración deja el stock quieto también para `track_inventory = false`,
> pero la validación del checkout todavía no lo sabía. Eso lo cierra la **75**,
> que hay que correr junto con esta.

---

## 69 — Devoluciones ligadas a caja

- `returns.cash_session_id uuid` + FK compuesta
  `(cash_session_id, branch_id) → cash_sessions(id, branch_id)` (tolera null,
  MATCH SIMPLE) + índice parcial.
- `returns.refund_method text not null default 'cash'`. Es **text**, no el enum
  `payment_method`, para admitir valores como `credit_note` sin tocar el enum.
- `return_items.imeis text[] not null default '{}'`.
- `public.restore_product_imeis(uuid, uuid, text[])` — helper que devuelve
  IMEIs a `products.imeis` haciendo unión sin duplicados y normalizando
  (trim, descarta vacíos).
- `public.process_return(...)` con **firma nueva de 7 parámetros**. Conserva
  todo lo que ya hacía (numeración NC-xxxxx, fórmula de ITBIS incluido/excluido,
  ajuste de `clients.balance_due` en ventas a crédito) y agrega: guardar la
  sesión de caja y el método de reembolso, resolver la sesión abierta cuando
  `p_cash_session_id` viene null, y devolver los IMEIs al producto.
- **Validación de IMEIs (el RPC no confía en el cliente).** Antes de restaurar,
  cada línea se valida: la cantidad de IMEIs no puede superar la cantidad
  devuelta, y — si se pasó `p_original_sale_id` — cada IMEI debe existir en
  `sale_items.imeis` de ESA venta. Sin esto, una devolución parcial mal armada
  (cantidad 1 con tres IMEIs) devolvía al inventario tres equipos que siguen
  vendidos. Si algo no cuadra la devolución completa aborta con un mensaje
  claro; todo va en una transacción, así que no queda nada a medias.
- **Bug corregido de paso:** el prefijo del número de devolución se leía con
  `from public.app_settings where id = 1`, que en multi-empresa devolvía la fila
  de OTRA empresa. Ahora se resuelve por compañía de la sucursal
  (`join public.branches b on b.company_id = s.company_id where b.id = v_branch_id`).

**No inserta en `cash_register_movements`, y es intencional.** El "Esperado en
caja" del cierre se calcula en Dart leyendo la tabla `returns`. Si además se
insertara un movimiento de caja, el mismo reembolso se descontaría dos veces.
Una sola fuente de verdad.

**Si no la corres:** las devoluciones siguen sin dejar rastro en la caja (el
turno siempre cierra con faltante), y los IMEIs devueltos no vuelven al
inventario. Además la 71 **falla**, porque la vista referencia columnas que no
existen.

---

## 70 — IMEIs: devolver el equipo al inventario

El modelo de IMEI es destructivo: `products.imeis` es un `text[]`, vender saca
el IMEI del array y lo **copia** a `sale_items.imeis`. Esa copia es la única
que queda, así que cualquier borrado de `sale_items` destruye el último rastro
del equipo.

- Índices GIN `sale_items_imeis_gin` y `return_items_imeis_gin` — permiten
  buscar la factura por IMEI (`where imeis @> array['359…']`).
- `void_sale_with_stock_return`: devuelve los IMEIs al producto **antes** del
  `delete from sale_items`.
- `edit_sale_transactional`: devuelve los IMEIs de las líneas viejas **antes**
  del delete, y las líneas nuevas ahora aceptan `imeis` en `p_items` (se
  guardan en `sale_items` y se vuelven a sacar del inventario). Si el cliente
  Dart no manda `imeis` al editar, los equipos quedan **disponibles** en el
  producto y la venta editada sin IMEIs; se emite un `raise notice` y el JSON
  de respuesta trae `imeis_restored` / `imeis_kept`.

Se eligió esa alternativa porque perder el IMEI es irrecuperable, mientras que
"equipo disponible de más" es una inconsistencia visible y corregible a mano.

La matemática de ITBIS incluido/excluido de la migración 66 queda **intacta**.

**Si no la corres:** anular o editar una venta con IMEIs borra los equipos del
sistema para siempre, y no hay índice para buscar factura por IMEI.

---

## 71 — Vista `public.sales_history_entries`

`union all` de `sales` y `returns` con columnas idénticas, para que el historial
muestre ambas cosas en un solo stream.

Las filas de devolución traen `subtotal`, `tax_amount`, `total_amount` y
`paid_amount` **negados**, de modo que sumar la columna ya da el neto: Total y
Ganancia salen en negativo sin lógica extra en Dart. `balance_due` es 0,
`due_date` / `receipt_type` / `ncf` son null, `status` es `'returned'`.

**Seguridad:** `security_invoker = true` → la vista se evalúa con los permisos
de quien consulta, así que hereda las policies RLS de `sales` y de `returns`
(ambas filtran por `public.has_branch_access(branch_id)`). No expone datos de
otra sucursal ni de otra empresa.

**Si no la corres:** el historial sigue ignorando las devoluciones; el total del
día no baja y la ganancia queda inflada.

---

## 72 — Cotización: tipo de comprobante

`quotations.receipt_type public.receipt_type not null default 'consumer_final'`
(el mismo enum de `sales`).

**No se agrega columna `ncf` a `quotations` y la cotización no consume secuencia
NCF.** El NCF es un correlativo fiscal ante la DGII: si una cotización tomara un
número y luego nunca se facturara — que es el caso normal — quedaría un hueco en
la correlatividad y el 607 saldría con números faltantes. El NCF se asigna al
**convertir** la cotización en venta. La cotización solo declara la intención.

**Si no la corres:** la cotización no puede declarar que la factura llevará
crédito fiscal, y al convertirla siempre sale como consumidor final.

---

## 73 — OPCIONAL — Saneo de cuentas por pagar

Las compras creadas con el bug tienen `due_date = purchase_date`: el proveedor
no tenía plazo pactado (`payment_terms_days = 0`) y la app le sumó 0 días, así
que aparecen vencidas desde el día uno.

Limpia `due_date` solo donde se dan las tres condiciones a la vez: proveedor con
`payment_terms_days = 0`, `due_date = purchase_date`, y `balance_due > 0`.

**Límite de la heurística:** si alguna compra vencía legítimamente el mismo día
contra un proveedor sin plazo pactado, pierde su fecha de vencimiento. No hay
forma de distinguirla del bug mirando los datos. El archivo trae un `SELECT` de
diagnóstico en su cabecera para revisar qué filas se verían afectadas antes de
correr el `UPDATE`. Ese `SELECT` muestra el proveedor con
`coalesce(s.trade_name, s.legal_name)`: `public.suppliers` no tiene columna
`name`.

**Si no la corres:** no se rompe nada — solo quedan compras marcadas como
vencidas que en realidad nunca tuvieron plazo.

---

## 74 — OPCIONAL — "Beneficios" del cierre del día sin ITBIS

Dos arreglos en `public.dashboard_v2_closeout`, los dos visibles en
**Cierre del día** (`/panel/cierre`):

1. **"Ventas totales (sin impuestos)" salía en RD$ 0.00.** Se calculaba con
   `taxable_amount + exempt_amount`, dos columnas que el checkout nunca llena.
   Ahora usa esas columnas cuando traen algo y, si no, cae a `subtotal`.

2. **"Beneficios" incluía el ITBIS.** Se calculaba como `total_amount − COGS`.
   El ITBIS no es ganancia: es un impuesto que se le cobra al cliente y se le
   paga a la DGII. Ahora es `subtotal − COGS`, que además coincide con la
   columna "Ganancia" del Historial de ventas y con el bloque nuevo
   "Venta por caja" de esa misma pantalla.

**Efecto visible: el número de "Beneficios" BAJA**, exactamente el ITBIS de las
ventas del día. Ejemplo: venta de 23,600 (subtotal 20,000 + ITBIS 3,600) con
costo 10,000 → antes 13,600, ahora 10,000.

**Si no la corres:** no se rompe nada, pero "Beneficios" y el bloque
"Venta por caja" van a mostrar cifras distintas en la misma pantalla, y
"Ventas totales (sin impuestos)" sigue en RD$ 0.00.

El resto de la función queda idéntica a `20260509_12_closeout_returns_fix.sql`.

---

## 75 — El checkout respeta `track_inventory`

La 68 apagó el movimiento de stock para `is_service OR NOT track_inventory`, y
el Dart adoptó la misma regla (`tracksStock = !isService && trackInventory`).
Pero la validación de "stock insuficiente" del checkout se quedó atrás: seguía
excluyendo solo `is_service`.

El caso que rompe: un producto con `is_service = false` y
`track_inventory = false` — configuración alcanzable desde el import de Excel,
columna `rastrear_inventario` — por ejemplo "Recarga telefónica", con stock 0 y
`app_settings.inv_disallow_no_stock` activado. Tras la 68 ninguna compra vuelve
a subirle stock, así que se queda en 0 para siempre. El POS lo deja agregar al
carrito y el Dart no lo bloquea, pero el RPC lo rechaza: **ese producto no se
puede facturar nunca**.

Se reescriben `public.checkout_sale_transactional` y
`public.hold_sale_transactional` como copias fieles de sus versiones vigentes en
`20260717_66_tax_inclusive_pricing.sql`, con **solo dos cambios** cada una:

1. el `select` del producto agrega `p.track_inventory`;
2. la validación de stock agrega `and coalesce(v_product.track_inventory, true)`.

Es exactamente el predicado que la 66 ya le había puesto a
`edit_sale_transactional` (y que la 70 conserva) — o sea que esto era una
inconsistencia entre las tres funciones, no un cambio de criterio.

Todo lo demás queda intacto: matemática de ITBIS incluido/excluido, absorción de
la cuenta guardada, asignación de NCF, manejo de IMEIs, pagos divididos y cambio
por sobrepago. Las firmas no cambian, así que basta `create or replace`.

**Si no la corres:** cualquier producto con `track_inventory = false` y stock 0
queda infacturable en instalaciones con "no vender sin stock" activado, con un
error de "Stock insuficiente" que el usuario no puede resolver de ninguna manera
(la compra ya no le sube el stock).
