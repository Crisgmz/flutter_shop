import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Window-size classification matching Material 3 adaptive layout guidance.
enum WindowClass { compact, medium, expanded }

/// Determine the current [WindowClass] from the given [width].
WindowClass windowClassOf(double width) {
  if (width < AppTokens.breakpointCompact) return WindowClass.compact;
  if (width < AppTokens.breakpointExpanded) return WindowClass.medium;
  return WindowClass.expanded;
}

/// A builder widget that rebuilds when the window class changes.
///
/// ```dart
/// ResponsiveBuilder(
///   compact: (context) => MobileLayout(),
///   medium:  (context) => TabletLayout(),
///   expanded: (context) => DesktopLayout(),
/// )
/// ```
///
/// If [medium] is omitted it falls back to [compact].
/// If [expanded] is omitted it falls back to [medium] (or [compact]).
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
  });

  final WidgetBuilder compact;
  final WidgetBuilder? medium;
  final WidgetBuilder? expanded;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wc = windowClassOf(width);

    return switch (wc) {
      WindowClass.expanded => (expanded ?? medium ?? compact)(context),
      WindowClass.medium => (medium ?? compact)(context),
      WindowClass.compact => compact(context),
    };
  }
}

/// Convenience extension on [BuildContext] for quick responsive checks.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  WindowClass get windowClass => windowClassOf(screenWidth);
  bool get isCompact => windowClass == WindowClass.compact;
  bool get isMedium => windowClass == WindowClass.medium;
  bool get isExpanded => windowClass == WindowClass.expanded;

  /// True when the sidebar should be shown as a persistent panel only when
  /// there is enough space for both navigation and comfortable content width.
  bool get showDesktopSidebar => screenWidth >= AppTokens.breakpointSidebar;

  /// True when the top-bar search field is visible.
  bool get showSearchBar => screenWidth >= AppTokens.breakpointSearch;

  /// True when user name/role is shown next to avatar.
  bool get showUserInfo => screenWidth >= AppTokens.breakpointUserInfo;
}
