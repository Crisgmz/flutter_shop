import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/dashboard_repository.dart';
import 'dashboard_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(dashboardDataProvider);
    final selectedPeriod = ref.watch(dashboardPeriodProvider);

    return dataAsync.when(
      data: (data) {
        final kpis = data.kpis;
        if (kpis == null) {
          return ModulePage(
            title: 'Panel de Control',
            child: ErrorCard(
              message: 'No hay sucursal asociada al usuario o no hay datos disponibles.',
              onRetry: () => ref.invalidate(dashboardDataProvider),
            ),
          );
        }

        return ModulePage(
          title: 'Panel de Control',
          description: 'Resumen general de tu negocio',
          actions: [
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(dashboardDataProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Actualizar'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KpisGrid(kpis: kpis),
              const SizedBox(height: AppTokens.s12),
              const _QuickActions(),
              const SizedBox(height: AppTokens.s24),

              // Chart Section
              Container(
                decoration: BoxDecoration(
                  color: AppTokens.card,
                  borderRadius: BorderRadius.circular(AppTokens.radius),
                  border: Border.all(color: AppTokens.border),
                ),
                padding: const EdgeInsets.all(AppTokens.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChartHeader(
                      selectedPeriod: selectedPeriod,
                      onPeriodChanged: (value) {
                        ref.read(dashboardPeriodProvider.notifier).state = value;
                      },
                    ),
                    const SizedBox(height: AppTokens.s24),
                    _SalesBarChart(points: data.salesSummary),
                  ],
                ),
              ),
              
              const SizedBox(height: AppTokens.s24),
              
              // Latest Sales Section
              Container(
                decoration: BoxDecoration(
                  color: AppTokens.card,
                  borderRadius: BorderRadius.circular(AppTokens.radius),
                  border: Border.all(color: AppTokens.border),
                ),
                padding: const EdgeInsets.all(AppTokens.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          color: AppTokens.primary,
                          size: 20,
                        ),
                        const SizedBox(width: AppTokens.s10),
                        const Text(
                          'Últimas Ventas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTokens.foreground,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.s4),
                    const Text(
                      'Transacciones recientes de la sucursal actual',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTokens.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: AppTokens.s20),
                    ResponsiveLayout(
                      mobile: _LatestSalesMobile(sales: data.latestSales),
                      desktop: DataTableShell(
                        child: _LatestSalesTable(sales: data.latestSales),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const ModulePage(
        title: 'Panel de Control',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ModulePage(
        title: 'Panel de Control',
        child: ErrorCard(
          message: 'No se pudo cargar el panel: $error',
          onRetry: () => ref.invalidate(dashboardDataProvider),
        ),
      ),
    );
  }
}


class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  final DashboardPeriod selectedPeriod;
  final ValueChanged<DashboardPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final periodButton = SegmentedButton<DashboardPeriod>(
      segments: const [
        ButtonSegment(value: DashboardPeriod.monthly, label: Text('Mensual')),
        ButtonSegment(value: DashboardPeriod.weekly, label: Text('Semanal')),
      ],
      selected: {selectedPeriod},
      onSelectionChanged: (value) => onPeriodChanged(value.first),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ventas por Mes',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTokens.s4),
          Text(
            'Resumen anual de ventas',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: AppTokens.s12),
          periodButton,
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ventas por Mes',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppTokens.s4),
              Text(
                'Resumen anual de ventas',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        periodButton,
      ],
    );
  }
}

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.kpis});

  final DashboardKpis kpis;

  static const _kpiColors = [
    Color(0xFFF97316),
    Color(0xFFDC2626),
    Color(0xFF16A34A),
    Color(0xFFD97706),
  ];

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Ventas Hoy',
        value: money(kpis.salesTodayAmount),
        trend: '${kpis.salesTodayCount} transacciones',
        icon: Icons.shopping_cart_rounded,
        backgroundColor: _kpiColors[0],
        onTap: () => context.go('/ventas'),
      ),
      KPICard(
        label: 'Ventas del Mes',
        value: money(kpis.salesMonthAmount),
        trend: '${kpis.salesMonthCount} ventas este mes',
        icon: Icons.trending_up_rounded,
        backgroundColor: _kpiColors[1],
        onTap: () => context.go('/reportes'),
      ),
      KPICard(
        label: 'Inventario',
        value: '${kpis.productsActive}',
        trend: 'Productos activos',
        icon: Icons.inventory_2_rounded,
        backgroundColor: _kpiColors[2],
        onTap: () => context.go('/inventario'),
      ),
      KPICard(
        label: 'Clientes',
        value: '${kpis.clientsActive}',
        trend: 'Registrados',
        icon: Icons.people_rounded,
        backgroundColor: _kpiColors[3],
        onTap: () => context.go('/clientes'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int columns = 1;
        if (width >= AppTokens.breakpointExpanded) {
          columns = 4;
        } else if (width >= AppTokens.breakpointMedium) {
          columns = 2;
        }

        return GridView.builder(
          itemCount: cards.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppTokens.s12,
            crossAxisSpacing: AppTokens.s12,
            childAspectRatio: width >= AppTokens.breakpointExpanded ? 1.6 : 2.2,
          ),
          itemBuilder: (_, index) => cards[index],
        );
      },
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _actions = [
    (
      icon: Icons.add_shopping_cart_outlined,
      label: 'Nueva Venta',
      route: '/ventas',
      color: Color(0xFFF97316),
    ),
    (
      icon: Icons.receipt_outlined,
      label: 'Comprobantes',
      route: '/comprobantes',
      color: Color(0xFF7C3AED),
    ),
    (
      icon: Icons.shopping_bag_outlined,
      label: 'Nueva Compra',
      route: '/compras',
      color: Color(0xFF0369A1),
    ),
    (
      icon: Icons.bar_chart_rounded,
      label: 'Reportes',
      route: '/reportes',
      color: Color(0xFF16A34A),
    ),
    (
      icon: Icons.people_outline,
      label: 'Clientes',
      route: '/clientes',
      color: Color(0xFFD97706),
    ),
    (
      icon: Icons.point_of_sale_outlined,
      label: 'Caja',
      route: '/caja',
      color: Color(0xFFDC2626),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 800 ? 6 : w >= 480 ? 3 : 2;
        final itemW = (w - (cols - 1) * AppTokens.s8) / cols;
        return Wrap(
          spacing: AppTokens.s8,
          runSpacing: AppTokens.s8,
          children: _actions.map((a) {
            return SizedBox(
              width: itemW,
              child: Material(
                color: AppTokens.card,
                borderRadius: BorderRadius.circular(AppTokens.radius),
                child: InkWell(
                  onTap: () => context.go(a.route),
                  borderRadius: BorderRadius.circular(AppTokens.radius),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s12,
                      vertical: AppTokens.s10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTokens.radius),
                      border: Border.all(color: AppTokens.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: a.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(a.icon, size: 18, color: a.color),
                        ),
                        const SizedBox(width: AppTokens.s8),
                        Expanded(
                          child: Text(
                            a.label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppTokens.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}


class _LatestSalesMobile extends StatelessWidget {
  const _LatestSalesMobile({required this.sales});

  final List<LatestSale> sales;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.receipt_long_outlined,
        message: 'No hay ventas registradas.',
      );
    }

    return Column(
      children: sales.map((sale) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.s8),
          child: Container(
            padding: const EdgeInsets.all(AppTokens.s12),
            decoration: BoxDecoration(
              color: AppTokens.background,
              borderRadius: BorderRadius.circular(AppTokens.radius),
              border: Border.all(color: AppTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sale.clientName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    StatusBadge(label: 'Aprobado', status: sale.dgiiStatus),
                  ],
                ),
                const SizedBox(height: AppTokens.s6),
                Row(
                  children: [
                    Text(
                      formatDate(sale.saleDate),
                      style: const TextStyle(
                        color: AppTokens.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      money(sale.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                if (sale.ncf != null) ...[
                  const SizedBox(height: AppTokens.s4),
                  Text(
                    'NCF: ${sale.ncf}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppTokens.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}


class _SalesBarChart extends StatelessWidget {
  const _SalesBarChart({required this.points});

  final List<SalesSummaryPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: Text('No hay datos de ventas para el periodo seleccionado.'),
      );
    }

    final maxAmount = points.fold<double>(
      0,
      (prev, item) => math.max(prev, item.totalAmount),
    );
    final topAxis = _roundAxisMax(maxAmount);
    const chartHeight = 320.0;
    const axisWidth = 54.0;
    final yTicks = _buildAxisTicks(topAxis, divisions: 4);

    return SizedBox(
      height: chartHeight + 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: axisWidth,
            child: Column(
              children: [
                for (final tick in yTicks.reversed)
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Text(
                        _compactMoney(tick),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF67728A),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Column(
                            children: [
                              for (int i = yTicks.length - 1; i >= 0; i--)
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 1),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: i == 0
                                              ? const Color(0xFF96A4BC)
                                              : const Color(0xFFD8E0EE),
                                          width: i == 0 ? 1.4 : 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: points
                                .map((point) {
                                  final ratio = topAxis == 0
                                      ? 0.0
                                      : point.totalAmount / topAxis;
                                  final barHeight = math.max(
                                    6.0,
                                    ratio * (chartHeight - 22),
                                  );
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Tooltip(
                                            message:
                                                '${point.periodLabel}: ${money(point.totalAmount)} (${point.transactionCount})',
                                            child: Container(
                                              height: barHeight,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1869E8),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: points
                      .map(
                        (point) => Expanded(
                          child: Text(
                            _shortLabel(point.periodLabel),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: const Color(0xFF67728A)),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestSalesTable extends StatelessWidget {
  const _LatestSalesTable({required this.sales});

  final List<LatestSale> sales;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined, size: 48, color: AppTokens.mutedForeground),
              SizedBox(height: 16),
              Text('No hay ventas registradas.', style: TextStyle(color: AppTokens.mutedForeground)),
            ],
          ),
        ),
      );
    }

    return DataTable(
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      horizontalMargin: 24,
      columnSpacing: 24,
      dividerThickness: 1,
      headingRowHeight: 48,
      dataRowMaxHeight: 60,
      dataRowMinHeight: 52,
      columns: const [
        DataColumn(label: Text('Fecha', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)))),
        DataColumn(label: Text('Cliente', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)))),
        DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)))),
        DataColumn(label: Text('NCF', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)))),
        DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)))),
        DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)))),
      ],
      rows: sales.map((sale) {
        return DataRow(
          cells: [
            DataCell(Text(formatDate(sale.saleDate), style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
            DataCell(
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.clientName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E293B)),
                  ),
                  if (sale.receiptType == 'fiscal_credit')
                    const Text('B15 - Fiscal', style: TextStyle(fontSize: 10, color: AppTokens.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            DataCell(
              Text(
                _receiptName(sale.receiptType),
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ),
            DataCell(
              Text(
                sale.ncf ?? '-',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF334155)),
              ),
            ),
            DataCell(
              Text(
                money(sale.totalAmount),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A)),
              ),
            ),
            DataCell(StatusBadge(label: 'Aprobado', status: sale.dgiiStatus)),
          ],
        );
      }).toList(),
    );
  }
}


double _roundAxisMax(double value) {
  if (value <= 0) return 100000;
  const step = 100000;
  return ((value / step).ceil() * step).toDouble();
}

List<double> _buildAxisTicks(double max, {required int divisions}) {
  if (divisions <= 0) return [0, max];
  return List.generate(divisions + 1, (index) => (max / divisions) * index);
}

String _compactMoney(num value) => moneyShort(value);

String _shortLabel(String value) {
  final normalized = value.trim();
  if (normalized.length <= 3) return normalized;
  return normalized.substring(0, 3);
}


String _receiptName(String value) {
  switch (value) {
    case 'fiscal_credit':
      return 'Crédito Fiscal';
    case 'consumer_final':
      return 'Consumidor Final';
    case 'governmental':
      return 'Gubernamental';
    case 'special':
      return 'Especial';
    case 'export':
      return 'Exportación';
    default:
      return value;
  }
}
