import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/reports_repository.dart';
import 'reports_providers.dart';

// ── Main page ─────────────────────────────────────────────────────────────────

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int _section = 0;

  static const _sections = [
    (icon: Icons.receipt_long_outlined, label: 'Ventas'),
    (icon: Icons.account_balance_wallet_outlined, label: 'Cobros'),
    (icon: Icons.inventory_2_outlined, label: 'Inventario'),
    (icon: Icons.receipt_outlined, label: 'Fiscal / NCF'),
    (icon: Icons.shopping_cart_outlined, label: 'Compras'),
    (icon: Icons.money_off_outlined, label: 'Gastos'),
    (icon: Icons.file_download_outlined, label: 'Exportaciones'),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return ModulePage(
      title: 'Reportes',
      description: 'Análisis financiero y operacional de la sucursal.',
      actions: [
        SegmentedButton<ReportPeriod>(
          segments: const [
            ButtonSegment(value: ReportPeriod.monthly, label: Text('Mensual')),
            ButtonSegment(value: ReportPeriod.weekly, label: Text('Semanal')),
          ],
          selected: {ref.watch(reportPeriodProvider)},
          onSelectionChanged: (value) {
            ref.read(reportPeriodProvider.notifier).state = value.first;
          },
        ),
        const SizedBox(width: AppTokens.s8),
        OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: isMobile ? _mobileLayout() : _desktopLayout(),
    );
  }

  void _refresh() {
    ref.invalidate(reportsDataProvider);
    ref.invalidate(reportPresetsProvider);
    ref.invalidate(reportExportsProvider);
    ref.invalidate(salesTaxBreakdownProvider);
  }

  Widget _desktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NavPanel(
          sections: _sections,
          selected: _section,
          onSelect: (i) => setState(() => _section = i),
        ),
        const SizedBox(width: AppTokens.s16),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _mobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileNav(
          sections: _sections,
          selected: _section,
          onSelect: (i) => setState(() => _section = i),
        ),
        const SizedBox(height: AppTokens.s16),
        _buildContent(),
      ],
    );
  }

  Widget _buildContent() {
    switch (_section) {
      case 0:
        return const _VentasSection();
      case 1:
        return const _CobrosSection();
      case 2:
        return const _InventarioSection();
      case 3:
        return const _FiscalSection();
      case 4:
        return _ModuleLinkSection(
          icon: Icons.shopping_cart_outlined,
          title: 'Módulo de Compras',
          description:
              'Consulta órdenes de compra, recepciones y estado con proveedores.',
          route: '/compras',
          color: const Color(0xFF0369A1),
        );
      case 5:
        return _ModuleLinkSection(
          icon: Icons.money_off_outlined,
          title: 'Módulo de Gastos',
          description:
              'Registra y consulta los gastos operativos de la sucursal.',
          route: '/gastos',
          color: const Color(0xFF7C3AED),
        );
      case 6:
      default:
        return const _ExportacionesSection();
    }
  }
}

// ── Navigation widgets ────────────────────────────────────────────────────────

class _NavPanel extends StatelessWidget {
  const _NavPanel({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final List<({IconData icon, String label})> sections;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: sections.indexed.map((e) {
            final idx = e.$1;
            final sec = e.$2;
            final isSelected = idx == selected;
            return ListTile(
              dense: true,
              leading: Icon(
                sec.icon,
                size: 18,
                color:
                    isSelected ? AppTokens.primary : AppTokens.mutedForeground,
              ),
              title: Text(
                sec.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppTokens.primary
                      : AppTokens.foreground,
                ),
              ),
              selected: isSelected,
              selectedTileColor: AppTokens.primary.withValues(alpha: 0.08),
              onTap: () => onSelect(idx),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _MobileNav extends StatelessWidget {
  const _MobileNav({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final List<({IconData icon, String label})> sections;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sections.indexed.map((e) {
          final idx = e.$1;
          final sec = e.$2;
          return Padding(
            padding: const EdgeInsets.only(right: AppTokens.s8),
            child: FilterChip(
              avatar: Icon(sec.icon, size: 16),
              label: Text(sec.label),
              selected: idx == selected,
              onSelected: (_) => onSelect(idx),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Section: Ventas ───────────────────────────────────────────────────────────

class _VentasSection extends ConsumerWidget {
  const _VentasSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(reportsDataProvider);

    return dataAsync.when(
      data: (data) => _VentasContent(data: data),
      loading: () => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar ventas: $e',
        onRetry: () => ref.invalidate(reportsDataProvider),
      ),
    );
  }
}

class _VentasContent extends StatelessWidget {
  const _VentasContent({required this.data});

  final ReportsData data;

  @override
  Widget build(BuildContext context) {
    final points = data.salesPoints;
    final totalSales =
        points.fold<double>(0, (sum, p) => sum + p.totalAmount);
    final totalTx = points.fold<int>(0, (sum, p) => sum + p.transactionCount);
    final activePeriods = points.where((p) => p.totalAmount > 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            final narrow = constraints.maxWidth < 600;
            final kpiCards = [
              KPICard(
                label: 'Total vendido',
                value: money(totalSales),
                icon: Icons.trending_up_rounded,
              ),
              KPICard(
                label: 'Transacciones',
                value: totalTx.toString(),
                icon: Icons.receipt_long_outlined,
              ),
              KPICard(
                label: 'Periodos activos',
                value: activePeriods.toString(),
                icon: Icons.calendar_month_outlined,
              ),
            ];

            if (narrow) {
              return Wrap(
                spacing: AppTokens.s12,
                runSpacing: AppTokens.s12,
                children: kpiCards
                    .map((c) => SizedBox(
                          width:
                              (constraints.maxWidth - AppTokens.s12) / 2,
                          child: c,
                        ))
                    .toList(),
              );
            }

            return Row(
              children: [
                Expanded(child: kpiCards[0]),
                const SizedBox(width: AppTokens.s12),
                Expanded(child: kpiCards[1]),
                const SizedBox(width: AppTokens.s12),
                Expanded(child: kpiCards[2]),
              ],
            );
          },
        ),
        const SizedBox(height: AppTokens.s16),
        // Bar chart — plain card (no horizontal scroll, so Expanded in Row works)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTokens.card,
            borderRadius: BorderRadius.circular(AppTokens.radius),
            border: Border.all(color: AppTokens.border),
          ),
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ventas por periodo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.foreground,
                ),
              ),
              const SizedBox(height: AppTokens.s16),
              _SalesSummaryList(points: points),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section: Cobros ───────────────────────────────────────────────────────────

class _CobrosSection extends ConsumerWidget {
  const _CobrosSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(reportsDataProvider);

    return dataAsync.when(
      data: (data) {
        final receivable = data.receivable;
        if (receivable == null) {
          return const EmptyStateCard(
            icon: Icons.account_balance_wallet_outlined,
            message: 'No hay datos de cobros disponibles.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReceivableKpis(receivable: receivable),
            const SizedBox(height: AppTokens.s24),
            OutlinedButton.icon(
              onPressed: () => context.go('/cobros'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Ver módulo de cobros completo'),
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar cobros: $e',
        onRetry: () => ref.invalidate(reportsDataProvider),
      ),
    );
  }
}

// ── Section: Inventario ───────────────────────────────────────────────────────

class _InventarioSection extends ConsumerWidget {
  const _InventarioSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(reportsDataProvider);

    return dataAsync.when(
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LowStockTable(items: data.lowStockItems),
          const SizedBox(height: AppTokens.s16),
          OutlinedButton.icon(
            onPressed: () => context.go('/inventario'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ver inventario completo'),
          ),
        ],
      ),
      loading: () => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar el inventario: $e',
        onRetry: () => ref.invalidate(reportsDataProvider),
      ),
    );
  }
}

// ── Section: Fiscal / NCF ─────────────────────────────────────────────────────

class _FiscalSection extends ConsumerWidget {
  const _FiscalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(reportsDataProvider);

    return dataAsync.when(
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SalesTaxSection(),
          const SizedBox(height: AppTokens.s24),
          _NcfTable(items: data.ncfItems),
          const SizedBox(height: AppTokens.s16),
          OutlinedButton.icon(
            onPressed: () => context.go('/comprobantes'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ver comprobantes fiscales emitidos'),
          ),
        ],
      ),
      loading: () => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar datos fiscales: $e',
        onRetry: () => ref.invalidate(reportsDataProvider),
      ),
    );
  }
}

// ── Section: Exportaciones ────────────────────────────────────────────────────

class _ExportacionesSection extends ConsumerWidget {
  const _ExportacionesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetsAsync = ref.watch(reportPresetsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PresetsSection(presetsAsync: presetsAsync),
        const SizedBox(height: AppTokens.s24),
        const _ExportsSection(),
      ],
    );
  }
}

// ── Section: Module link (Compras / Gastos) ───────────────────────────────────

class _ModuleLinkSection extends StatelessWidget {
  const _ModuleLinkSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.route,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final String route;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppTokens.s12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTokens.radius),
                  ),
                  child: Icon(icon, size: 28, color: color),
                ),
                const SizedBox(width: AppTokens.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          color: AppTokens.mutedForeground,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s20),
            FilledButton.icon(
              onPressed: () => context.go(route),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Ir al módulo'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Low stock table (extracted from ReportsPage) ──────────────────────────────

class _LowStockTable extends StatelessWidget {
  const _LowStockTable({required this.items});

  final List<LowStockReportItem> items;

  @override
  Widget build(BuildContext context) {
    return DataTableShell(
      title: 'Inventario bajo stock',
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Sin productos en bajo stock.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Producto')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(label: Text('Stock'), numeric: true),
                  DataColumn(label: Text('Mínimo'), numeric: true),
                  DataColumn(label: Text('Precio'), numeric: true),
                ],
                rows: items
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(Text(
                            item.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          )),
                          DataCell(Text(
                            item.sku ?? '-',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          )),
                          DataCell(Text(
                            item.stock.toStringAsFixed(2),
                            style: const TextStyle(
                              color: AppTokens.destructive,
                              fontWeight: FontWeight.w700,
                            ),
                          )),
                          DataCell(Text(item.minStock.toStringAsFixed(2))),
                          DataCell(Text(money(item.price))),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
    );
  }
}

// ── NCF table (extracted from ReportsPage) ────────────────────────────────────

class _NcfTable extends StatelessWidget {
  const _NcfTable({required this.items});

  final List<NcfUsageItem> items;

  @override
  Widget build(BuildContext context) {
    return DataTableShell(
      title: 'Uso NCF',
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Sin datos NCF.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Prefijo')),
                  DataColumn(label: Text('Actual'), numeric: true),
                  DataColumn(label: Text('Disponible'), numeric: true),
                  DataColumn(label: Text('Vence')),
                ],
                rows: items
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(Text(_pretty(item.receiptType))),
                          DataCell(Text(
                            item.prefix,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          )),
                          DataCell(Text(item.currentNumber.toString())),
                          DataCell(Text(item.available.toString())),
                          DataCell(Text(
                            item.expiresOn == null
                                ? '-'
                                : formatDate(item.expiresOn!),
                          )),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
    );
  }
}

class _ReceivableKpis extends StatelessWidget {
  const _ReceivableKpis({required this.receivable});

  final ReceivableReport receivable;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Facturas abiertas',
        value: receivable.invoicesOpen.toString(),
        icon: Icons.receipt_long_outlined,
      ),
      KPICard(
        label: 'Balance por cobrar',
        value: money(receivable.totalBalanceDue),
        icon: Icons.access_time_rounded,
      ),
      KPICard(
        label: 'Facturado',
        value: money(receivable.totalInvoiced),
        icon: Icons.trending_up_rounded,
      ),
      KPICard(
        label: 'Cobrado',
        value: money(receivable.totalCollected),
        icon: Icons.check_circle_outline,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Wrap(
            spacing: AppTokens.s12,
            runSpacing: AppTokens.s12,
            children: cards
                .map((card) => SizedBox(
                      width: (constraints.maxWidth - AppTokens.s12) / 2,
                      child: card,
                    ))
                .toList(),
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[1]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[2]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }
}

class _SalesSummaryList extends StatelessWidget {
  const _SalesSummaryList({required this.points});

  final List<ReportSalesPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Text(
        'No hay datos para el periodo seleccionado.',
        style: TextStyle(color: AppTokens.mutedForeground),
      );
    }

    final maxAmount = points
        .map((point) => point.totalAmount)
        .fold<double>(0, (prev, next) => next > prev ? next : prev);

    return Column(
      children: points
          .map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: ResponsiveLayout.isMobile(context) ? 80 : 120,
                    child: Text(point.periodLabel),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTokens.radiusS),
                      child: LinearProgressIndicator(
                        value: maxAmount == 0 ? 0 : point.totalAmount / maxAmount,
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: ResponsiveLayout.isMobile(context) ? 130 : 170,
                    child: Text(
                      '${money(point.totalAmount)} (${point.transactionCount})',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

String _pretty(String value) {
  if (value.isEmpty) return '-';
  return value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

// ── Sales Tax Breakdown section ───────────────────────────────────────────────

class _SalesTaxSection extends ConsumerWidget {
  const _SalesTaxSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(salesTaxBreakdownProvider);
    final from = ref.watch(taxBreakdownFromProvider);
    final to = ref.watch(taxBreakdownToProvider);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s20, AppTokens.s20, AppTokens.s20, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Desglose ITBIS / Impuestos',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.foreground,
                    ),
                  ),
                ),
                _DateRangeButton(
                  from: from,
                  to: to,
                  onChanged: (f, t) {
                    ref.read(taxBreakdownFromProvider.notifier).state = f;
                    ref.read(taxBreakdownToProvider.notifier).state = t;
                  },
                ),
              ],
            ),
          ),
          rowsAsync.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppTokens.s20),
                  child: Text(
                    'Sin ventas en el periodo seleccionado.',
                    style: TextStyle(color: AppTokens.mutedForeground),
                  ),
                );
              }

              final summary = <String, _TaxSummary>{};
              for (final r in rows) {
                final s =
                    summary.putIfAbsent(r.receiptType, () => _TaxSummary());
                s.count++;
                s.taxable += r.taxableAmount;
                s.exempt += r.exemptAmount;
                s.tax += r.taxAmount;
                s.serviceCharge += r.serviceChargeAmount;
                s.total += r.totalAmount;
              }

              final totals = _TaxSummary();
              for (final s in summary.values) {
                totals.count += s.count;
                totals.taxable += s.taxable;
                totals.exempt += s.exempt;
                totals.tax += s.tax;
                totals.serviceCharge += s.serviceCharge;
                totals.total += s.total;
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('Tipo comprobante')),
                    DataColumn(label: Text('Fact.'), numeric: true),
                    DataColumn(label: Text('Gravado'), numeric: true),
                    DataColumn(label: Text('Exento'), numeric: true),
                    DataColumn(label: Text('ITBIS'), numeric: true),
                    DataColumn(label: Text('Servicio'), numeric: true),
                    DataColumn(label: Text('Total'), numeric: true),
                  ],
                  rows: [
                    ...summary.entries.map(
                      (e) => DataRow(cells: [
                        DataCell(Text(_pretty(e.key))),
                        DataCell(Text(e.value.count.toString())),
                        DataCell(Text(money(e.value.taxable))),
                        DataCell(Text(money(e.value.exempt))),
                        DataCell(Text(
                          money(e.value.tax),
                          style: const TextStyle(
                            color: AppTokens.destructive,
                            fontWeight: FontWeight.w600,
                          ),
                        )),
                        DataCell(Text(money(e.value.serviceCharge))),
                        DataCell(Text(
                          money(e.value.total),
                          style:
                              const TextStyle(fontWeight: FontWeight.w700),
                        )),
                      ]),
                    ),
                    DataRow(cells: [
                      const DataCell(Text(
                        'TOTAL',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      )),
                      DataCell(Text(
                        totals.count.toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )),
                      DataCell(Text(
                        money(totals.taxable),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )),
                      DataCell(Text(
                        money(totals.exempt),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )),
                      DataCell(Text(
                        money(totals.tax),
                        style: const TextStyle(
                          color: AppTokens.destructive,
                          fontWeight: FontWeight.w700,
                        ),
                      )),
                      DataCell(Text(
                        money(totals.serviceCharge),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )),
                      DataCell(Text(
                        money(totals.total),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )),
                    ]),
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.s24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(AppTokens.s20),
              child: Text(
                'No se pudo cargar el desglose: $error',
                style: const TextStyle(color: AppTokens.destructive),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxSummary {
  int count = 0;
  double taxable = 0;
  double exempt = 0;
  double tax = 0;
  double serviceCharge = 0;
  double total = 0;
}

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;

  @override
  Widget build(BuildContext context) {
    final hasRange = from != null || to != null;

    String label() {
      if (!hasRange) return 'Rango fechas';
      final f = from == null
          ? '…'
          : '${from!.day}/${from!.month}/${from!.year}';
      final t =
          to == null ? '…' : '${to!.day}/${to!.month}/${to!.year}';
      return '$f → $t';
    }

    return OutlinedButton.icon(
      onPressed: hasRange
          ? () => onChanged(null, null)
          : () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDateRange: from != null
                    ? DateTimeRange(
                        start: from!,
                        end: to ?? DateTime.now(),
                      )
                    : null,
              );
              if (range != null) {
                onChanged(range.start, range.end);
              }
            },
      icon: Icon(
        hasRange ? Icons.close : Icons.date_range_outlined,
        size: 16,
      ),
      label: Text(label()),
    );
  }
}

// ── Presets section ──────────────────────────────────────────────────────────

class _PresetsSection extends StatelessWidget {
  const _PresetsSection({required this.presetsAsync});

  final AsyncValue<List<ReportPreset>> presetsAsync;

  @override
  Widget build(BuildContext context) {
    return DataTableShell(
      title: 'Presets de reportes',
      child: presetsAsync.when(
        data: (presets) {
          if (presets.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Sin presets guardados.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            );
          }
          return DataTable(
            columns: const [
              DataColumn(label: Text('Nombre')),
              DataColumn(label: Text('Reporte')),
              DataColumn(label: Text('Descripción')),
              DataColumn(label: Text('Por defecto')),
            ],
            rows: presets
                .map(
                  (preset) => DataRow(
                    cells: [
                      DataCell(Text(
                        preset.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      )),
                      DataCell(Text(
                        _pretty(preset.reportKey),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      )),
                      DataCell(Text(
                        preset.description ?? '—',
                        style:
                            const TextStyle(color: AppTokens.mutedForeground),
                      )),
                      DataCell(
                        preset.isDefault
                            ? const Icon(Icons.check_circle_outline,
                                size: 18, color: Color(0xFF22C55E))
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                )
                .toList(growable: false),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(AppTokens.s20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => const Padding(
          padding: EdgeInsets.all(AppTokens.s20),
          child: Text(
            'No se pudieron cargar los presets.',
            style: TextStyle(color: AppTokens.mutedForeground),
          ),
        ),
      ),
    );
  }
}

// ── Exports section ───────────────────────────────────────────────────────────

const _exportStatusLabels = <String, String>{
  'pending': 'Pendiente',
  'processing': 'Procesando',
  'completed': 'Listo',
  'failed': 'Error',
  'expired': 'Expirado',
};

const _exportStatusColors = <String, Color>{
  'pending': Color(0xFFF59E0B),
  'processing': Color(0xFF3B82F6),
  'completed': Color(0xFF22C55E),
  'failed': Color(0xFFEF4444),
  'expired': Color(0xFF94A3B8),
};

class _ExportsSection extends ConsumerStatefulWidget {
  const _ExportsSection();

  @override
  ConsumerState<_ExportsSection> createState() => _ExportsSectionState();
}

class _ExportsSectionState extends ConsumerState<_ExportsSection> {
  @override
  Widget build(BuildContext context) {
    final exportsAsync = ref.watch(reportExportsProvider);

    return DataTableShell(
      title: 'Historial de exportaciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s20, AppTokens.s12, AppTokens.s20, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _onRequestExport,
                icon: const Icon(Icons.add_chart_outlined, size: 16),
                label: const Text('Nueva exportación'),
              ),
            ),
          ),
          exportsAsync.when(
            data: (exports) {
              if (exports.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppTokens.s20),
                  child: Text(
                    'Sin exportaciones recientes.',
                    style: TextStyle(color: AppTokens.mutedForeground),
                  ),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Reporte')),
                    DataColumn(label: Text('Formato')),
                    DataColumn(label: Text('Estado')),
                    DataColumn(label: Text('Solicitado')),
                    DataColumn(label: Text('Archivo')),
                  ],
                  rows: exports
                      .map((exp) => _buildExportRow(exp))
                      .toList(growable: false),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppTokens.s20),
              child: Text(
                'No se pudo cargar el historial: $e',
                style: const TextStyle(color: AppTokens.mutedForeground),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildExportRow(ReportExport exp) {
    final statusColor =
        _exportStatusColors[exp.status] ?? AppTokens.mutedForeground;
    final statusLabel = _exportStatusLabels[exp.status] ?? _pretty(exp.status);

    return DataRow(cells: [
      DataCell(Text(
        _pretty(exp.reportKey),
        style: const TextStyle(fontWeight: FontWeight.w600),
      )),
      DataCell(Text(
        exp.exportFormat.toUpperCase(),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      )),
      DataCell(Container(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8, vertical: 3),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
        ),
        child: Text(
          statusLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: statusColor,
          ),
        ),
      )),
      DataCell(Text(formatDateTime(exp.requestedAt))),
      DataCell(
        exp.hasDownload
            ? TextButton.icon(
                onPressed: () => _copyUrl(exp.downloadUrl!),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: Text(
                  exp.fileName ?? 'Copiar URL',
                  style: const TextStyle(fontSize: 13),
                ),
              )
            : Text(
                exp.errorMessage ?? exp.fileName ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTokens.mutedForeground,
                ),
              ),
      ),
    ]);
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL copiada al portapapeles')),
    );
  }

  Future<void> _onRequestExport() async {
    final result = await showDialog<({String reportKey, String format})>(
      context: context,
      builder: (_) => const _RequestExportDialog(),
    );
    if (result == null || !mounted) return;

    try {
      final repo = ref.read(reportsRepositoryProvider);
      await repo.requestExport(
        reportKey: result.reportKey,
        exportFormat: result.format,
      );
      if (!mounted) return;
      ref.invalidate(reportExportsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exportación solicitada')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo solicitar exportación: $error')),
      );
    }
  }
}

// ── Request Export Dialog ─────────────────────────────────────────────────────

const _exportReportKeys = <String, String>{
  'sales_summary': 'Resumen de ventas',
  'tax_breakdown': 'Desglose ITBIS',
  'accounts_receivable': 'Cuentas por cobrar',
  'low_stock': 'Inventario bajo stock',
  'ncf_usage': 'Uso NCF',
};

const _exportFormats = <String>['csv', 'xlsx', 'pdf'];

class _RequestExportDialog extends StatefulWidget {
  const _RequestExportDialog();

  @override
  State<_RequestExportDialog> createState() => _RequestExportDialogState();
}

class _RequestExportDialogState extends State<_RequestExportDialog> {
  String _reportKey = 'sales_summary';
  String _format = 'csv';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Solicitar exportación'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _reportKey,
              decoration: const InputDecoration(labelText: 'Reporte'),
              items: _exportReportKeys.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(growable: false),
              onChanged: (v) => setState(() => _reportKey = v ?? _reportKey),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _format,
              decoration: const InputDecoration(labelText: 'Formato'),
              items: _exportFormats
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f.toUpperCase()),
                      ))
                  .toList(growable: false),
              onChanged: (v) => setState(() => _format = v ?? _format),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop((reportKey: _reportKey, format: _format)),
          child: const Text('Solicitar'),
        ),
      ],
    );
  }
}
