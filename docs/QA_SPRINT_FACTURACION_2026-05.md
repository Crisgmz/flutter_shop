# QA Checklist — Sprint Facturación 2026-05

Validación end-to-end de las 10 features entregadas. Usar **antes de
release** o tras tocar código relacionado. Tachar manualmente al ejecutar.

> **Preparación:** aplicar las migraciones SQL 5-14
> (`supabase/sql-next/20260509_08_*.sql` hasta `20260509_17_*.sql`) en
> Supabase. Crear al menos un cliente con `price_tier = 'tier_1'` y un
> producto con `price_tier_1` distinto al `price` base.

---

## F1 — Selector método de pago + COMPLETAR VENTA + confirmación

- [ ] En `/ventas` con carrito vacío, los 3 botones (Efectivo/Tarjeta/Transferencia) están visibles.
- [ ] Agregar productos: el botón **COMPLETAR VENTA** está deshabilitado (gris) hasta elegir método.
- [ ] Seleccionar "Efectivo" → el chip se pone saturado verde.
- [ ] Click **COMPLETAR VENTA** → aparece diálogo de confirmación con: artículos, método de pago, total destacado en verde.
- [ ] Botón Cancelar cierra el diálogo sin guardar.
- [ ] Botón Confirmar registra la venta. El carrito se limpia. Método de pago vuelve a `null`.
- [ ] La venta aparece en `/cobros` con `payment_method = cash`.
- [ ] Repetir con Tarjeta y Transferencia.

## F2 — Cotizaciones funcionales + auto-expirar

- [ ] En `/cotizaciones` crear una cotización con vencimiento futuro. Se guarda sin el error `column reference quotation_id is ambiguous`.
- [ ] Editar la misma cotización, cambiar items, guardar. Persiste.
- [ ] Convertir cotización a venta → aparece en `/ventas` y la cotización queda en estado `converted`.
- [ ] **Test de auto-expirar:** modificar manualmente en SQL una cotización con `valid_until` en el pasado y `status = 'sent'`. Refrescar `/cotizaciones`. Debería cambiar a `expired` automáticamente.

## F3 — Adición / sangría de efectivo en /caja

- [ ] Abrir caja con monto inicial (por ejemplo RD$ 1,000).
- [ ] Click **Agregar efectivo** → diálogo. Ingresar 500 + motivo → `Esperado` sube a RD$ 1,500.
- [ ] Click **Sangría** → ingresar 200 + motivo → `Esperado` baja a RD$ 1,300.
- [ ] En SQL: `select * from cash_register_movements where cash_session_id = ...` muestra ambos movimientos.
- [ ] Cerrar caja con monto real RD$ 1,300 → diferencia 0.

## F4 — Historial editable de pagos por cliente

- [ ] En `/clientes` click en ícono "Historial de pagos" (verde) de un cliente con pagos.
- [ ] El diálogo muestra cada pago con monto destacado, método, fecha, venta, referencia, notas.
- [ ] Total pagado coincide con la suma de las filas.
- [ ] Click **Editar** en un pago → cambia monto + método → guarda → se refleja.
- [ ] Click **Eliminar** → confirmación → el pago desaparece de la lista.
- [ ] En `/cobros` los abonos del cliente reflejan los cambios.

## F5 — Ver factura + reimprimir desde /cobros

- [ ] En `/cobros` cada fila tiene íconos **Ver factura** (visibility) y **Reimprimir** (print).
- [ ] Ver factura abre diálogo con cliente, fecha, NCF, total, pagado, balance.
- [ ] Botón Reimprimir dentro del diálogo abre `PrintReceiptDialog` con el mismo formato del POS.
- [ ] El ícono Reimprimir directo en la fila también abre `PrintReceiptDialog`.
- [ ] Si la venta no está `completed` el RPC retorna null → snackbar amistoso.

## F6 — Inventario: campos extra + historial

- [ ] En `/inventario` la tabla muestra columnas: **Producto · SKU · Referencia · Categoría · Costo · Precio · Stock · Estado · Acciones**.
- [ ] Costo aparece en gris muted.
- [ ] Click ícono **Historial** (reloj) en un producto.
- [ ] El diálogo muestra: entradas (compras, devoluciones, ajustes_in) en verde con flecha abajo; salidas (ventas, mermas) en rojo con flecha arriba.
- [ ] Header muestra **Entradas / Salidas / Stock actual**, suma manual coincide con stock.
- [ ] Cada fila tiene fecha, tipo, referencia (sale_number/purchase_number) y monto.

## F7 — Sellar Cierre Z fiscal

- [ ] En `/caja`, en la tabla de "Sesiones recientes", las sesiones CERRADAS tienen botón **Sellar Z**.
- [ ] Las sesiones ABIERTAS no muestran botón.
- [ ] Click **Sellar Z** → diálogo de confirmación.
- [ ] Confirmar → snackbar verde con UUID corto del cierre.
- [ ] En SQL `select * from fiscal_z_closures` aparece el registro con `payload` poblado (sales by receipt_type, payments by method, etc.).
- [ ] Intentar sellar de nuevo la misma sesión → error "Ya existe un cierre Z para esta sesión".

## F8 — Caja chica

- [ ] Sidebar muestra "Caja chica" en sección **Operación** (ícono `savings_outlined`).
- [ ] Sin sesión abierta, `/caja-chica` muestra tarjeta "Abrir caja chica".
- [ ] Abrir con RD$ 500. KPIs reflejan apertura 500, ingresos 0, gastos 0, esperado 500.
- [ ] **Gasto:** RD$ 50 categoría "Transporte" descripción "Taxi a banco" → esperado baja a 450.
- [ ] **Ingreso:** RD$ 100 → esperado sube a 550.
- [ ] **Reposición:** RD$ 200 → esperado sube a 750.
- [ ] Eliminar el gasto → esperado sube a 800.
- [ ] Cerrar con conteo RD$ 795 → diferencia -5 mostrada en rojo.
- [ ] Sesión cerrada aparece en "Sesiones recientes".

## F9 — Precio por cliente en POS

- [ ] Asignar a un cliente `price_tier = 'tier_1'` (vía SQL o edición de cliente).
- [ ] Asignar a un producto `price_tier_1 = 80` cuando `price = 100`.
- [ ] En POS sin cliente: agregar producto → línea con precio RD$ 100.
- [ ] Seleccionar el cliente tier_1 → la línea existente se re-precia automáticamente a RD$ 80. El total se ajusta.
- [ ] Cambiar a "Cliente General" → el precio vuelve a 100.
- [ ] Completar venta con tier_1 → la venta queda con monto basado en RD$ 80.

## F10 — Import/Export Excel de clientes

- [ ] En `/clientes` botón **Excel** con menú: Descargar plantilla / Exportar / Importar.
- [ ] **Plantilla:** descargar → abrir Excel. Verificar hoja "Instrucciones" + hoja "Clientes" con 18 columnas + 1 fila de ejemplo.
- [ ] **Exportar:** descargar → todas las filas de clientes activos están presentes con los valores correctos.
- [ ] **Importar nuevo:** editar la plantilla, agregar 2 filas nuevas con datos. Sin `documento_numero` coincidente → se crean 2 nuevos clientes. Confirmar el diálogo con conteo.
- [ ] **Importar update:** exportar todos, modificar el email/teléfono de uno con `documento_numero`, importar → se actualiza ese cliente, no se crea duplicado.
- [ ] **Importar con errores:** dejar `nombre` vacío en una fila → en el diálogo de confirmación aparece error con número de fila y mensaje.

---

## QA cross-feature

- [ ] **Multi-sucursal:** repetir F1 + F8 + F10 cambiando de sucursal en el header. Los datos NO se mezclan entre sucursales.
- [ ] **Roles:** entrar como `cashier` y verificar que NO pueda ver:
  - F7 sellar Z (no debería bloquear porque el RPC permite cualquier rol con `has_branch_access`, pero el botón debería estar visible — verificar comportamiento esperado).
  - Edición de pagos en F4 (cualquier rol puede ver historial, pero solo admin/supervisor edita per `payments_update` policy).
- [ ] **Permisos admin bypass:** entrar como `admin` y verificar que NUNCA aparece la pantalla "Acceso restringido para este rol".
- [ ] **Settings activo:** cambiar `currency_symbol` a `US$` en `/configuracion` → recargar `/ventas` → todos los precios cambian.
- [ ] **Selección de texto:** seleccionar cualquier texto en cualquier pantalla con drag — debe funcionar (Ctrl/Cmd+C copia).

---

## Sign-off

| Tester | Fecha | Pasa | Notas |
|---|---|---|---|
| | | ☐ | |

Una vez todos los items pasen, marcar Round 5 del sprint plan
(`docs/SPRINT_FACTURACION_2026-05.md`) como cerrado.
