import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../data/fiscal_consumo_summary.dart';

/// "Resumen Facturas Consumo" en pantalla, con las mismas líneas que el
/// formulario de la DGII (y que el PDF/Excel). Lo usan Comprobantes y el 607.
class FiscalConsumoSummaryPanel extends StatelessWidget {
  const FiscalConsumoSummaryPanel({
    super.key,
    required this.summary,
    this.rangeNote,
    this.padding = const EdgeInsets.all(AppTokens.s20),
  });

  final FiscalConsumoSummary summary;

  final EdgeInsetsGeometry padding;

  /// Texto extra junto al rango de fechas (ej. "mes en curso").
  final String? rangeNote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '${formatDate(summary.from)} – ${formatDate(summary.to)}'
                      '${rangeNote == null ? '' : ' ($rangeNote)'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTokens.mutedForeground,
                      ),
                    ),
                  ),
                  Text(
                    summary.period,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s12),
              _SummaryTable(summary: summary),
              const SizedBox(height: AppTokens.s8),
              Text(
                'Solo comprobantes de consumo (B02 / E32) del período.'
                '${summary.cancelledCount > 0 ? ' No incluye ${summary.cancelledCount} anulado(s).' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTokens.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable({required this.summary});

  final FiscalConsumoSummary summary;

  @override
  Widget build(BuildContext context) {
    const cellPadding = EdgeInsets.symmetric(
      horizontal: AppTokens.s12,
      vertical: AppTokens.s8,
    );
    final sectionColor = AppTokens.success.withValues(alpha: 0.22);

    TableRow section(String title) => TableRow(
          decoration: BoxDecoration(color: sectionColor),
          children: [
            const Padding(
              padding: cellPadding,
              child: Text('*', textAlign: TextAlign.right),
            ),
            Padding(
              padding: cellPadding,
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox.shrink(),
          ],
        );

    TableRow line(FiscalSummaryLine line) {
      final value = line.amount;
      return TableRow(
        children: [
          Padding(
            padding: cellPadding,
            child: Text('${line.line}', textAlign: TextAlign.right),
          ),
          Padding(padding: cellPadding, child: Text(line.label)),
          Padding(
            padding: cellPadding,
            child: Text(
              value == null
                  ? ''
                  : line.isCount
                      ? qty(value.round())
                      : moneyPlain(value),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    return Table(
      border: TableBorder.all(color: AppTokens.border),
      columnWidths: const {
        0: FixedColumnWidth(48),
        1: FlexColumnWidth(),
        2: FixedColumnWidth(160),
      },
      children: [
        section(FiscalConsumoSummary.generalSectionTitle),
        for (final l in summary.generalLines) line(l),
        section(FiscalConsumoSummary.saleTypeSectionTitle),
        for (final l in summary.saleTypeLines) line(l),
      ],
    );
  }
}
