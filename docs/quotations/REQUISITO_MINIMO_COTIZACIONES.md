# REQUISITO_MINIMO_COTIZACIONES.md

## Alcance mínimo obligatorio del módulo de Cotizaciones

A partir de este punto, el módulo de **Cotizaciones** en `flutter_shop+` debe cumplir, como mínimo, con estas capacidades funcionales obligatorias:

### 1. Crear cotizaciones
El usuario debe poder crear una nueva cotización con:
- cliente
- productos o líneas
- cantidades
- precios
- impuestos o descuentos si aplican
- fecha de creación
- fecha de vencimiento

### 2. Ver cotizaciones
El usuario debe poder:
- listar cotizaciones
- abrir una cotización existente
- revisar sus datos principales
- ver claramente su estado
- ver claramente su fecha de vencimiento

### 3. Editar cotizaciones
El usuario debe poder editar una cotización mientras siga en un estado válido para edición.

Como mínimo debe poder modificar:
- cliente
- líneas/productos
- cantidades
- precios
- observaciones
- fecha de vencimiento

### 4. Borrar cotizaciones
El usuario debe poder borrar cotizaciones solo cuando su estado lo permita.

Regla mínima:
- una cotización ya convertida a venta no debe poder borrarse como si no hubiera existido

### 5. Fecha de vencimiento
Toda cotización debe tener una fecha de vencimiento.

El sistema debe:
- permitir seleccionarla al crear
- permitir editarla cuando corresponda
- mostrarla claramente
- reflejar cuando la cotización ya está vencida

### 6. Convertir cotización a venta
El usuario debe poder convertir una cotización en venta.

La conversión debe trasladar correctamente, como mínimo:
- cliente
- líneas o productos
- cantidades
- precios
- impuestos y descuentos si aplican

La conversión no debe depender de hacks client-side frágiles ni dejar datos inconsistentes.

---

## Estados mínimos recomendados
Para soportar este alcance, el módulo debe contemplar al menos estos estados:
- borrador
- activa o enviada
- vencida
- convertida

---

## Reglas mínimas de consistencia
- una cotización convertida no debe poder comportarse como una cotización editable normal
- una cotización vencida debe identificarse claramente
- la conversión a venta debe preservar la integridad de los datos
- crear, editar, borrar y convertir deben respetar reglas de estado

---

## Fuera de alcance por ahora
Estas capacidades son deseables, pero **no forman parte del mínimo obligatorio inmediato**:
- aprobaciones internas
- versionado avanzado
- seguimiento comercial
- impresión formal avanzada
- reportes complejos
- permisos finos por acción

---

## Resumen ejecutivo
El módulo de Cotizaciones no debe seguir creciendo como idea abstracta o pantalla decorativa.

Su alcance mínimo obligatorio ahora mismo es:
- **crear**
- **ver**
- **editar**
- **borrar**
- **manejar vencimiento**
- **convertir a venta**

Cualquier trabajo posterior debe respetar este núcleo como base funcional real.
