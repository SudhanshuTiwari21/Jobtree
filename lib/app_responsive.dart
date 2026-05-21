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

  /// Effective width for layout decisions when [BoxConstraints.maxWidth] may be unbounded.
  static double layoutWidth(BuildContext context, BoxConstraints constraints) {
    final maxW = constraints.maxWidth;
    if (maxW.isFinite && maxW > 0) return maxW;
    return contentInnerMaxWidth(MediaQuery.sizeOf(context).width);
  }

  static bool _isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < tablet;

  /// When true, prefer stacking banner actions vertically instead of a single [Row].
  static bool stackProfileBanner(BuildContext context, BoxConstraints constraints) {
    if (_isPhone(context)) return true;
    return layoutWidth(context, constraints) < 480;
  }

  /// When true, stack completion card (progress + copy + CTA) vertically.
  static bool stackCompletionCard(BuildContext context, BoxConstraints constraints) {
    if (_isPhone(context)) return true;
    return layoutWidth(context, constraints) < 440;
  }

  /// Stack job-card / dual CTAs vertically (phones and narrow cards).
  static bool stackJobCardActions(BuildContext context, BoxConstraints constraints) {
    if (_isPhone(context)) return true;
    final w = layoutWidth(context, constraints);
    if (!w.isFinite || w <= 0) return true;
    return w < 520;
  }

  /// Stack job title + live badge vertically on very narrow cards.
  static bool stackJobCardHeader(BuildContext context, BoxConstraints constraints) {
    if (_isPhone(context)) return layoutWidth(context, constraints) < 400;
    final w = layoutWidth(context, constraints);
    if (!w.isFinite || w <= 0) return true;
    return w < 340;
  }

  /// Tighter insets inside cards on small phones.
  static double cardPadding(double width) {
    final w = width.isFinite && width > 0 ? width : 360;
    return w < 360 ? 14.0 : 20.0;
  }

  /// Button label size inside job cards.
  static double jobCardButtonFontSize(double width) {
    final w = width.isFinite && width > 0 ? width : 360;
    return w < 360 ? 11.0 : 12.0;
  }

  /// Bottom nav label size on very narrow screens.
  static double bottomNavLabelFontSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) return 8;
    if (w < 380) return 9;
    return 10;
  }
}

/// Two action buttons: side-by-side on wide layouts, stacked on phones / narrow width.
class ResponsiveDualButtons extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const ResponsiveDualButtons({
    super.key,
    required this.children,
    this.gap = 10,
  }) : assert(children.length >= 1 && children.length <= 3);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = AppResponsive.stackJobCardActions(context, constraints);
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Circular progress with a centered percent label; stable across font scale and screen density.
class ProfilePercentRing extends StatelessWidget {
  final double size;
  final int percent;
  final double strokeWidth;
  final Color valueColor;
  final Color? trackColor;
  final Color textColor;

  const ProfilePercentRing({
    super.key,
    required this.size,
    required this.percent,
    this.strokeWidth = 4,
    this.valueColor = const Color(0xFFF9A825),
    this.trackColor,
    this.textColor = const Color(0xFF121A2C),
  });

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);
    final inset = strokeWidth + 5;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: clamped / 100,
              strokeWidth: strokeWidth,
              backgroundColor: trackColor ?? Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(valueColor),
            ),
          ),
          Positioned(
            left: inset,
            right: inset,
            top: inset,
            bottom: inset,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$clamped%',
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: size * 0.28,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    letterSpacing: -0.4,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
          child: SizedBox(
            width: maxInner,
            child: child,
          ),
        ),
      ),
    );
  }
}
