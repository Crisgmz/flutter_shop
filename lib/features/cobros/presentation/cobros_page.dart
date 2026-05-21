import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../sales/presentation/sales_providers.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/cobros_repository.dart';
import 'cobros_providers.dart';

class CobrosPage extends ConsumerStatefulWidget {
  const CobrosPage({super.key});

  @override
  ConsumerState<CobrosPage> createState() => _CobrosPageState();
}

class _CobrosPageState extends ConsumerState<CobrosPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receivablesAsync = ref.watch(cobrosReceivablesProvider);
    final paymentsAsync = ref.watch(cobrosPaymentsProvider);
    final query = ref.watch(cobrosSearchProvider).trim().toLowerCase();
    final filterMode = ref.watch(cobrosFilterProvider);
    final warnDays =
        ref.watch(appSettingsProvider).valueOrNull?.creditWarnDays ?? 7;

    return ModulePage(
      title: 'Cobros',
      description: 'Gestiona cuentas por cobrar y pagos recibidos.',
      actions: [
        OutlinedButton.icon(
          onPressed: _refreshCobrosData,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                ref.read(cobrosSearchProvider.notifier).state = value,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar por cliente, venta o NCF',
            ),
          ),
          const SizedBox(height: AppTokens.s16),
          receivablesAsync.when(
            data: (receivables) {
              // Conteos por categoría (sobre TODAS las cuentas, no las filtradas
              // por texto) — alimentan los badges del segmented button.
              final allNearDue =
                  receivables.where((e) => e.isNearDue(warnDays)).length;
              final allOverdue =
                  receivables.where((e) => e.isOverdue).length;

              // Filtro por texto + por modo.
              final filtered = receivables.where((item) {
                if (query.isNotEmpty) {
                  final searchable = [
                    item.saleNumber,
                    item.clientName,
                    item.ncf ?? '',
                  ].join(' ').toLowerCase();
                  if (!searchable.contains(query)) return false;
                }
                switch (filterMode) {
                  case ReceivablesFilter.nearDue:
                    return item.isNearDue(warnDays);
                  case ReceivablesFilter.overdue:
                    return item.isOverdue;
                  case ReceivablesFilter.all:
                    return true;
                }
              }).toList(growable: false);

              final totalDue = filtered.fold<double>(
                0,
                (sum, item) => sum + item.balanceDue,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KpisGrid(invoices: filtered.length, totalDue: totalDue),
                  const SizedBox(height: AppTokens.s16),
                  _ReceivablesFilterBar(
                    active: filterMode,
                    countAll: receivables.length,
                    countNearDue: allNearDue,
                    countOverdue: allOverdue,
                    onChanged: (mode) =>
                        ref.read(cobrosFilterProvider.notifier).state = mode,
                  ),
                  const SizedBox(height: AppTokens.s16),
                  DataTableShell(
                    scrollable: false,
                    title: 'Cuentas por cobrar',
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(AppTokens.s20),
                            child: Text(
                              'No hay cuentas por cobrar.',
                              style: TextStyle(color: AppTokens.mutedForeground),
                            ),
                          )
                        : FlexTable(
                            columns: const [
                              FlexTableColumn(label: 'Fecha'),
                              FlexTableColumn(label: 'Venta', flex: 2),
                              FlexTableColumn(label: 'Cliente', flex: 2),
                              FlexTableColumn(label: 'Vence'),
                              FlexTableColumn(label: 'Total', numeric: true),
                              FlexTableColumn(label: 'Balance', numeric: true),
                              FlexTableColumn(label: 'Acción', flex: 2),
                            ],
                            rows: filtered
                                .map((item) => [
                                      Text(formatDate(item.saleDate)),
                                      Text(item.saleNumber),
                                      Text(
                                        item.clientName,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      _DueDateCell(
                                        sale: item,
                                        warnDays: warnDays,
                                      ),
                                      Text(money(item.totalAmount)),
                                      Text(
                                        money(item.balanceDue),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppTokens.destructive,
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            tooltip: 'Ver factura',
                                            onPressed: () =>
                                                _onViewInvoice(item),
                                            icon: const Icon(
                                                Icons.visibility_outlined,
                                                size: 18),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          IconButton(
                                            tooltip: 'Extender plazo',
                                            onPressed: () =>
                                                _onExtendDueDate(item),
                                            icon: const Icon(
                                                Icons.event_repeat_outlined,
                                                size: 18),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          IconButton(
                                            tooltip: 'Reimprimir',
                                            onPressed: () =>
                                                _onReprintInvoice(item),
                                            icon: const Icon(
                                                Icons.print_outlined,
                                                size: 18),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          FilledButton.icon(
                                            onPressed: () =>
                                                _onRegisterPayment(item),
                                            icon: const Icon(
                                                Icons.attach_money,
                                                size: 16),
                                            label: const Text('Abonar'),
                                            style: FilledButton.styleFrom(
                                              minimumSize:
                                                  const Size(0, 34),
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 10),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ])
                                .toList(growable: false),
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar cuentas por cobrar: $error',
              onRetry: _refreshCobrosData,
            ),
          ),
          const SizedBox(height: AppTokens.s24),
          const _CustomerBalancesPanel(),
          const SizedBox(height: AppTokens.s24),
          paymentsAsync.when(
            data: (payments) {
              return DataTableShell(
                scrollable: false,
                title: 'Pagos recibidos recientes',
                child: payments.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppTokens.s20),
                        child: Text(
                          'No hay pagos registrados.',
                          style: TextStyle(color: AppTokens.mutedForeground),
                        ),
                      )
                    : FlexTable(
                        columns: const [
                          FlexTableColumn(label: 'Fecha'),
                          FlexTableColumn(label: 'Venta', flex: 2),
                          FlexTableColumn(label: 'Cliente', flex: 2),
                          FlexTableColumn(label: 'Método'),
                          FlexTableColumn(label: 'Monto', numeric: true),
                          FlexTableColumn(label: 'Referencia', flex: 2),
                        ],
                        rows: payments
                            .map((payment) => [
                                  Text(formatDate(payment.paidAt)),
                                  Text(payment.saleNumber),
                                  Text(payment.clientName),
                                  Text(_pretty(payment.paymentMethod)),
                                  Text(
                                    money(payment.amount),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  Text(payment.reference ?? '-'),
                                ])
                            .toList(growable: false),
                      ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar pagos: $error',
              onRetry: _refreshCobrosData,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshCobrosData() async {
    ref.invalidate(cobrosReceivablesProvider);
    ref.invalidate(cobrosPaymentsProvider);
    await Future.wait([
      ref.read(cobrosReceivablesProvider.future),
      ref.read(cobrosPaymentsProvider.future),
    ]);
  }

  Future<void> _onRegisterPayment(ReceivableSale sale) async {
    final input = await showDialog<CobrosPaymentInput>(
      context: context,
      builder: (_) => _RegisterPaymentDialog(sale: sale),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(cobrosRepositoryProvider);

    try {
      await repository.registerPayment(input);
      if (!mounted) return;

      ref.invalidate(cobrosReceivablesProvider);
      ref.invalidate(cobrosPaymentsProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pago aplicado a ${sale.saleNumber}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar pago: $error')),
      );
    }
  }

  /// Abre un diálogo con el detalle de la venta (resumen + opción de imprimir).
  Future<void> _onViewInvoice(ReceivableSale sale) async {
    await showDialog(
      context: context,
      builder: (_) => _InvoiceViewerDialog(sale: sale),
    );
  }

  /// Imprime directamente sin pasar por el viewer (reusa
  /// `SalesRepository.prepareCompletedSalePrintJob` + `PrintReceiptDialog`).
  Future<void> _onReprintInvoice(ReceivableSale sale) async {
    try {
      final salesRepo = ref.read(salesRepositoryProvider);
      final job = await salesRepo.prepareCompletedSalePrintJob(
        saleId: sale.id,
      );
      if (!mounted) return;
      if (job == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo preparar la factura (¿venta no completada?).',
            ),
          ),
        );
        return;
      }
      await PrintReceiptDialog.show(context, job);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al preparar impresión: $e')),
      );
    }
  }

  /// Diálogo para postergar `due_date` sumándole N días o eligiendo una
  /// fecha concreta.
  Future<void> _onExtendDueDate(ReceivableSale sale) async {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final defaultDays = settings?.creditDefaultDays ?? 30;
    final result = await showDialog<_ExtendResult>(
      context: context,
      builder: (_) => _ExtendDueDialog(
        sale: sale,
        suggestedDays: defaultDays,
      ),
    );
    if (result == null || !mounted) return;

    try {
      await ref.read(cobrosRepositoryProvider).extendCreditDueDate(
            saleId: sale.id,
            additionalDays: result.additionalDays,
            newDueDate: result.newDueDate,
          );
      if (!mounted) return;
      ref.invalidate(cobrosReceivablesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plazo de ${sale.saleNumber} actualizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo extender el plazo: $e')),
      );
    }
  }
}

class _ReceivablesFilterBar extends StatelessWidget {
  const _ReceivablesFilterBar({
    required this.active,
    required this.countAll,
    required this.countNearDue,
    required this.countOverdue,
    required this.onChanged,
  });

  final ReceivablesFilter active;
  final int countAll;
  final int countNearDue;
  final int countOverdue;
  final ValueChanged<ReceivablesFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ReceivablesFilter>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 13),
      ),
      segments: [
        ButtonSegment(
          value: ReceivablesFilter.all,
          icon: const Icon(Icons.list_alt_outlined, size: 16),
          label: Text('Todos ($countAll)'),
        ),
        ButtonSegment(
          value: ReceivablesFilter.nearDue,
          icon: const Icon(Icons.schedule_outlined, size: 16),
          label: Text('Próximos a vencer ($countNearDue)'),
        ),
        ButtonSegment(
          value: ReceivablesFilter.overdue,
          icon: const Icon(Icons.warning_amber_rounded, size: 16),
          label: Text('Vencidos ($countOverdue)'),
        ),
      ],
      selected: {active},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    );
  }
}

class _DueDateCell extends StatelessWidget {
  const _DueDateCell({required this.sale, required this.warnDays});

  final ReceivableSale sale;
  final int warnDays;

  @override
  Widget build(BuildContext context) {
    final due = sale.dueDate;
    if (due == null) {
      return const Text(
        'Sin plazo',
        style: TextStyle(color: AppTokens.mutedForeground, fontSize: 12),
      );
    }
    final days = sale.daysUntilDue!;
    final isOverdue = days < 0;
    final isNear = !isOverdue && days <= warnDays;

    final color = isOverdue
        ? AppTokens.destructive
        : isNear
            ? AppTokens.warning
            : AppTokens.mutedForeground;

    final subtitle = isOverdue
        ? 'Vencido hace ${-days}d'
        : days == 0
            ? 'Vence hoy'
            : 'En ${days}d';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatDate(due),
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
        ),
        Text(
          subtitle,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }
}

class _ExtendResult {
  _ExtendResult({this.additionalDays, this.newDueDate});
  final int? additionalDays;
  final DateTime? newDueDate;
}

class _ExtendDueDialog extends StatefulWidget {
  const _ExtendDueDialog({required this.sale, required this.suggestedDays});

  final ReceivableSale sale;
  final int suggestedDays;

  @override
  State<_ExtendDueDialog> createState() => _ExtendDueDialogState();
}

class _ExtendDueDialogState extends State<_ExtendDueDialog> {
  late final TextEditingController _daysCtrl;
  DateTime? _pickedDate;
  bool _useDays = true;

  @override
  void initState() {
    super.initState();
    _daysCtrl = TextEditingController(text: widget.suggestedDays.toString());
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentDue = widget.sale.dueDate;
    return AlertDialog(
      title: Text('Extender plazo · ${widget.sale.saleNumber}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentDue == null
                  ? 'Esta venta no tenía fecha de vencimiento.'
                  : 'Vence actualmente: ${formatDate(currentDue)}',
              style: const TextStyle(
                color: AppTokens.mutedForeground,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppTokens.s16),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: true,
              groupValue: _useDays,
              onChanged: (v) => setState(() => _useDays = v ?? true),
              title: const Text('Sumar días'),
            ),
            if (_useDays)
              TextField(
                controller: _daysCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Días a añadir',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: false,
              groupValue: _useDays,
              onChanged: (v) => setState(() => _useDays = v ?? false),
              title: const Text('Elegir fecha exacta'),
            ),
            if (!_useDays)
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _pickedDate ?? currentDue ?? now,
                    firstDate: now.subtract(const Duration(days: 365)),
                    lastDate: now.add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) {
                    setState(() => _pickedDate = picked);
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  _pickedDate == null
                      ? 'Seleccionar fecha'
                      : formatDate(_pickedDate!),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_useDays) {
              final days = int.tryParse(_daysCtrl.text.trim()) ?? 0;
              if (days <= 0) return;
              Navigator.pop(
                context,
                _ExtendResult(additionalDays: days),
              );
            } else {
              if (_pickedDate == null) return;
              Navigator.pop(
                context,
                _ExtendResult(newDueDate: _pickedDate),
              );
            }
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _InvoiceViewerDialog extends ConsumerWidget {
  const _InvoiceViewerDialog({required this.sale});

  final ReceivableSale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppTokens.s24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      color: AppTokens.primary),
                  const SizedBox(width: AppTokens.s8),
                  Expanded(
                    child: Text(
                      'Factura ${sale.saleNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const Divider(),
              _kv('Cliente', sale.clientName),
              _kv('Fecha', formatDate(sale.saleDate)),
              if (sale.ncf != null) _kv('NCF', sale.ncf!),
              _kv('Total', money(sale.totalAmount),
                  highlight: true),
              _kv('Pagado', money(sale.paidAmount)),
              _kv('Balance', money(sale.balanceDue), danger: true),
              const SizedBox(height: AppTokens.s16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cerrar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          final salesRepo =
                              ref.read(salesRepositoryProvider);
                          final job = await salesRepo
                              .prepareCompletedSalePrintJob(
                                  saleId: sale.id);
                          if (!context.mounted) return;
                          if (job == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'No se pudo preparar la factura.'),
                              ),
                            );
                            return;
                          }
                          await PrintReceiptDialog.show(context, job);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      },
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Reimprimir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value,
      {bool highlight = false, bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTokens.mutedForeground)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w700,
              fontSize: highlight ? 16 : 14,
              color: danger
                  ? AppTokens.destructive
                  : (highlight ? AppTokens.primary : AppTokens.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.invoices, required this.totalDue});

  final int invoices;
  final double totalDue;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Facturas pendientes',
        value: invoices.toString(),
        icon: Icons.receipt_long_outlined,
        trend: 'Por cobrar',
      ),
      KPICard(
        label: 'Total por cobrar',
        value: money(totalDue),
        icon: Icons.access_time_rounded,
        trend: 'Balance pendiente',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppTokens.breakpointCompact) {
          return Column(
            children: [
              cards[0],
              const SizedBox(height: AppTokens.s12),
              cards[1],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

class _RegisterPaymentDialog extends StatefulWidget {
  const _RegisterPaymentDialog({required this.sale});

  final ReceivableSale sale;

  @override
  State<_RegisterPaymentDialog> createState() => _RegisterPaymentDialogState();
}

class _RegisterPaymentDialogState extends State<_RegisterPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.sale.balanceDue.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar abono'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Venta: ${widget.sale.saleNumber}\nBalance: ${money(widget.sale.balanceDue)}',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Monto a abonar'),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Monto inválido';
                  }
                  if (amount > widget.sale.balanceDue) {
                    return 'No puede exceder el balance';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Método de pago'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                  DropdownMenuItem(
                    value: 'transfer',
                    child: Text('Transferencia'),
                  ),
                  DropdownMenuItem(value: 'mobile', child: Text('Pago móvil')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _paymentMethod = value);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _referenceController,
                decoration: const InputDecoration(labelText: 'Referencia'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Nota'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Aplicar pago')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      CobrosPaymentInput(
        saleId: widget.sale.id,
        amount: double.parse(_amountController.text),
        paymentMethod: _paymentMethod,
        reference: _referenceController.text,
        notes: _notesController.text,
      ),
    );
  }
}

class _CustomerBalancesPanel extends ConsumerWidget {
  const _CustomerBalancesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(customerBalancesProvider);

    return DataTableShell(
      scrollable: false,
      title: 'Saldos por cliente',
      child: balancesAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Ningún cliente tiene saldo pendiente.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            );
          }

          final totalDue =
              items.fold<double>(0, (sum, i) => sum + i.balanceDue);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s20, AppTokens.s12, AppTokens.s20, 0),
                child: Text(
                  '${items.length} clientes · ${money(totalDue)} total pendiente',
                  style: const TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 13,
                  ),
                ),
              ),
              FlexTable(
                columns: const [
                  FlexTableColumn(label: 'Cliente', flex: 2),
                  FlexTableColumn(label: 'Teléfono'),
                  FlexTableColumn(label: 'Ventas', numeric: true),
                  FlexTableColumn(label: 'Total ventas', numeric: true),
                  FlexTableColumn(label: 'Límite crédito', numeric: true),
                  FlexTableColumn(label: 'Saldo', numeric: true),
                  FlexTableColumn(label: 'Última venta'),
                ],
                rows: items
                    .map((item) => [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayName,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (item.companyName != null &&
                                  item.displayName != item.fullName)
                                Text(
                                  item.fullName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTokens.mutedForeground,
                                  ),
                                ),
                            ],
                          ),
                          Text(item.phone ?? '-'),
                          Text(item.salesCount.toString()),
                          Text(money(item.totalSalesAmount)),
                          Text(
                            item.creditLimit > 0 ? money(item.creditLimit) : '—',
                            style: TextStyle(
                              color: item.overLimit ? AppTokens.destructive : null,
                            ),
                          ),
                          Text(
                            money(item.balanceDue),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTokens.destructive,
                            ),
                          ),
                          Text(
                            item.lastSaleAt == null ? '—' : formatDate(item.lastSaleAt!),
                          ),
                        ])
                    .toList(growable: false),
              ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(AppTokens.s20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Text(
            'No se pudieron cargar saldos: $error',
            style: const TextStyle(color: AppTokens.destructive),
          ),
        ),
      ),
    );
  }
}

String _pretty(String value) {
  if (value.isEmpty) return '-';
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
