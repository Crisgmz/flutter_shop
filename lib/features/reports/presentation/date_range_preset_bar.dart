import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/date_range_filter_button.dart';
import '../domain/report_category.dart';

/// Chips de rango rápido (Hoy, Ayer, Esta semana, Este mes, Mes anterior) +
/// botón "Personalizado" con selector de rango. Sin marco propio: quien lo
/// usa decide si va en una tarjeta.
class DateRangePresetBar extends StatelessWidget {
  const DateRangePresetBar({
    super.key,
    required this.range,
    required this.onChanged,
  });

  final ReportDateRange range;
  final ValueChanged<ReportDateRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppTokens.s8,
      runSpacing: AppTokens.s8,
      children: [
        for (final preset in ReportDateRangePreset.values)
          if (preset != ReportDateRangePreset.customRange)
            ChoiceChip(
              label: Text(preset.label),
              selected: range.preset == preset,
              onSelected: (_) => onChanged(ReportDateRange.fromPreset(preset)),
            ),
        OutlinedButton.icon(
          onPressed: () => _pickCustomRange(context),
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(
            range.preset == ReportDateRangePreset.customRange
                ? '${formatDate(range.from)} → ${formatDate(range.to)}'
                : 'Personalizado',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
    final current = Text(
      '${formatDate(range.from)} → ${formatDate(range.to)}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppTokens.mutedForeground,
        fontWeight: FontWeight.w600,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppTokens.breakpointCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              presets,
              const SizedBox(height: AppTokens.s8),
              current,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: presets),
            const SizedBox(width: AppTokens.s12),
            const Icon(
              Icons.event_outlined,
              size: 16,
              color: AppTokens.mutedForeground,
            ),
            const SizedBox(width: AppTokens.s4),
            current,
          ],
        );
      },
    );
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final picked = await showAppDateRangePicker(
      context,
      initialRange: DateTimeRange(start: range.from, end: range.to),
    );
    if (picked == null) return;
    onChanged(
      ReportDateRange.fromPreset(
        ReportDateRangePreset.customRange,
        customFrom: picked.start,
        customTo: picked.end,
      ),
    );
  }
}
