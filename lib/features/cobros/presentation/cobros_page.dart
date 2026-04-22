import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../clients/presentation/clients_providers.dart';
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
          const SizedBox(height: AppTokens.s24),
          receivablesAsync.when(
            data: (receivables) {
              final filtered = receivables
                  .where((item) {
                    if (query.isEmpty) return true;
                    final searchable = [
                      item.saleNumber,
                      item.clientName,
                      item.ncf ?? '',
                    ].join(' ').toLowerCase();
                    return searchable.contains(query);
                  })
                  .toList(growable: false);

              final totalDue = filtered.fold<double>(
                0,
                (sum, item) => sum + item.balanceDue,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KpisGrid(invoices: filtered.length, totalDue: totalDue),
                  const SizedBox(height: AppTokens.s24),
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
                              FlexTableColumn(label: 'NCF'),
                              FlexTableColumn(label: 'Total', numeric: true),
                              FlexTableColumn(label: 'Pagado', numeric: true),
                              FlexTableColumn(label: 'Balance', numeric: true),
                              FlexTableColumn(label: 'Acción'),
                            ],
                            rows: filtered
                                .map((item) => [
                                      Text(formatDate(item.saleDate)),
                                      Text(item.saleNumber),
                                      Text(
                                        item.clientName,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        item.ncf ?? '-',
                                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                      ),
                                      Text(money(item.totalAmount)),
                                      Text(money(item.paidAmount)),
                                      Text(
                                        money(item.balanceDue),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppTokens.destructive,
                                        ),
                                      ),
                                      FilledButton.icon(
                                        onPressed: () => _onRegisterPayment(item),
                                        icon: const Icon(Icons.attach_money, size: 16),
                                        label: const Text('Abonar'),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(0, 34),
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
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
