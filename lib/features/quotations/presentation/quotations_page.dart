import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
import '../data/quotations_models.dart';
import 'quotations_providers.dart';

class QuotationsPage extends ConsumerWidget {
  const QuotationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foundationAsync = ref.watch(quotationsFoundationProvider);

    return foundationAsync.when(
      data: (foundation) => ModulePage(
        title: 'Cotizaciones',
        description: 'Gestión comercial de propuestas y cierre de ventas.',
        actions: [
          OutlinedButton.icon(
            onPressed: () => ref.invalidate(quotationsFoundationProvider),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Actualizar'),
          ),
          const SizedBox(width: AppTokens.s8),
          FilledButton.icon(
            onPressed: () => context.push('/cotizaciones/nueva'),
            icon: const Icon(Icons.note_add_outlined, size: 18),
            label: const Text('Nueva cotización'),
          ),
        ],
        child: Column(
          children: [
            _MetricsGrid(metrics: foundation.metrics),
            const SizedBox(height: AppTokens.s24),
            ResponsiveLayout(
              mobile: _PipelineCard(pipeline: foundation.pipeline),
              desktop: _PipelineCard(pipeline: foundation.pipeline),
            ),
            const SizedBox(height: AppTokens.s24),
            _RecentQuotesCard(quotes: foundation.recentQuotes),
          ],
        ),
      ),
      loading: () => const ModulePage(
        title: 'Cotizaciones',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ModulePage(
        title: 'Cotizaciones',
        child: ErrorCard(
          message: 'No se pudo cargar la base de cotizaciones: $error',
          onRetry: () => ref.invalidate(quotationsFoundationProvider),
        ),
      ),
    );
  }
}

class _RecentQuotesCard extends ConsumerWidget {
  const _RecentQuotesCard({required this.quotes});

  final List<QuoteListItem> quotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cotizaciones recientes',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${quotes.length} registradas',
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s14),
            if (quotes.isEmpty)
              const EmptyStateCard(
                icon: Icons.request_quote_outlined,
                message: 'Aún no hay cotizaciones preparadas.',
              )
            else if (isMobile)
              Column(
                children: [
                  for (final quote in quotes) ...[
                    _QuoteMobileCard(quote: quote),
                    if (quote != quotes.last)
                      const SizedBox(height: AppTokens.s10),
                  ],
                ],
              )
            else
              _QuotesDataTable(quotes: quotes),
          ],
        ),
      ),
    );
  }
}

class _QuotesDataTable extends ConsumerWidget {
  const _QuotesDataTable({required this.quotes});
  final List<QuoteListItem> quotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : 0),
            child: DataTable(
              horizontalMargin: 12,
              columnSpacing: constraints.maxWidth > 800 ? 40 : 24,
              columns: const [
                DataColumn(label: Text('Código')),
                DataColumn(label: Text('Cliente')),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Vigencia')),
                DataColumn(label: Text('Monto')),
                DataColumn(label: Text('Acciones')),
              ],
              rows: quotes
                  .map(
                    (quote) => DataRow(
                      onSelectChanged: (_) => context.push('/cotizaciones/${quote.id}'),
                      cells: [
                        DataCell(
                          Text(
                            quote.code,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => context.push('/cotizaciones/${quote.id}'),
                        ),
                        DataCell(Text(quote.clientName)),
                        DataCell(_StatusChip(status: quote.effectiveStatus)),
                        DataCell(Text(formatDate(quote.validUntil))),
                        DataCell(
                          Text(
                            money(quote.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTokens.brandBlueDark,
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => context.push('/cotizaciones/${quote.id}'),
                                icon: const Icon(Icons.visibility_outlined, size: 20),
                                tooltip: 'Ver / editar',
                              ),
                              IconButton(
                                onPressed: () => _printQuote(context, ref, quote),
                                icon: const Icon(Icons.print_outlined, size: 20),
                                tooltip: 'Imprimir cotización',
                              ),
                              if (quote.canConvert)
                                IconButton(
                                  onPressed: () => _convertToSale(context, ref, quote),
                                  icon: const Icon(
                                    Icons.shopping_cart_checkout_rounded,
                                    color: AppTokens.success,
                                    size: 20,
                                  ),
                                  tooltip: 'Convertir a venta',
                                ),
                              if (quote.canDelete)
                                IconButton(
                                  onPressed: () => _deleteQuote(context, ref, quote),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppTokens.error,
                                    size: 20,
                                  ),
                                  tooltip: 'Eliminar',
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _convertToSale(
    BuildContext context,
    WidgetRef ref,
    QuoteListItem quote,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convertir a venta'),
        content: Text(
          '¿Deseas convertir la cotización ${quote.code} en una venta pendiente? Esto trasladará cliente, líneas y montos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final result = await ref
            .read(quotationsRepositoryProvider)
            .convertToSale(quote.id);
        ref.invalidate(quotationsFoundationProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cotización convertida a venta ${result.saleNumber}.',
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _printQuote(
    BuildContext context,
    WidgetRef ref,
    QuoteListItem quote,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final printJob = await ref
          .read(quotationsRepositoryProvider)
          .prepareQuotePrintJob(quoteId: quote.id);
      if (printJob == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo preparar la impresión.')),
        );
        return;
      }
      if (context.mounted) {
        await PrintReceiptDialog.show(context, printJob);
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteQuote(
    BuildContext context,
    WidgetRef ref,
    QuoteListItem quote,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la cotización ${quote.code}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(quotationsRepositoryProvider).deleteQuote(quote.id);
        ref.invalidate(quotationsFoundationProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}

class _QuoteMobileCard extends ConsumerWidget {
  const _QuoteMobileCard({required this.quote});

  final QuoteListItem quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push('/cotizaciones/${quote.id}'),
      borderRadius: BorderRadius.circular(AppTokens.radiusL),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.s14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FBFF),
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
          border: Border.all(color: AppTokens.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quote.code,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusChip(status: quote.effectiveStatus),
              ],
            ),
            const SizedBox(height: AppTokens.s6),
            Text(
              quote.clientName,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.s10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Vence ${formatDate(quote.validUntil)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTokens.textSecondary,
                  ),
                ),
                Text(
                  money(quote.total),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTokens.brandBlueDark,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _printQuote(context, ref),
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text('Imprimir'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printQuote(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final printJob = await ref
          .read(quotationsRepositoryProvider)
          .prepareQuotePrintJob(quoteId: quote.id);
      if (printJob == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo preparar la impresión.')),
        );
        return;
      }
      if (context.mounted) {
        await PrintReceiptDialog.show(context, printJob);
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final QuoteStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = switch (status) {
      QuoteStatus.draft => (const Color(0xFFEAF2FF), AppTokens.brandBlueDark),
      QuoteStatus.sent => (const Color(0xFFEAF8FF), AppTokens.info),
      QuoteStatus.underReview => (const Color(0xFFFFF6E5), AppTokens.warning),
      QuoteStatus.approved => (const Color(0xFFE8F8EE), AppTokens.success),
      QuoteStatus.rejected => (const Color(0xFFFDEBED), AppTokens.error),
      QuoteStatus.expired => (const Color(0xFFF1F3F7), AppTokens.textMuted),
      QuoteStatus.converted => (const Color(0xFFE8F8EE), AppTokens.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s10,
        vertical: AppTokens.s6,
      ),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(AppTokens.radiusRound),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: palette.$2,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final List<QuoteMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = kpiCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppTokens.s12,
            crossAxisSpacing: AppTokens.s12,
            childAspectRatio:
                constraints.maxWidth >= AppTokens.breakpointExpanded
                ? 1.9
                : 2.1,
          ),
          itemBuilder: (_, index) => _MetricCard(metric: metrics[index]),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final QuoteMetric metric;

  @override
  Widget build(BuildContext context) {
    final background = metric.highlight
        ? const Color(0xFFEAF2FF)
        : Colors.white;

    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              metric.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.s8),
            Text(
              metric.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: metric.highlight
                    ? AppTokens.brandBlueDark
                    : AppTokens.textPrimary,
              ),
            ),
            const SizedBox(height: AppTokens.s6),
            Text(
              metric.helpText,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({required this.pipeline});

  final List<QuotePipelineStage> pipeline;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pipeline comercial',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppTokens.s14),
            Row(
              children: [
                for (final stage in pipeline) ...[
                  Expanded(child: _PipelineStageWidget(stage: stage)),
                  if (stage != pipeline.last)
                    const Icon(
                      Icons.chevron_right,
                      color: AppTokens.cardBorder,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineStageWidget extends StatelessWidget {
  const _PipelineStageWidget({required this.stage});
  final QuotePipelineStage stage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          stage.count.toString(),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: AppTokens.brandBlue,
          ),
        ),
        Text(
          stage.label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        Text(
          money(stage.amount),
          style: const TextStyle(color: AppTokens.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
