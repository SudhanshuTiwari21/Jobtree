import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared breakpoints and layout helpers so screens adapt to phones, tablets, and foldables.
class AppResponsive {
  AppResponsive._();

  /// Yellow accent border used on owner home profile / job cards.
  static const Color ownerHomeCardBorder = Color(0xFFFFE082);

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

  /// [EdgeInsets.all] for cards / tiles using [cardPadding].
  static EdgeInsets cardPaddingInsets(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return EdgeInsets.all(cardPadding(w));
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

  /// Horizontal padding for full-screen forms (job post, edit profile, etc.).
  static EdgeInsets formScreenPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return EdgeInsets.symmetric(horizontal: horizontalPadding(w));
  }

  /// Stack side-by-side option cards (full-time/part-time, etc.) on narrow width.
  static bool stackDualOptionCards(BuildContext context, BoxConstraints constraints) {
    final w = layoutWidth(context, constraints);
    if (!w.isFinite || w <= 0) return true;
    return w < 480;
  }

  /// Use [Wrap] for gender / pill chips instead of a single [Row].
  static bool wrapChoiceChips(BuildContext context, BoxConstraints constraints) {
    final w = layoutWidth(context, constraints);
    if (!w.isFinite || w <= 0) return true;
    return w < 420;
  }

  /// Footer bar padding (save / continue buttons).
  static EdgeInsets formFooterPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = horizontalPadding(w);
    return EdgeInsets.fromLTRB(h, 16, h, 16);
  }

  /// Compact card padding for option tiles on small phones.
  static EdgeInsets optionCardPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) return const EdgeInsets.symmetric(vertical: 14, horizontal: 10);
    if (w < 400) return const EdgeInsets.symmetric(vertical: 16, horizontal: 12);
    return const EdgeInsets.symmetric(vertical: 20, horizontal: 16);
  }

  static double optionCardIconSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w < 360 ? 28.0 : 32.0;
  }

  static double optionCardLabelSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w < 360 ? 13.0 : 14.0;
  }

  /// Stack salary label + selected range on very narrow screens.
  static bool stackSalaryHeader(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 360;
  }

  /// Title size on form screens.
  static double formTitleFontSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) return 20;
    if (w < 380) return 22;
    return 24;
  }

  /// Large marketing / OTP headings.
  static double pageHeadingFontSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) return 22;
    if (w < 380) return 24;
    return 28;
  }

  /// OTP digit boxes and similar.
  static double otpDigitFontSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w < 360 ? 22.0 : 24.0;
  }

  /// Uniform screen padding (replaces hard-coded 24px on phones).
  static EdgeInsets screenPaddingAll(
    BuildContext context, {
    double vertical = 24,
  }) {
    final h = horizontalPadding(MediaQuery.sizeOf(context).width);
    return EdgeInsets.symmetric(horizontal: h, vertical: vertical);
  }

  /// [SingleChildScrollView] / list padding with responsive horizontal insets.
  static EdgeInsets scrollScreenPadding(
    BuildContext context, {
    double top = 0,
    double bottom = 24,
  }) {
    final h = horizontalPadding(MediaQuery.sizeOf(context).width);
    return EdgeInsets.fromLTRB(h, top, h, bottom);
  }

  /// Horizontal + custom vertical (e.g. banner bars).
  static EdgeInsets screenPaddingHV(
    BuildContext context, {
    required double vertical,
  }) {
    final h = horizontalPadding(MediaQuery.sizeOf(context).width);
    return EdgeInsets.symmetric(horizontal: h, vertical: vertical);
  }

  /// Gap between staff-count / triple buttons.
  static double compactRowGap(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 360 ? 8.0 : 12.0;
  }

  /// Clamps system font scale so layouts stay stable on all phones.
  static TextScaler clampTextScaler(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scale = mq.textScaler.scale(1.0);
    const min = 0.92;
    const max = 1.28;
    if (scale <= min) return TextScaler.linear(min);
    if (scale >= max) return TextScaler.linear(max);
    return mq.textScaler;
  }
}

/// Convenient access: `context.rPad`, `context.rFooterPad`, etc.
extension JobtreeResponsiveContext on BuildContext {
  double get rScreenWidth => MediaQuery.sizeOf(this).width;

  EdgeInsets get rPad => AppResponsive.formScreenPadding(this);

  EdgeInsets rPadV(double vertical) =>
      AppResponsive.screenPaddingHV(this, vertical: vertical);

  EdgeInsets get rFooterPad => AppResponsive.formFooterPadding(this);

  EdgeInsets rScrollPad({double top = 0, double bottom = 24}) =>
      AppResponsive.scrollScreenPadding(this, top: top, bottom: bottom);

  double get rTitleSize => AppResponsive.formTitleFontSize(this);

  double get rHeadingSize => AppResponsive.pageHeadingFontSize(this);
}

/// Scrollable page body with responsive horizontal padding and max content width.
class ResponsiveScrollPage extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final ScrollPhysics? physics;

  const ResponsiveScrollPage({
    super.key,
    required this.child,
    this.padding,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: physics,
      padding: padding ?? AppResponsive.scrollScreenPadding(context),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppResponsive.contentInnerMaxWidth(
              MediaQuery.sizeOf(context).width,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Non-scroll screen body (OTP, static forms) with responsive insets + max width.
class ResponsiveScreenBody extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const ResponsiveScreenBody({
    super.key,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? AppResponsive.screenPaddingAll(context),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppResponsive.contentInnerMaxWidth(
              MediaQuery.sizeOf(context).width,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Three equal-width tap targets (staff count 1 / 2 / 3+).
class ResponsiveTripleRow extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const ResponsiveTripleRow({
    super.key,
    required this.children,
  })  : gap = 12,
        assert(children.length == 3);

  @override
  Widget build(BuildContext context) {
    final g = AppResponsive.compactRowGap(context);
    return Row(
      children: [
        Expanded(child: children[0]),
        SizedBox(width: g),
        Expanded(child: children[1]),
        SizedBox(width: g),
        Expanded(child: children[2]),
      ],
    );
  }
}

/// Label on the left, value on the right — stacks on very narrow phones.
class ResponsiveLabelValueRow extends StatelessWidget {
  final Widget label;
  final Widget value;
  final double gap;

  const ResponsiveLabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (AppResponsive.stackSalaryHeader(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          SizedBox(height: gap),
          value,
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(child: label),
        SizedBox(width: gap),
        value,
      ],
    );
  }
}

/// Compact radio bullet for form single-select fields.
class FormBulletOption<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final String label;
  final ValueChanged<T?> onChanged;

  const FormBulletOption({
    super.key,
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      groupValue: groupValue,
      activeColor: const Color(0xFF3D3D7B),
      onChanged: onChanged,
    );
  }
}

/// Horizontal row of compact radio bullets (e.g. staff count 1 / 2 / 3+).
class FormBulletOptionRow<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T? groupValue;
  final ValueChanged<T?> onChanged;

  const FormBulletOptionRow({
    super.key,
    required this.options,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: FormBulletOption<T>(
              value: options[i].value,
              groupValue: groupValue,
              label: options[i].label,
              onChanged: onChanged,
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact location picker button for job forms.
class CompactLocationField extends StatelessWidget {
  final String? selectedLocation;
  final String placeholder;
  final VoidCallback onTap;

  const CompactLocationField({
    super.key,
    required this.selectedLocation,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = selectedLocation != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasValue ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 18,
              color: hasValue ? const Color(0xFF3D3D7B) : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedLocation ?? placeholder,
                style: TextStyle(
                  fontSize: 14,
                  color: hasValue ? const Color(0xFF121A2C) : Colors.grey,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

/// Two large option cards: side-by-side when wide, stacked on narrow phones.
class ResponsiveOptionRow extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const ResponsiveOptionRow({
    super.key,
    required this.children,
    this.gap = 12,
  }) : assert(children.length == 2);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (AppResponsive.stackDualOptionCards(context, constraints)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              children[0],
              SizedBox(height: gap),
              children[1],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            SizedBox(width: gap),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }
}

/// Choice chips in a [Row] when wide, [Wrap] when narrow.
class ResponsiveChipRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  const ResponsiveChipRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (AppResponsive.wrapChoiceChips(context, constraints)) {
          return Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            children: children,
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
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
