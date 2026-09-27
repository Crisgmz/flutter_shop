import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import 'cash_register_providers.dart';

/// Filtro por caja: "Todas" (default) o una caja puntual. Lo usan el
/// Historial de ventas y el reporte de Ventas detalladas.
class CashRegisterFilterChip extends ConsumerWidget {
  const CashRegisterFilterChip({
    super.key,
    required this.selectedId,
    required this.onChanged,
  });

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registersAsync = ref.watch(cashRegistersProvider);
    final registers = registersAsync.valueOrNull ?? const [];
    final selected = registers
        .where((r) => r.id == selectedId)
        .map((r) => r.name)
        .firstOrNull;

    return PopupMenuButton<String?>(
      tooltip: 'Filtrar por caja',
      initialValue: selectedId,
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem<String?>(value: null, child: Text('Todas')),
        ...registers.map(
          (register) => PopupMenuItem<String?>(
            value: register.id,
            child: Text(register.name),
          ),
        ),
      ],
      // Contenedor plano (no un botón): el tap lo maneja el PopupMenuButton
      // que lo envuelve, y un botón anidado se lo comería.
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(
            color: selectedId == null ? AppTokens.border : AppTokens.primary,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.point_of_sale_outlined,
              size: 16,
              color: selectedId == null
                  ? AppTokens.secondaryForeground
                  : AppTokens.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Caja: ${selected ?? 'Todas'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selectedId == null
                    ? AppTokens.secondaryForeground
                    : AppTokens.primary,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppTokens.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
