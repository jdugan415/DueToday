import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/assignment.dart';

/// DueToday design system: slate neutrals, an iris accent, hairline borders
/// instead of drop shadows, 16px card radii, and Plus Jakarta Sans.
///
/// The font is bundled (pubspec.yaml `fonts:`), so it renders offline, every
/// FontWeight maps to a real font file, and nothing is fetched at runtime.
const String fontFamily = 'PlusJakartaSans';

/// Semantic colors not covered by [ColorScheme]. Read with `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.border,
    required this.fieldFill,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.urgent,
    required this.warning,
    required this.success,
  });

  final Color background;
  final Color surface;

  /// 1px hairlines on cards, sheets, and dividers.
  final Color border;

  /// Soft fill behind text fields and quiet tonal controls.
  final Color fieldFill;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;

  /// Overdue / due within 24 hours.
  final Color urgent;

  /// Due within a few days.
  final Color warning;
  final Color success;

  static const light = AppColors(
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    fieldFill: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    accent: Color(0xFF4F46E5),
    urgent: Color(0xFFEF4444),
    warning: Color(0xFFF59E0B),
    success: Color(0xFF10B981),
  );

  static const dark = AppColors(
    background: Color(0xFF090D16),
    surface: Color(0xFF131B2E),
    border: Color(0xFF1E293B),
    fieldFill: Color(0xFF1E293B),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    accent: Color(0xFF818CF8),
    // Lighter tints keep contrast on the near-black background.
    urgent: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
    success: Color(0xFF34D399),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? border,
    Color? fieldFill,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? urgent,
    Color? warning,
    Color? success,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      fieldFill: fieldFill ?? this.fieldFill,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      urgent: urgent ?? this.urgent,
      warning: warning ?? this.warning,
      success: success ?? this.success,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      fieldFill: Color.lerp(fieldFill, other.fieldFill, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      urgent: Color.lerp(urgent, other.urgent, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  /// Falls back to the matching palette when a widget is shown under a theme
  /// without [AppColors] (tests, embedded previews).
  AppColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? AppColors.dark : AppColors.light);
  }
}

/// Shared geometry.
class AppRadius {
  AppRadius._();

  static const double card = 16;
  static const double sheet = 24;
  static const double field = 12;
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
}

/// Hairline card border: crisp 1px outline at half strength, no shadow.
BorderSide hairline(BuildContext context) =>
    BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5));

// ---------------------------------------------------------------------------
// Course colors
// ---------------------------------------------------------------------------

/// Course badge hues; pills render them as low-saturation tints.
const List<Color> courseColors = [
  Color(0xFF6366F1), // indigo
  Color(0xFF14B8A6), // teal
  Color(0xFFF43F5E), // rose
  Color(0xFFF59E0B), // amber
  Color(0xFF8B5CF6), // violet
  Color(0xFF10B981), // emerald
  Color(0xFF0EA5E9), // sky
  Color(0xFFF97316), // orange
];

Color courseColor(int index) => courseColors[index % courseColors.length];

/// Stable color slot for a course code (FNV-1a), so "CSC 3380" gets the same
/// tint on every device. Users can still pick another color per course.
int courseColorIndexFor(String courseCode) {
  var hash = 0x811c9dc5;
  for (final unit in courseCode.toUpperCase().codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash % courseColors.length;
}

/// (background, foreground) for a course pill, readable in both themes.
({Color background, Color foreground}) coursePillColors(int index, Brightness brightness) {
  final base = courseColor(index);
  final dark = brightness == Brightness.dark;
  return (
    background: base.withValues(alpha: dark ? 0.18 : 0.12),
    foreground: Color.lerp(base, dark ? Colors.white : Colors.black, dark ? 0.35 : 0.3)!,
  );
}

({Color background, Color foreground, String label}) priorityStyle(Priority priority, BuildContext context) {
  final c = context.colors;
  return switch (priority) {
    Priority.high => (background: c.urgent.withValues(alpha: 0.12), foreground: c.urgent, label: 'High'),
    Priority.medium => (background: c.warning.withValues(alpha: 0.14), foreground: c.warning, label: 'Medium'),
    Priority.low => (background: c.fieldFill, foreground: c.textSecondary, label: 'Low'),
  };
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? AppColors.dark : AppColors.light;

  final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: brightness).copyWith(
    primary: c.accent,
    onPrimary: dark ? const Color(0xFF0B1020) : Colors.white,
    primaryContainer: dark ? const Color(0xFF262B5E) : const Color(0xFFEEF2FF),
    onPrimaryContainer: dark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3),
    secondary: c.textSecondary,
    secondaryContainer: c.fieldFill,
    onSecondaryContainer: c.textPrimary,
    tertiary: c.warning,
    error: c.urgent,
    errorContainer: dark ? const Color(0xFF3B1219) : const Color(0xFFFEE2E2),
    onErrorContainer: dark ? const Color(0xFFFECACA) : const Color(0xFF991B1B),
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.fieldFill,
    surfaceTint: Colors.transparent,
    outline: dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
    outlineVariant: c.border,
    inverseSurface: dark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
    onInverseSurface: dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    inversePrimary: dark ? const Color(0xFF4F46E5) : const Color(0xFFA5B4FC),
  );

  final text = _textTheme(brightness, c);
  final pill = const StadiumBorder();
  final fieldRadius = BorderRadius.circular(AppRadius.field);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    textTheme: text,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarThemeData(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.textPrimary,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      // A transparent bar can't infer icon contrast; set it per theme.
      systemOverlayStyle: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: c.background,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: c.border.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: c.fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide.none),
      disabledBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: c.accent, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: c.urgent)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: c.urgent, width: 1.5)),
      labelStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
      floatingLabelStyle: text.labelMedium?.copyWith(color: c.accent),
      hintStyle: text.bodyMedium?.copyWith(color: c.textSecondary.withValues(alpha: 0.8)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: pill, textStyle: text.labelLarge),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: c.border)),
      side: BorderSide(color: c.border),
      backgroundColor: c.surface,
      selectedColor: scheme.primaryContainer,
      labelStyle: text.labelMedium?.copyWith(color: c.textPrimary),
      secondaryLabelStyle: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      showCheckmark: false,
      elevation: 0,
      pressElevation: 0,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      side: BorderSide(color: c.textSecondary.withValues(alpha: 0.55), width: 1.6),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.success : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      splashRadius: 18,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 3,
      shape: pill,
      extendedTextStyle: text.labelLarge,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: c.border,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.border),
      ),
      titleTextStyle: text.titleLarge,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      actionTextColor: dark ? c.accent : const Color(0xFFA5B4FC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: c.textSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.border),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal,
        ),
      },
    ),
  );
}

/// Tight, product-style type scale: negative tracking on large headings,
/// semi-bold titles, medium-weight body, tracked labels (call sites
/// uppercase `labelSmall` tags).
TextTheme _textTheme(Brightness brightness, AppColors c) {
  final base = ThemeData(brightness: brightness)
      .textTheme
      .apply(fontFamily: fontFamily, bodyColor: c.textPrimary, displayColor: c.textPrimary);
  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1.1, height: 1.1),
    headlineMedium: base.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineSmall: base.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    titleLarge: base.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleMedium: base.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.3),
    titleSmall: base.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.1),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
    bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.textSecondary),
    labelLarge: base.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0),
    labelMedium: base.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelSmall: base.labelSmall?.copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9),
  );
}
