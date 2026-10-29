import 'package:flutter/material.dart';

import '../formatters/formatters.dart';

/// Botón "Desde – hasta": abre el selector de rango y, con un rango puesto,
/// muestra una X para volver a todas las fechas.
class DateRangeFilterButton extends StatelessWidget {
  const DateRangeFilterButton({
    super.key,
    required this.range,
    required this.onChanged,
    this.helpText = 'Desde – hasta',
  });

  /// Rango activo. Null = todas las fechas.
  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;

  /// Título del selector.
  final String helpText;

  Future<void> _pick(BuildContext context) async {
    final picked = await showAppDateRangePicker(
      context,
      initialRange: range,
      helpText: helpText,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final range = this.range;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.date_range_outlined, size: 18),
          label: Text(
            range == null
                ? 'Desde – hasta'
                : '${formatDate(range.start)} – ${formatDate(range.end)}',
          ),
        ),
        if (range != null)
          IconButton(
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Ver todas las fechas',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

/// Si [when] cae dentro de [range], contando días completos (el día "hasta"
/// entra entero). Sin rango, todo entra.
bool isWithinDateRange(DateTime when, DateTimeRange? range) {
  if (range == null) return true;
  final from = DateUtils.dateOnly(range.start);
  final end = range.end;
  final to = DateTime(end.year, end.month, end.day + 1);
  return !when.isBefore(from) && when.isBefore(to);
}

/// Selector de rango de fechas de la app: en pantallas anchas se muestra como
/// ventana centrada (el de Material ocupa toda la pantalla); en el celular
/// sigue a pantalla completa.
Future<DateTimeRange?> showAppDateRangePicker(
  BuildContext context, {
  DateTimeRange? initialRange,
  String helpText = 'Desde – hasta',
}) {
  final now = DateTime.now();
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime(now.year + 1, 12, 31),
    currentDate: now,
    initialDateRange: initialRange,
    helpText: helpText,
    saveText: 'Aplicar',
    cancelText: 'Cancelar',
    fieldStartLabelText: 'Desde',
    fieldEndLabelText: 'Hasta',
    builder: (context, child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      ),
    ),
  );
}
