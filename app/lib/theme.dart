import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/db/tables/tables.dart';
import 'core/l10n/generated/app_localizations.dart';

import 'core/money/currency.dart';
import 'core/money/money.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Plain decimal input only; grouped and mixed-separator values are ambiguous.
double? parsePositiveAmount(String text, {bool allowZero = false}) {
  final input = text.trim();
  if (!RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(input)) return null;
  final value = double.tryParse(input.replaceAll(',', '.'));
  if (value == null ||
      !value.isFinite ||
      value > 90071992547409 ||
      value < 0 ||
      (!allowZero && value == 0)) {
    return null;
  }
  return value;
}

Future<bool> confirmDiscardChanges(BuildContext context,
    {required bool dirty}) async {
  if (!dirty) return true;
  final l10n = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.t('Discard changes?', 'Eldobod a módosításokat?')),
          content: Text(l10n.t('Your unsaved changes will be lost.',
              'A nem mentett módosítások elvesznek.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.t('Keep editing', 'Szerkesztés folytatása'))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.t('Discard', 'Eldobás'))),
          ],
        ),
      ) ??
      false;
}

String activityDisplaySummary(ActivityEvent event,
    {required String locale, required bool hideAmounts}) {
  if (!hideAmounts) return event.localizedSummary(locale);
  final hu = locale.startsWith('hu');
  return switch (event.eventType) {
    'expense_added' ||
    'income_added' ||
    'transaction_added' ||
    'transfer_added' =>
      hu ? 'Tranzakció rögzítve' : 'Transaction recorded',
    'contribution_added' ||
    'goal_milestone' =>
      hu ? 'Megtakarítás frissítve' : 'Savings updated',
    'settlement_proposed' =>
      hu ? 'Elszámolási javaslat rögzítve' : 'Settlement proposal recorded',
    'settlement_confirmed' =>
      hu ? 'Elszámolás rögzítve' : 'Settlement recorded',
    _ => hu ? 'Tevékenység rögzítve' : 'Activity recorded',
  };
}

/// Motion tokens. Built-in curves are too weak; these have intent.
abstract final class Motion {
  /// Entrances & press feedback: starts fast, feels instant.
  static const easeOut = Cubic(0.23, 1, 0.32, 1);

  /// iOS-like sheet curve (Ionic) and its mirror for the exit.
  static const drawer = Cubic(0.32, 0.72, 0, 1);
  static const drawerExit = Cubic(1, 0, 0.68, 0.28);

  static const press = Duration(milliseconds: 140);
  static const page = Duration(milliseconds: 180);

  /// Bottom sheets: deliberate in, snappy out.
  static const sheet = AnimationStyle(
    duration: Duration(milliseconds: 300),
    reverseDuration: Duration(milliseconds: 200),
    curve: drawer,
    reverseCurve: drawerExit,
  );
}

/// Semantic colors that Material's ColorScheme has no slot for.
@immutable
class DuoColors extends ThemeExtension<DuoColors> {
  const DuoColors({
    required this.positive,
    required this.negative,
    required this.warning,
    required this.info,
    required this.muted,
    required this.hairline,
    required this.icon,
    required this.accent,
    required this.well,
    this.heroSurface = const Color(0xFFFF385C),
    this.onHeroSurface = const Color(0xFFFFFFFF),
  });

  final Color positive;
  final Color negative;
  final Color warning;
  final Color info;
  final Color muted;
  final Color hairline;
  final Color icon;
  final Color accent;
  final Color well;
  final Color heroSurface;
  final Color onHeroSurface;

  @override
  DuoColors copyWith({
    Color? positive,
    Color? negative,
    Color? warning,
    Color? info,
    Color? muted,
    Color? hairline,
    Color? icon,
    Color? accent,
    Color? well,
    Color? heroSurface,
    Color? onHeroSurface,
  }) =>
      DuoColors(
        positive: positive ?? this.positive,
        negative: negative ?? this.negative,
        warning: warning ?? this.warning,
        info: info ?? this.info,
        muted: muted ?? this.muted,
        hairline: hairline ?? this.hairline,
        icon: icon ?? this.icon,
        accent: accent ?? this.accent,
        well: well ?? this.well,
        heroSurface: heroSurface ?? this.heroSurface,
        onHeroSurface: onHeroSurface ?? this.onHeroSurface,
      );

  @override
  DuoColors lerp(DuoColors? other, double t) {
    if (other == null) return this;
    return DuoColors(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      icon: Color.lerp(icon, other.icon, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      well: Color.lerp(well, other.well, t)!,
      heroSurface: Color.lerp(heroSurface, other.heroSurface, t)!,
      onHeroSurface: Color.lerp(onHeroSurface, other.onHeroSurface, t)!,
    );
  }
}

extension DuoThemeX on BuildContext {
  DuoColors get duo => Theme.of(this).extension<DuoColors>()!;
}

class _Palette {
  const _Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.fill,
    required this.hairline,
    required this.outline,
    required this.ink,
    required this.muted,
    required this.positive,
    required this.negative,
    required this.negativeContainer,
    required this.warning,
    required this.info,
    required this.icon,
    required this.accent,
    required this.primaryBrand,
  });

  final Brightness brightness;
  final Color bg, surface, fill, hairline, outline, ink, muted;
  final Color positive, negative, negativeContainer, warning, info;
  final Color icon, accent, primaryBrand;

  // Exact User-Provided Airbnb Palette:
  // Primary Brand & Logo Colors:
  // - Rausch (#FF5A5F / RGB: 255, 90, 95) — Coral-pink brand identity
  // - Radical Red (#FF385C / RGB: 255, 56, 92) — Vibrant reddish-pink CTAs & active states
  // Secondary & Accent Colors:
  // - Babu (#00A699 / RGB: 0, 166, 153) — Teal accent for secondary, maps, success states
  // - Arches (#FC642D / RGB: 252, 100, 45) — Warm orange-red for badges & highlights
  // Neutral & UI Colors:
  // - Mine Shaft / Black (#222222 / RGB: 34, 34, 34) — Primary text
  // - Hof / Dark Gray (#484848 / RGB: 72, 72, 72) — Headings & interface elements/icons
  // - Foggy / Secondary Gray (#767676 / RGB: 118, 118, 118) — Secondary text & descriptions
  // - White (#FFFFFF / RGB: 255, 255, 255) — Clean background surface color
  static const light = _Palette(
    brightness: Brightness.light,
    bg: Color(
        0xFFF7F7F7), // Soft canvas so #FFFFFF cards & input fields stand out
    surface: Color(0xFFFFFFFF), // White (#FFFFFF) clean surface color
    fill: Color(0xFFF1F1F1), // Subtle nested well
    hairline: Color(0xFFEBEBEB),
    outline: Color(0xFFB0B0B0), // Clear visible border for input boxes
    ink: Color(0xFF222222), // Mine Shaft / Black (#222222)
    muted: Color(0xFF626262), // Foggy / Secondary Gray (#767676)
    positive: Color(0xFF00766D), // Babu Teal (#00A699)
    negative: Color(0xFFBF2345), // Radical Red (#FF385C)
    negativeContainer: Color(0xFFFFE5EA),
    warning: Color(0xFFAC420F), // Arches Orange-Red (#FC642D)
    info: Color(0xFF00766D), // Babu Teal (#00A699)
    icon: Color(0xFF484848), // Hof / Dark Gray (#484848)
    accent: Color(0xFFFF5A5F), // Rausch Coral-Pink (#FF5A5F)
    primaryBrand: Color(0xFFBF2345), // Radical Red (#FF385C)
  );

  static const dark = _Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF141414),
    surface: Color(0xFF222222), // Mine Shaft dark surface
    fill: Color(0xFF2C2C2C),
    hairline: Color(0xFF383838),
    outline: Color(0xFF767676), // Foggy border
    ink: Color(0xFFFFFFFF), // White text
    muted: Color(0xFFB0B0B0),
    positive: Color(0xFF4FD1BE), // Babu Teal (#00A699)
    negative: Color(0xFFFF5A5F), // Rausch (#FF5A5F)
    negativeContainer: Color(0xFF421820),
    warning: Color(0xFFFC642D), // Arches (#FC642D)
    info: Color(0xFF4FD1BE), // Babu (#00A699)
    icon: Color(0xFFE2E2E2), // Rausch (#FF5A5F)
    accent: Color(0xFFFF5A5F), // Rausch (#FF5A5F)
    primaryBrand: Color(0xFFFF8FA4), // Radical Red (#FF385C)
  );
}

class AppTheme {
  static ThemeData light() => _build(_Palette.light);
  static ThemeData dark() => _build(_Palette.dark);

  static ThemeData _build(_Palette p) {
    final isDark = p.brightness == Brightness.dark;
    final hairline = BorderSide(color: p.hairline);
    final text = _textTheme(p);

    RoundedRectangleBorder rounded(double r,
            [BorderSide side = BorderSide.none]) =>
        RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r), side: side);

    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primaryBrand, // Radical Red #FF385C
      onPrimary: isDark ? p.bg : Colors.white,
      primaryContainer: p.primaryBrand.withValues(alpha: 0.12),
      onPrimaryContainer: p.primaryBrand,
      secondary: p.positive, // Babu #00A699
      onSecondary: isDark ? p.bg : Colors.white,
      secondaryContainer: p.positive.withValues(alpha: 0.14),
      onSecondaryContainer: isDark ? Colors.white : const Color(0xFF007A70),
      tertiary: p.warning, // Arches #FC642D
      onTertiary: isDark ? p.bg : Colors.white,
      error: p.negative,
      onError: Colors.white,
      errorContainer: p.negativeContainer,
      onErrorContainer: p.negative,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface,
      surfaceContainerHighest: p.fill,
      outline: p.outline,
      outlineVariant: p.hairline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: p.ink,
      onInverseSurface: p.surface,
      inversePrimary: p.accent,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      dividerColor: p.hairline,
      iconTheme: IconThemeData(color: p.icon, size: 22),
      // Ripples are slow and noisy. An instant tint + scale reads as "heard you".
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.ink.withValues(alpha: 0.06),
      hoverColor: p.ink.withValues(alpha: 0.04),
      focusColor: p.ink.withValues(alpha: 0.08),
      extensions: [
        DuoColors(
          positive: p.positive,
          negative: p.negative,
          warning: p.warning,
          info: p.info,
          muted: p.muted,
          hairline: p.hairline,
          icon: p.icon,
          accent: p.accent,
          well: p.fill,
          heroSurface: const Color(0xFFBF2345),
          onHeroSurface: Colors.white,
        ),
      ],
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        for (final platform in TargetPlatform.values)
          platform: const _ReducedMotionPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontSize: 20,
          letterSpacing: -0.5,
          color: isDark ? p.ink : const Color(0xFF484848),
        ),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: rounded(20, hairline),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.icon,
        textColor: p.ink,
        selectedColor: p.primaryBrand,
        selectedTileColor: p.primaryBrand.withValues(alpha: 0.08),
        shape: rounded(12),
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: p.muted),
        leadingAndTrailingTextStyle:
            text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 58,
        indicatorColor: p.primaryBrand.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? p.primaryBrand : p.muted,
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        width: 304,
        scrimColor: Colors.black.withValues(alpha: 0.35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primaryBrand,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: rounded(12),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: BorderSide(color: p.ink, width: 1.2),
          shape: rounded(12),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primaryBrand,
          shape: rounded(12),
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primaryBrand,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 1,
        shape: rounded(16),
        extendedTextStyle:
            text.labelLarge?.copyWith(fontSize: 15, color: scheme.onPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.outline, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.outline, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.primaryBrand, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.negative, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.negative, width: 2.0),
        ),
        labelStyle: TextStyle(
          color: isDark ? p.muted : const Color(0xFF484848),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: isDark ? p.ink : const Color(0xFF484848),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: p.muted, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF),
        selectedColor: p.primaryBrand.withValues(alpha: 0.14),
        checkmarkColor: p.primaryBrand,
        side: BorderSide(color: p.outline, width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        labelStyle: text.labelMedium?.copyWith(
          color: p.ink,
          fontWeight: FontWeight.w500,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 150),
          visualDensity: VisualDensity.compact,
          side: WidgetStatePropertyAll(BorderSide(color: p.outline)),
          shape: WidgetStatePropertyAll(rounded(12)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected) ? p.primaryBrand : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : p.ink,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected) ? scheme.onPrimary : p.muted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.bg,
        modalBackgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: p.outline,
        dragHandleSize: const Size(36, 4),
        modalBarrierColor: Colors.black.withValues(alpha: 0.4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: rounded(20, hairline),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.surface),
        actionTextColor: p.accent,
        elevation: 2,
        shape: rounded(12),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primaryBrand,
        linearTrackColor: p.fill,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(99),
        circularTrackColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: text.labelMedium?.copyWith(color: p.surface),
        decoration:
            BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.14),
        shape: rounded(12, hairline),
        textStyle: text.bodyMedium,
      ),
    );
  }

  static TextTheme _textTheme(_Palette p) {
    final typo = Typography.material2021(platform: defaultTargetPlatform);
    final base = typo.englishLike.merge(
      p.brightness == Brightness.dark ? typo.white : typo.black,
    );
    // Tabular figures everywhere: amounts line up in every list and never
    // jitter in width when they change.
    TextStyle? t(TextStyle? s, double size, FontWeight w, double ls,
            {double? h, Color? c}) =>
        s?.copyWith(
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          height: h,
          color: c ?? p.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    const w4 = FontWeight.w400, w5 = FontWeight.w500, w6 = FontWeight.w600;
    return base.copyWith(
      displayLarge: t(base.displayLarge, 56, w6, -2.0, h: 1.05),
      displayMedium: t(base.displayMedium, 44, w6, -1.6, h: 1.05),
      displaySmall: t(base.displaySmall, 36, w6, -1.2, h: 1.1),
      headlineLarge: t(base.headlineLarge, 32, w6, -1.0, h: 1.15),
      headlineMedium: t(base.headlineMedium, 28, w6, -0.8, h: 1.15),
      headlineSmall: t(base.headlineSmall, 24, w6, -0.6, h: 1.2),
      titleLarge: t(base.titleLarge, 20, w6, -0.4, h: 1.25),
      titleMedium: t(base.titleMedium, 16, w6, -0.2, h: 1.3),
      titleSmall: t(base.titleSmall, 14, w6, -0.1, h: 1.3),
      bodyLarge: t(base.bodyLarge, 16, w4, -0.1, h: 1.45),
      bodyMedium: t(base.bodyMedium, 14, w4, -0.05, h: 1.45),
      bodySmall: t(base.bodySmall, 12.5, w4, 0, h: 1.4, c: p.muted),
      labelLarge: t(base.labelLarge, 14, w6, -0.1),
      labelMedium: t(base.labelMedium, 12.5, w5, 0, c: p.muted),
      labelSmall: t(base.labelSmall, 11, w5, 0.1, c: p.muted),
    );
  }
}

class _ReducedMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const _ReducedMotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final native =
        const PageTransitionsTheme().builders[Theme.of(context).platform] ??
            const FadeUpwardsPageTransitionsBuilder();
    return native.buildTransitions(
        route, context, animation, secondaryAnimation, child);
  }
}

/// Scales its child to 0.97 while pressed. Uses a raw [Listener], so it never
/// competes with the child's own gestures; releases as soon as the pointer
/// drifts past touch slop (i.e. the user is scrolling, not pressing).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.onTap,
  });

  final Widget child;
  final double scale;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  int? _pointer;
  Offset _origin = Offset.zero;

  void _release() {
    if (_pointer != null) setState(() => _pointer = null);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget content = AnimatedScale(
      scale: _pointer != null && !reduceMotion ? widget.scale : 1,
      duration: reduceMotion ? Duration.zero : Motion.press,
      curve: Motion.easeOut,
      child: widget.child,
    );
    if (widget.onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          focusColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
          child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: content),
        ),
      );
    }
    return Listener(
      onPointerDown: (e) {
        if (_pointer != null) return; // ignore a second finger
        _origin = e.position;
        setState(() => _pointer = e.pointer);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer &&
            (e.position - _origin).distance > kTouchSlop) {
          _release();
        }
      },
      onPointerUp: (e) => e.pointer == _pointer ? _release() : null,
      onPointerCancel: (e) => e.pointer == _pointer ? _release() : null,
      child: content,
    );
  }
}

/// Compact status/delta pill without Material Chip's heavy 32px minimum height.
/// Positive pills render as solid Forest Pine (#013328) with Warm Sand (#E3DCD2) text.
typedef DuoPill = DuoBadge;

class DuoBadge extends StatelessWidget {
  const DuoBadge(
    this.label, {
    super.key,
    this.color,
    this.backgroundColor,
    this.solid = false,
  });

  final String label;
  final Color? color;
  final Color? backgroundColor;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final isPositiveSolid =
        solid || (backgroundColor == null && color == const Color(0xFF00A699));
    final bg = backgroundColor ??
        (isPositiveSolid
            ? (color ?? duo.positive)
            : (color != null ? color!.withValues(alpha: 0.12) : duo.well));
    final fg = isPositiveSolid
        ? ((bg.computeLuminance() + .05) / .05 >= 4.5
            ? Colors.black
            : Colors.white)
        : (color ?? Theme.of(context).colorScheme.onSurface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: isPositiveSolid
            ? null
            : Border.all(
                color: color != null
                    ? color!.withValues(alpha: 0.24)
                    : duo.hairline,
              ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
      ),
    );
  }
}

/// Borderless lifted card with radius 24, soft multi-layer shadow in light mode,
/// optional hero Deep Forest Pine surface (#013328), and optional Pressable tap.
class DuoCard extends StatelessWidget {
  const DuoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.isHero = false,
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool isHero;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final bg = color ??
        (isHero ? duo.heroSurface : Theme.of(context).colorScheme.surface);

    Widget inner = Padding(padding: padding, child: child);
    if (isHero) {
      inner = DefaultTextStyle.merge(
        style: TextStyle(color: duo.onHeroSurface),
        child: IconTheme.merge(
          data: IconThemeData(color: duo.onHeroSurface),
          child: inner,
        ),
      );
    }

    Widget box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: highContrast ? Border.all(color: duo.hairline) : null,
        boxShadow: isDark
            ? const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x0A100C0D),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
                BoxShadow(
                  color: Color(0x08100C0D),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: inner,
      ),
    );

    if (onTap != null) {
      box = Pressable(onTap: onTap, child: box);
    }
    return box;
  }
}

/// Nested rounded well container for secondary pairs (e.g. My Total / Individual) inside a card.
class DuoWell extends StatelessWidget {
  const DuoWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderRadius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? duo.well,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}

/// Formats a [Money] value with large bold main digits (tight -0.03em tracking,
/// tabular figures) and renders the currency symbol/code in muted lighter weight
/// (0.55x font size). Narrow summaries compact numbers and wrap currency.
class DuoAmount extends StatelessWidget {
  const DuoAmount({
    super.key,
    required this.money,
    this.locale = 'hu',
    this.hideAmounts = false,
    this.compact = false,
    this.animate = false,
    this.fontSize = 38,
    this.color,
    this.currencyColor,
    this.alignment = Alignment.centerLeft,
  });

  final Money money;
  final String locale;
  final bool hideAmounts;
  final bool compact;
  final bool animate;
  final double fontSize;
  final Color? color;
  final Color? currencyColor;
  final AlignmentGeometry alignment;

  Widget _buildFormatted(BuildContext context, int minor) {
    final duo = context.duo;
    final mainColor = color ?? Theme.of(context).colorScheme.onSurface;
    final subColor = currencyColor ?? (color ?? duo.muted);
    final symbol = money.currency.symbol;

    final mainStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: fontSize * -0.03,
      height: 1.05,
      color: mainColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final subStyle = TextStyle(
      fontSize: fontSize * 0.55,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.2,
      height: 1.05,
      color: subColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final m = Money(minor, money.currency);
    final numPart =
        hideAmounts ? '••••' : m.formatNumber(locale: locale, compact: compact);
    final suffixCurrency =
        locale.startsWith('hu') || money.currency != CurrencyCode.eur;
    return Semantics(
      label: hideAmounts
          ? (locale.startsWith('hu') ? 'Összeg elrejtve' : 'Amount hidden')
          : money.format(locale: locale),
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, constraints) {
        var displayed = numPart;
        final painter = TextPainter(
            text: TextSpan(text: numPart, style: mainStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context))
          ..layout();
        if (!hideAmounts && painter.width > constraints.maxWidth) {
          displayed = m.formatNumber(locale: locale, compact: true);
        }
        painter.dispose();
        return Align(
          alignment: alignment,
          child: Text.rich(TextSpan(
              children: suffixCurrency
                  ? [
                      TextSpan(text: displayed, style: mainStyle),
                      TextSpan(text: ' $symbol', style: subStyle)
                    ]
                  : [
                      TextSpan(text: '$symbol ', style: subStyle),
                      TextSpan(text: displayed, style: mainStyle)
                    ])),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!animate || reduceMotion || hideAmounts) {
      return _buildFormatted(context, money.amountMinor);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: money.amountMinor.toDouble()),
      duration: const Duration(milliseconds: 240),
      curve: Motion.easeOut,
      builder: (context, value, _) => _buildFormatted(context, value.round()),
    );
  }
}

/// Compact circle glyph with at least 48px interactive bounds.
class DuoCircleButton extends StatelessWidget {
  const DuoCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 38,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    Widget btn = Pressable(
      onTap: onTap,
      child: Container(
        width: math.max(48, size),
        height: math.max(48, size),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: duo.hairline, width: 1.1),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.48, color: iconColor ?? duo.icon),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// Clean section header row with title and optional tappable trailing action / chevron.
class DuoSectionHeader extends StatelessWidget {
  const DuoSectionHeader({
    super.key,
    required this.title,
    this.trailingLabel,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String? trailingLabel;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final duo = context.duo;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text(title,
            style:
                textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        if (trailing != null)
          trailing!
        else if (onTap != null)
          TextButton(
            onPressed: onTap,
            child: Text(
                trailingLabel ??
                    (Localizations.localeOf(context).languageCode == 'hu'
                        ? 'Összes'
                        : 'View all'),
                style: textTheme.labelMedium?.copyWith(color: duo.muted)),
          ),
      ],
    );
  }
}

/// Semicircular 240°–270° arc gauge with rounded stroke caps, track in [DuoColors.well],
/// and active arc sweeping from Deep Forest Pine (#013328) to Terracotta (#CC8B65).
class DuoGauge extends StatelessWidget {
  const DuoGauge({
    super.key,
    required this.progress,
    this.size = 160,
    this.strokeWidth = 14,
    this.trackColor,
    this.child,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final Color? trackColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final clamped = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size * 0.78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size * 0.78),
            painter: _DuoGaugePainter(
              progress: clamped,
              strokeWidth: strokeWidth,
              trackColor: trackColor ?? duo.well,
              startColor: const Color(0xFF00A699),
              endColor: const Color(0xFFFF385C),
            ),
          ),
          if (child != null)
            Padding(
              padding: EdgeInsets.only(top: size * 0.12),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _DuoGaugePainter extends CustomPainter {
  const _DuoGaugePainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    const startAngle = 150 * math.pi / 180; // 150°
    const totalSweep = 240 * math.pi / 180; // 240°
    final radius = (math.min(size.width, size.height * 1.22) - strokeWidth) / 2;
    final center = Offset(size.width / 2, radius + strokeWidth / 2 + 4);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, totalSweep, false, trackPaint);

    if (progress > 0.005) {
      final activeSweep = totalSweep * progress;
      final gradient = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [startColor, endColor, startColor],
        stops: const [0.0, 0.7, 1.0],
        transform: const GradientRotation(startAngle),
      );
      final activePaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, startAngle, activeSweep, false, activePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DuoGaugePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.trackColor != trackColor;
}

/// Clean bare icon without any rounded squircle background box.
/// Uses the unified palette icon color (#013328 in light, #CC8B65 in dark).
class DuoIconBox extends StatelessWidget {
  const DuoIconBox(
    this.icon, {
    super.key,
    this.color,
    this.backgroundColor,
    this.size = 22,
  });

  final IconData icon;
  final Color? color;
  final Color? backgroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final fg = color ?? duo.icon;
    return Icon(icon, size: size, color: fg);
  }
}

/// Category or merchant glyph. If an icon is provided, renders the bare icon directly
/// in the unified palette color without any pastel background squircle box.
class MerchantAvatar extends StatelessWidget {
  const MerchantAvatar({
    super.key,
    this.name,
    this.category,
    this.icon,
    this.customColor,
    this.size = 28,
  });

  final String? name;
  final String? category;
  final IconData? icon;
  final Color? customColor;
  final double size;

  static String _monogram(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return 'TX';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return cleaned.substring(0, cleaned.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final fg = customColor ?? duo.icon;

    if (icon != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(icon, size: size * 0.82, color: fg),
        ),
      );
    }

    final label = name?.trim().isNotEmpty == true ? name! : (category ?? 'Tx');
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: duo.hairline, width: 1.0),
      ),
      child: Text(
        _monogram(label),
        style: TextStyle(
          color: fg,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

/// Clean user avatar representing a Man, Woman, or custom profile image.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.avatarType = 'man',
    this.avatarUrl,
    this.name,
    this.size = 36,
    this.color,
  });

  final String? avatarType; // 'man', 'woman', 'image'
  final String? avatarUrl;
  final String? name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final iconColor = color ?? duo.icon;

    Widget fallback() => Center(
        child: avatarType == 'initials'
            ? Text(
                (name?.trim().isNotEmpty ?? false)
                    ? name!.trim().characters.first.toUpperCase()
                    : '?',
                style: TextStyle(color: iconColor, fontSize: size * .42))
            : Icon(Icons.person_outline, size: size * .6, color: iconColor));
    if (avatarType == 'initials' || avatarType == 'image') {
      final uri = Uri.tryParse(avatarUrl ?? '');
      final valid = uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty;
      return ClipOval(
          child: SizedBox(
              width: size,
              height: size,
              child: avatarType == 'image' && valid
                  ? Image.network(avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback(),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : fallback())
                  : fallback()));
    }

    final icon =
        (avatarType == 'woman') ? Icons.face_3_outlined : Icons.face_outlined;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: duo.hairline, width: 1.2),
      ),
      child: Center(
        child: Icon(icon, size: size * 0.62, color: iconColor),
      ),
    );
  }
}

/// Minimalist hairline progress bar with smooth capsule radius.
class DuoProgressBar extends StatelessWidget {
  const DuoProgressBar({
    super.key,
    double? progress,
    double? value,
    this.color,
    this.backgroundColor,
    this.height = 6,
  }) : progress = progress ?? value ?? 0.0;

  final double progress;
  final Color? color;
  final Color? backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final barColor = color ?? duo.positive;
    final trackColor = backgroundColor ?? duo.well;
    final clamped = progress.clamp(0.0, 1.0);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: clamped,
        child: Container(
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }
}
