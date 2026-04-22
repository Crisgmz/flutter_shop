import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Responsive layout helper that switches between mobile/tablet/desktop builds.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppTokens.breakpointCompact;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= AppTokens.breakpointCompact && w < AppTokens.breakpointExpanded;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppTokens.breakpointExpanded;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= AppTokens.breakpointExpanded) return desktop;
    if (width >= AppTokens.breakpointCompact) return tablet ?? mobile;
    return mobile;
  }
}

/// Adaptive padding that tightens on smaller screens.
EdgeInsets adaptivePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < AppTokens.breakpointCompact) {
    return const EdgeInsets.all(AppTokens.s12);
  }
  if (width < AppTokens.breakpointMedium) {
    return const EdgeInsets.all(AppTokens.s16);
  }
  return const EdgeInsets.all(AppTokens.s20);
}

/// Returns the number of KPI columns for the given width.
int kpiCrossAxisCount(double width) {
  if (width >= 1280) return 4;
  if (width >= 1024) return 4;
  if (width >= 760) return 2;
  return 1;
}
