import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/expenses_repository.dart';
import 'expenses_providers.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesListProvider);
    final query = ref.watch(expensesSearchProvider).trim().toLowerCase();

    return ModulePage(
      title: 'Gastos',
      description: 'Registra egresos operativos para controlar caja diaria.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(expensesListProvider);
            ref.invalidate(expenseSuppliersProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onNewExpense,
          icon: const Icon(Icons.add_card_outlined, size: 18),
          label: const Text('Nuevo gasto'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                ref.read(expensesSearchProvider.notifier).state = value,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar por categoría, proveedor o descripción',
            ),
          ),
          const SizedBox(height: AppTokens.s24),
          expensesAsync.when(
            data: (expenses) {
              final filtered = expenses
                  .where((expense) {
                    if (query.isEmpty) return true;
                    final searchable = [
                      expense.category,
                      expense.supplierName ?? '',
                      expense.description ?? '',
                      expense.paymentMethod,
                    ].join(' ').toLowerCase();
                    return searchable.contains(query);
                  })
                  .toList(growable: false);

              final total = filtered.fold<double>(
                0,
                (sum, item) => sum + item.amount,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KpisGrid(count: filtered.length, total: total),
                  const SizedBox(height: AppTokens.s24),
                  DataTableShell(
                    title: 'Gastos (${filtered.length})',
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(AppTokens.s20),
                            child: Text(
                              'No hay gastos registrados.',
                              style: TextStyle(color: AppTokens.mutedForeground),
                            ),
                          )
                        : DataTable(
                            columns: const [
                              DataColumn(label: Text('Fecha')),
                              DataColumn(label: Text('Categoría')),
                              DataColumn(label: Text('Proveedor')),
                              DataColumn(label: Text('Método')),
                              DataColumn(label: Text('Descripción')),
                              DataColumn(label: Text('Monto'), numeric: true),
                            ],
                            rows: filtered
                                .map(
                                  (expense) => DataRow(
                                    cells: [
                                      DataCell(Text(formatDate(expense.expenseDate))),
                                      DataCell(Text(
                                        expense.category,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      )),
                                      DataCell(Text(expense.supplierName ?? '-')),
                                      DataCell(Text(_pretty(expense.paymentMethod))),
                                      DataCell(Text(expense.description ?? '-')),
                                      DataCell(Text(
                                        money(expense.amount),
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      )),
                                    ],
                                  ),
                                )
                                .toList(growable: false),
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar gastos: $error',
              onRetry: () => ref.invalidate(expensesListProvider),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onNewExpense() async {
    List<ExpenseSupplier> suppliers;
    try {
      suppliers = await ref.read(expenseSuppliersProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir formulario: $error')),
      );
      return;
    }

    if (!mounted) return;

    final input = await showDialog<ExpenseInput>(
      context: context,
      builder: (_) => _NewExpenseDialog(suppliers: suppliers),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(expensesRepositoryProvider);

    try {
      await repository.createExpense(input);
      if (!mounted) return;

      ref.invalidate(expensesListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gasto registrado.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar gasto: $error')),
      );
    }
  }
}

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.count, required this.total});

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Transacciones',
        value: count.toString(),
        icon: Icons.receipt_outlined,
        trend: 'Gastos registrados',
      ),
      KPICard(
        label: 'Total listado',
        value: money(total),
        icon: Icons.wallet_outlined,
        trend: 'Monto total',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppTokens.breakpointCompact) {
          return Column(
            children: [cards[0], const SizedBox(height: AppTokens.s12), cards[1]],
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

class _NewExpenseDialog extends StatefulWidget {
  const _NewExpenseDialog({required this.suppliers});

  final List<ExpenseSupplier> suppliers;

  @override
  State<_NewExpenseDialog> createState() => _NewExpenseDialogState();
}

class _NewExpenseDialogState extends State<_NewExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController(text: '0');

  String _paymentMethod = 'cash';
  String? _supplierId;
  DateTime _expenseDate = DateTime.now();

  @override
  void dispose() {
    _categoryController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: const Text('Nuevo gasto'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Categoría requerida';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _supplierId ?? '',
                  decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('Sin proveedor')),
                    ...widget.suppliers.map(
                      (supplier) => DropdownMenuItem<String>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _supplierId = (value == null || value.isEmpty) ? null : value,
                  ),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Método de pago'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                      DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                      DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
                      DropdownMenuItem(value: 'mobile', child: Text('Pago móvil')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _paymentMethod = value);
                    },
                  ),
                  TextFormField(
                    readOnly: true,
                    controller: TextEditingController(text: formatDate(_expenseDate)),
                    decoration: InputDecoration(
                      labelText: 'Fecha',
                      suffixIcon: IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Monto'),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed <= 0) return 'Monto inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }

  Widget _formRow(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children:
            children.expand((w) => [w, const SizedBox(height: 10)]).toList()
              ..removeLast(),
      );
    }
    return Row(
      children:
          children
              .expand((w) => [Expanded(child: w), const SizedBox(width: 10)])
              .toList()
            ..removeLast(),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _expenseDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      ExpenseInput(
        category: _categoryController.text,
        paymentMethod: _paymentMethod,
        amount: double.parse(_amountController.text),
        expenseDate: _expenseDate,
        description: _descriptionController.text,
        supplierId: _supplierId,
      ),
    );
  }
}

String _pretty(String value) {
  if (value.isEmpty) return '-';
  return value
      .split('_')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
