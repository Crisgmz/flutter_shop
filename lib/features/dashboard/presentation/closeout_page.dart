// Pantalla dedicada al Cierre del día (PRD F4) — accesible desde
// los quick actions del Panel ("Informe de cierre de hoy").
//
// Reutiliza el mismo provider `dashboardCloseoutProvider` que la pieza
// inline original, así que la fecha persiste si el usuario abre y cierra
// la pantalla. La navegación día anterior / siguiente día actualiza el
// provider y refresca el contenido.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../data/dashboard_repository.dart';
import 'dashboard_providers.dart';

class CloseoutPage extends ConsumerWidget {
  const CloseoutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closeoutAsync = ref.watch(dashboardCloseoutProvider);
    final date = ref.watch(dashboardCloseoutDateProvider);
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    return ModulePage(
      title: 'Cierre del día',
      description: 'Liquidación detallada por sucursal y día.',
      actions: [
        TextButton.icon(
          onPressed: () {
            ref.read(dashboardCloseoutDateProvider.notifier).state =
                date.subtract(const Duration(days: 1));
          },
          icon: const Icon(Icons.chevron_left),
          label: const Text('Día anterior'),
        ),
        TextButton.icon(
          onPressed: isToday
              ? null
              : () {
                  ref.read(dashboardCloseoutDateProvider.notifier).state =
                      date.add(const Duration(days: 1));
                },
          icon: const Icon(Icons.chevron_right),
          label: const Text('Siguiente día'),
        ),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(dashboardCloseoutProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Liquidación · ${formatDate(date)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Divider(height: AppTokens.s24, color: AppTokens.border),
              closeoutAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppTokens.s24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => ErrorCard(
                  message: 'No se pudo cargar el cierre: $error',
                  onRetry: () =>
                      ref.invalidate(dashboardCloseoutProvider),
                ),
                data: (closeout) => CloseoutBlocks(closeout: closeout),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bloques visuales del cierre. Exportado para reutilizo desde otras vistas
/// (en este round sólo lo consume `closeout_page.dart`).
class CloseoutBlocks extends StatelessWidget {
  const CloseoutBlocks({super.key, required this.closeout});

  final DashboardCloseout closeout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BlockHeader('Ventas'),
        _BlockRow('Ventas totales (sin impuestos)',
            money(closeout.sales.salesTotalNoTax)),
        _BlockRow('Ventas totales (con impuestos)',
            money(closeout.sales.salesTotalWithTax)),
        _BlockRow('Beneficios', money(closeout.sales.profit)),
        _BlockRow('Total artículos en inventario',
            qty(closeout.sales.inventoryQtyOnHand.toInt())),
        _BlockRow('Valor total del inventario',
            money(closeout.sales.inventoryValue)),
        _BlockRow('Número de transacciones',
            '${closeout.sales.transactionsCount}'),
        _BlockRow('Ticket promedio', money(closeout.sales.avgTicket)),
        _BlockRow('Número de artículos vendidos',
            qty(closeout.sales.itemsSold.toInt())),
        _BlockRow('Impuesto', money(closeout.sales.taxAmount)),
        _BlockRow('Sin impuesto', money(closeout.sales.noTaxAmount)),
        _BlockRow('Efectivo', money(closeout.sales.cashAmount)),
        if (closeout.sales.breakdownByCategory.isNotEmpty) ...[
          const SizedBox(height: AppTokens.s8),
          Text(
            'Por categoría',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTokens.mutedForeground,
                ),
          ),
          for (final cat in closeout.sales.breakdownByCategory)
            _BlockRow('  · ${cat.name}', money(cat.amount)),
        ],

        const _BlockSpacer(),
        const _BlockHeader('Crédito'),
        _BlockRow('Débitos', money(closeout.credit.debits)),
        _BlockRow('Créditos', money(closeout.credit.credits)),
        _BlockRow('Saldo total cuentas de tienda',
            money(closeout.credit.storeAccountBalanceTotal)),

        const _BlockSpacer(),
        const _BlockHeader('Devoluciones'),
        if (!closeout.returns.returnsTableAvailable)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.s8),
            child: Text(
              'Datos aproximados desde ventas anuladas. La tabla `returns` '
              'completa llega con el toggle Venta/Devolución (PRD F5).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTokens.mutedForeground,
                  ),
            ),
          ),
        _BlockRow('Retornos totales', money(closeout.returns.returnsTotal)),
        _BlockRow('Número de transacciones',
            '${closeout.returns.transactionsCount}'),
        _BlockRow('Artículos devueltos',
            qty(closeout.returns.itemsReturned.toInt())),
        _BlockRow('Impuesto', money(closeout.returns.taxAmount)),
        for (final item in closeout.returns.breakdownByItem)
          _BlockRow(
            '  · ${item.description} (${item.quantity})',
            money(item.amount),
          ),

        const _BlockSpacer(),
        const _BlockHeader('Compras'),
        _BlockRow('Recepciones totales (sin impuestos)',
            money(closeout.purchases.receivingsTotalNoTax)),
        _BlockRow('Recepciones totales (con impuestos)',
            money(closeout.purchases.receivingsTotalWithTax)),
        _BlockRow('Número de transacciones',
            '${closeout.purchases.transactionsCount}'),
        _BlockRow('Ticket promedio', money(closeout.purchases.avgTicket)),
        _BlockRow('Artículos recibidos',
            qty(closeout.purchases.itemsReceived.toInt())),
        _BlockRow('Impuesto', money(closeout.purchases.taxAmount)),
        _BlockRow('Sin impuesto', money(closeout.purchases.noTaxAmount)),

        const _BlockSpacer(),
        const _BlockHeader('Gastos'),
        _BlockRow('Gastos totales', money(closeout.expenses.expensesTotal)),
        _BlockRow('Número de transacciones',
            '${closeout.expenses.transactionsCount}'),

        const _BlockSpacer(),
        const _BlockHeader('Monitoreo de efectivo en caja'),
        if (!closeout.cashMonitoring.enabled)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
            child: Text(
              'No hay sesión de caja registrada para este día.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTokens.mutedForeground,
                  ),
            ),
          )
        else ...[
          _BlockRow('Estado',
              _cashStatusLabel(closeout.cashMonitoring.status)),
          _BlockRow('Efectivo inicial declarado',
              money(closeout.cashMonitoring.openingAmount)),
          _BlockRow('Efectivo esperado',
              money(closeout.cashMonitoring.expectedAmount)),
          if (closeout.cashMonitoring.closingAmount != null)
            _BlockRow('Efectivo declarado al cierre',
                money(closeout.cashMonitoring.closingAmount)),
          if (closeout.cashMonitoring.differenceAmount != null)
            _BlockRow('Diferencia',
                money(closeout.cashMonitoring.differenceAmount)),
        ],
      ],
    );
  }

  String _cashStatusLabel(String? status) {
    switch (status) {
      case 'open':
        return 'Abierta';
      case 'closed':
        return 'Cerrada';
      default:
        return status ?? '—';
    }
  }
}

class _BlockHeader extends StatelessWidget {
  const _BlockHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s12,
        vertical: AppTokens.s8,
      ),
      decoration: BoxDecoration(
        color: AppTokens.secondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _BlockSpacer extends StatelessWidget {
  const _BlockSpacer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: AppTokens.s16);
  }
}
