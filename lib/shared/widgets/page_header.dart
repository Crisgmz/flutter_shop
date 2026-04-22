import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../responsive/responsive_layout.dart';

/// Consistent page header with title, description, and action buttons.
/// Stacks vertically on mobile, row on desktop.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.description,
    this.actions = const [],
  });

  final String title;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile) ...[
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppTokens.s4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTokens.textSecondary,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppTokens.s12),
            Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, children: actions),
          ],
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppTokens.s6),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ...actions.expand(
                (action) => [const SizedBox(width: AppTokens.s12), action],
              ),
            ],
          ),
        ],
      ],
    );
  }
}
