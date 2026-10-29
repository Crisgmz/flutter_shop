import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Pie de tabla "Mostrando 1 – 25 de N  ‹ ›".
///
/// [totalCount] es opcional: con paginación en servidor solo se sabe si hay
/// más ([hasMore]); con paginación en cliente se conoce el total.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.pageIndex,
    required this.pageSize,
    required this.rowsInPage,
    required this.hasMore,
    required this.onPageChanged,
    this.totalCount,
  });

  final int pageIndex;
  final int pageSize;
  final int rowsInPage;
  final bool hasMore;
  final int? totalCount;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final first = pageIndex * pageSize + 1;
    final last = first + rowsInPage - 1;
    final total = totalCount;
    final label = rowsInPage == 0
        ? 'Sin resultados'
        : total == null
            ? 'Mostrando $first – $last'
            : 'Mostrando $first – $last de $total';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTokens.mutedForeground,
          ),
        ),
        const SizedBox(width: AppTokens.s12),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: pageIndex == 0 ? null : () => onPageChanged(pageIndex - 1),
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: hasMore ? () => onPageChanged(pageIndex + 1) : null,
          icon: const Icon(Icons.chevron_right, size: 20),
        ),
      ],
    );
  }
}
