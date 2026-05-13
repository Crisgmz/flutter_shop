// Banner global que avisa cuando alguna secuencia NCF de la sucursal actual
// está por agotarse o vencida. Lee la vista `vw_ncf_stock`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../features/auth/presentation/auth_providers.dart';

class NcfStockRow {
  const NcfStockRow({
    required this.receiptType,
    required this.prefix,
    required this.remaining,
    required this.isLowStock,
    required this.isExpired,
  });

  final String receiptType;
  final String prefix;
  final int? remaining;
  final bool isLowStock;
  final bool isExpired;

  factory NcfStockRow.fromMap(Map<String, dynamic> m) {
    return NcfStockRow(
      receiptType: (m['receipt_type'] ?? '').toString(),
      prefix: (m['prefix'] ?? '').toString(),
      remaining: (m['remaining'] as num?)?.toInt(),
      isLowStock: m['is_low_stock'] == true,
      isExpired: m['is_expired'] == true,
    );
  }
}

/// Devuelve solo las filas con alerta (vencidas o stock bajo). Si la vista
/// no existe (migración no aplicada) devuelve lista vacía.
final ncfStockAlertsProvider =
    FutureProvider.autoDispose<List<NcfStockRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final result = await client
        .from('vw_ncf_stock')
        .select(
          'receipt_type, prefix, remaining, is_low_stock, is_expired, is_active',
        )
        .eq('is_active', true)
        .or('is_low_stock.eq.true,is_expired.eq.true');
    return (result as List)
        .map((row) => NcfStockRow.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

class NcfStockBanner extends ConsumerWidget {
  const NcfStockBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ncfStockAlertsProvider);
    return async.maybeWhen(
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        final anyExpired = rows.any((r) => r.isExpired);
        final color = anyExpired ? AppTokens.destructive : AppTokens.warning;
        final icon = anyExpired ? Icons.error_outline : Icons.warning_amber_outlined;
        final headline = anyExpired
            ? 'Secuencia NCF vencida'
            : 'Stock de NCF bajo';
        final details = rows
            .map((r) =>
                '${_label(r.receiptType)} (${r.prefix}): ${r.isExpired ? "vencida" : "quedan ${r.remaining ?? 0}"}')
            .join(' · ');

        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.s12),
          child: InkWell(
            onTap: () => context.go('/configuracion'),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(AppTokens.s12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                border: Border.all(color: color.withValues(alpha: 0.40)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: AppTokens.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$details · Toca para configurar.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: color, size: 20),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  static String _label(String type) {
    switch (type) {
      case 'consumer_final':
        return 'Consumidor Final';
      case 'fiscal_credit':
        return 'Crédito Fiscal';
      case 'governmental':
        return 'Gubernamental';
      case 'special':
        return 'Régimen Especial';
      case 'export':
        return 'Exportación';
      default:
        return type;
    }
  }
}
