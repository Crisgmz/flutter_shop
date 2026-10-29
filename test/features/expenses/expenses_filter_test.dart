import 'package:flutter_app/features/expenses/data/expenses_repository.dart';
import 'package:flutter_app/features/expenses/presentation/expenses_providers.dart';
import 'package:flutter_test/flutter_test.dart';

ExpenseEntity _expense(
  String category,
  double amount, {
  String method = 'cash',
  String? description,
  String? supplier,
}) {
  return ExpenseEntity(
    id: '$category-$amount',
    category: category,
    description: description,
    paymentMethod: method,
    amount: amount,
    expenseDate: DateTime(2026, 10, 1),
    supplierName: supplier,
  );
}

void main() {
  final expenses = [
    _expense('Nómina', 5000, method: 'transfer', description: 'Juan'),
    _expense('nómina ', 3000, description: 'Pedro'),
    _expense('Agua', 100),
    _expense('Fundas', 390, supplier: 'Plásticos SRL'),
  ];

  group('filterExpenses', () {
    test('sin filtros devuelve todo', () {
      expect(filterExpenses(expenses), hasLength(4));
    });

    test('categoría ignora mayúsculas y espacios', () {
      final result = filterExpenses(
        expenses,
        categoryKey: expenseCategoryKey('NÓMINA'),
      );
      expect(result.map((e) => e.amount), [5000, 3000]);
    });

    test('método de pago', () {
      final result = filterExpenses(expenses, paymentMethod: 'transfer');
      expect(result.single.amount, 5000);
    });

    test('búsqueda en descripción y proveedor, combinada con categoría', () {
      expect(filterExpenses(expenses, search: 'pedro').single.amount, 3000);
      expect(filterExpenses(expenses, search: 'plásticos').single.amount, 390);
      expect(
        filterExpenses(
          expenses,
          search: 'juan',
          categoryKey: expenseCategoryKey('Agua'),
        ),
        isEmpty,
      );
    });
  });

  test('summarizeByCategory agrupa y ordena por monto', () {
    final summary = summarizeByCategory(expenses);
    expect(summary.map((c) => c.label), ['Nómina', 'Fundas', 'Agua']);
    expect(summary.first.count, 2);
    expect(summary.first.total, 8000);
  });
}
