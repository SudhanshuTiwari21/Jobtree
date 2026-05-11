import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared breakpoints and layout helpers so screens adapt to phones, tablets, and foldables.
class AppResponsive {
  AppResponsive._();

  static const double tablet = 600;
  static const double desktop = 900;

  /// Horizontal inset from screen edges (after safe area).
  static double horizontalPadding(double screenWidth) {
    if (screenWidth >= desktop) return 40;
    if (screenWidth >= tablet) return 28;
    if (screenWidth >= 340) return 16;
    return 12;
  }

  /// Max content width inside [horizontalPadding] — keeps text and cards readable on large screens.
  static double contentInnerMaxWidth(double screenWidth) {
    final pad = horizontalPadding(screenWidth);
    final available = math.max(0.0, screenWidth - 2 * pad);
    if (screenWidth >= desktop) return math.min(720, available);
    if (screenWidth >= tablet) return math.min(640, available);
    return available;
  }

  /// When true, prefer stacking banner actions vertically instead of a single [Row].
  static bool stackProfileBanner(double width) => width < 420;

  /// When true, stack completion card (progress + copy + CTA) vertically.
  static bool stackCompletionCard(double width) => width < 400;
}

/// Centers content and caps width on tablets / desktop; applies responsive horizontal padding.
class ResponsiveContent extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;

  const ResponsiveContent({super.key, required this.child, this.margin});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = AppResponsive.horizontalPadding(w);
    final maxInner = AppResponsive.contentInnerMaxWidth(w);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxInner),
            child: child,
          ),
        ),
      ),
    );
  }
}
