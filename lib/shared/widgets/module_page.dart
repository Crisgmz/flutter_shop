import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../responsive/responsive_layout.dart';

/// Reusable scaffold for feature module pages.
///
/// Provides a consistent layout with:
/// - Optional header row with title, description, and action buttons
/// - Scrollable body area
/// - Consistent padding and spacing
///
/// ```dart
/// ModulePage(
///   title: 'Inventario',
///   description: 'Gestión de productos y categorías',
///   actions: [
///     FilledButton.icon(
///       onPressed: _add,
///       icon: Icon(Icons.add),
///       label: Text('Agregar'),
///     ),
///   ],
///   slivers: [
///     SliverToBoxAdapter(child: _statsRow()),
///     SliverList(...),
///   ],
/// )
/// ```
class ModulePage extends StatelessWidget {
  const ModulePage({
    super.key,
    this.title,
    this.description,
    this.actions = const [],
    this.slivers = const [],
    this.child,
    this.padding,
    this.headerSpacing = AppTokens.s16,
  }) : assert(
         child != null || slivers.length > 0,
         'Provide either child or slivers',
       );

  /// Page headline (shown above content).
  final String? title;

  /// Subtitle / description below the title.
  final String? description;

  /// Action buttons displayed to the right of the title on wide screens,
  /// or below on narrow screens.
  final List<Widget> actions;

  /// Sliver-based body. Use for pages with mixed scroll content.
  final List<Widget> slivers;

  /// Simple non-sliver child. If provided, it is placed in a
  /// [SliverToBoxAdapter] after the header.
  final Widget? child;

  /// Outer padding for the entire scrollable area.
  final EdgeInsetsGeometry? padding;

  /// Space between the header row and the body content.
  final double headerSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHeader = title != null || description != null || actions.isNotEmpty;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: padding ?? adaptivePadding(context),
          sliver: SliverMainAxisGroup(
            slivers: [
              if (hasHeader)
                SliverToBoxAdapter(child: _Header(this, theme)),
              if (hasHeader)
                SliverToBoxAdapter(
                  child: SizedBox(height: headerSpacing),
                ),
              if (child != null) SliverToBoxAdapter(child: child!),
              ...slivers,
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.page, this.theme);

  final ModulePage page;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < AppTokens.breakpointCompact;

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (page.title != null)
            Text(
              page.title!,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          if (page.description != null) ...[
            const SizedBox(height: AppTokens.s4),
            Text(
              page.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTokens.textSecondary,
              ),
            ),
          ],
          if (page.actions.isNotEmpty) ...[
            const SizedBox(height: AppTokens.s12),
            Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, children: page.actions),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (page.title != null)
                Text(
                  page.title!,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (page.description != null) ...[
                const SizedBox(height: AppTokens.s4),
                Text(
                  page.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (page.actions.isNotEmpty)
          Wrap(spacing: AppTokens.s8, children: page.actions),
      ],
    );
  }
}
