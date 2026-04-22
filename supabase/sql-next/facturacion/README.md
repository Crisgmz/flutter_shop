# SQL de facturación

Esta carpeta agrupa los archivos SQL relacionados con facturación, comprobantes, NCF, e-CF readiness y endurecimiento fiscal.

## Convención sugerida

Usar nombres con prefijo de fecha o secuencia, por ejemplo:

- `20260410_facturacion_ncf_core.sql`
- `20260410_facturacion_snapshot_fiscal.sql`
- `20260410_facturacion_document_states.sql`

## Alcance esperado

Aquí deben vivir únicamente cambios SQL relacionados con:

- secuencias NCF
- reglas de comprobantes
- snapshot fiscal del cliente
- estados fiscales
- conversiones o RPC fiscales
- base para e-CF

No mezclar aquí SQL de caja, compras, inventario o UX.
