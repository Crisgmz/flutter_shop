import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/date_range_filter_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el filtro Desde – hasta cuenta el día "hasta" completo', () {
    final range = DateTimeRange(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 30),
    );
    expect(isWithinDateRange(DateTime(2026, 9, 1), range), isTrue);
    expect(isWithinDateRange(DateTime(2026, 9, 30, 23, 59), range), isTrue);
    expect(isWithinDateRange(DateTime(2026, 10, 1), range), isFalse);
    expect(isWithinDateRange(DateTime(2026, 8, 31, 23, 59), range), isFalse);
    expect(isWithinDateRange(DateTime(2020, 1, 1), null), isTrue);
  });
}
