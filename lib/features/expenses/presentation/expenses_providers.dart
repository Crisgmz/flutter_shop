import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../reports/domain/report_category.dart';
import '../data/expenses_repository.dart';

/// Filas por página en la tabla de gastos.
const expensesPageSize = 25;

final expensesSearchProvider = StateProvider<String>((ref) => '');

/// Rango de fechas (default: este mes). Se consulta en el servidor.
final expensesDateRangeProvider = StateProvider<ReportDateRange>((ref) {
  return ReportDateRange.fromPreset(ReportDateRangePreset.thisMonth);
});

/// Categoría seleccionada ([expenseCategoryKey]). Null = todas.
final expensesCategoryFilterProvider = StateProvider<String?>((ref) => null);

/// Método de pago seleccionado (`cash`, `card`...). Null = todos.
final expensesMethodFilterProvider = StateProvider<String?>((ref) => null);

final expensesPageIndexProvider = StateProvider<int>((ref) => 0);

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ExpensesRepository(client);
});

/// Todos los gastos del rango de fechas activo.
final expensesListProvider = FutureProvider<List<ExpenseEntity>>((ref) async {
  final repository = ref.watch(expensesRepositoryProvider);
  final range = ref.watch(expensesDateRangeProvider);
  return repository.fetchExpenses(from: range.from, to: range.to);
});

/// Gastos del rango después de aplicar búsqueda, categoría y método.
/// Es la fuente de la tabla, los totales y la exportación.
final expensesFilteredProvider = Provider<AsyncValue<List<ExpenseEntity>>>((
  ref,
) {
  final search = ref.watch(expensesSearchProvider);
  final category = ref.watch(expensesCategoryFilterProvider);
  final method = ref.watch(expensesMethodFilterProvider);
  return ref
      .watch(expensesListProvider)
      .whenData(
        (expenses) => filterExpenses(
          expenses,
          search: search,
          categoryKey: category,
          paymentMethod: method,
        ),
      );
});

final expenseSuppliersProvider = FutureProvider<List<ExpenseSupplier>>((
  ref,
) async {
  final repository = ref.watch(expensesRepositoryProvider);
  return repository.fetchSuppliers();
});

final expenseCategoriesProvider = FutureProvider<List<String>>((ref) async {
  final repository = ref.watch(expensesRepositoryProvider);
  return repository.fetchCategories();
});

/// Clave de agrupación de categoría: las categorías son texto libre, así que
/// "Nómina", "nómina " y "NÓMINA" cuentan como la misma.
String expenseCategoryKey(String category) => category.trim().toLowerCase();

List<ExpenseEntity> filterExpenses(
  List<ExpenseEntity> expenses, {
  String search = '',
  String? categoryKey,
  String? paymentMethod,
}) {
  final query = search.trim().toLowerCase();
  return expenses
      .where((expense) {
        if (categoryKey != null &&
            expenseCategoryKey(expense.category) != categoryKey) {
          return false;
        }
        if (paymentMethod != null && expense.paymentMethod != paymentMethod) {
          return false;
        }
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
}

/// Total y cantidad por categoría, ordenado de mayor a menor monto.
class ExpenseCategorySummary {
  const ExpenseCategorySummary({
    required this.key,
    required this.label,
    required this.count,
    required this.total,
  });

  final String key;
  final String label;
  final int count;
  final double total;
}

List<ExpenseCategorySummary> summarizeByCategory(List<ExpenseEntity> expenses) {
  final labels = <String, String>{};
  final counts = <String, int>{};
  final totals = <String, double>{};
  for (final expense in expenses) {
    final key = expenseCategoryKey(expense.category);
    labels.putIfAbsent(key, () => expense.category.trim());
    counts[key] = (counts[key] ?? 0) + 1;
    totals[key] = (totals[key] ?? 0) + expense.amount;
  }
  return [
    for (final key in labels.keys)
      ExpenseCategorySummary(
        key: key,
        label: labels[key]!.isEmpty ? 'Sin categoría' : labels[key]!,
        count: counts[key]!,
        total: totals[key]!,
      ),
  ]..sort((a, b) => b.total.compareTo(a.total));
}
