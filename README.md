# Shop+ RD Flutter

Base Flutter para migrar tu sistema POS con backend en Supabase.

## Stack

- Flutter
- Riverpod (estado)
- go_router (navegación)
- supabase_flutter (auth + data)

## Ejecutar

Desde la raíz del repo:

```bash
cd flutter_shop+
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=TU_SUPABASE_URL \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=TU_SUPABASE_PUBLISHABLE_KEY
```

Si no pasas esas variables, la app abre una pantalla de setup para recordarte la configuración.

Importante:
- En Flutter usa solo `publishable` (o `anon`) key.
- Nunca uses `secret` key en cliente móvil/web.

## Estructura

```text
lib/
  app/                    # App principal y router
  core/                   # Config, tema, bootstrap
  features/
    auth/                 # Login y sesión
    shell/                # Navegación principal
    sales/ inventory/ ... # Módulos del POS
  shared/widgets/         # Componentes reutilizables
```

## Siguiente paso recomendado

Conectar cada módulo a tablas reales de Supabase:

1. `products`
2. `customers`
3. `suppliers`
4. `sales` y `sale_items`
5. `cash_sessions` y `payments`
