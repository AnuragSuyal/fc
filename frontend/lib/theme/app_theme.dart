import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/constants.dart';

@immutable
class AppMood extends ThemeExtension<AppMood> {
  const AppMood({
    required this.shellTop,
    required this.shellBottom,
    required this.blush,
    required this.mint,
    required this.sun,
    required this.sky,
    required this.berry,
    required this.surfaceSoft,
    required this.outlineSoft,
    required this.shadow,
    required this.navGlass,
  });

  final Color shellTop;
  final Color shellBottom;
  final Color blush;
  final Color mint;
  final Color sun;
  final Color sky;
  final Color berry;
  final Color surfaceSoft;
  final Color outlineSoft;
  final Color shadow;
  final Color navGlass;

  LinearGradient get shellGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [shellTop, shellBottom],
      );

  LinearGradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [blush, sun, sky],
      );

  LinearGradient get loungeGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [berry, blush, mint],
      );

  @override
  AppMood copyWith({
    Color? shellTop,
    Color? shellBottom,
    Color? blush,
    Color? mint,
    Color? sun,
    Color? sky,
    Color? berry,
    Color? surfaceSoft,
    Color? outlineSoft,
    Color? shadow,
    Color? navGlass,
  }) {
    return AppMood(
      shellTop: shellTop ?? this.shellTop,
      shellBottom: shellBottom ?? this.shellBottom,
      blush: blush ?? this.blush,
      mint: mint ?? this.mint,
      sun: sun ?? this.sun,
      sky: sky ?? this.sky,
      berry: berry ?? this.berry,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      outlineSoft: outlineSoft ?? this.outlineSoft,
      shadow: shadow ?? this.shadow,
      navGlass: navGlass ?? this.navGlass,
    );
  }

  @override
  AppMood lerp(ThemeExtension<AppMood>? other, double t) {
    if (other is! AppMood) return this;
    return AppMood(
      shellTop: Color.lerp(shellTop, other.shellTop, t) ?? shellTop,
      shellBottom: Color.lerp(shellBottom, other.shellBottom, t) ?? shellBottom,
      blush: Color.lerp(blush, other.blush, t) ?? blush,
      mint: Color.lerp(mint, other.mint, t) ?? mint,
      sun: Color.lerp(sun, other.sun, t) ?? sun,
      sky: Color.lerp(sky, other.sky, t) ?? sky,
      berry: Color.lerp(berry, other.berry, t) ?? berry,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t) ?? surfaceSoft,
      outlineSoft: Color.lerp(outlineSoft, other.outlineSoft, t) ?? outlineSoft,
      shadow: Color.lerp(shadow, other.shadow, t) ?? shadow,
      navGlass: Color.lerp(navGlass, other.navGlass, t) ?? navGlass,
    );
  }

  static const light = AppMood(
    shellTop: Color(0xFFE7E9EC),
    shellBottom: Color(0xFFF7F8F9),
    blush: Color(0xFF272A30),
    mint: Color(0xFF5B6168),
    sun: Color(0xFF959CA4),
    sky: Color(0xFFD6DBE1),
    berry: Color(0xFF101113),
    surfaceSoft: Color(0xFFF1F3F5),
    outlineSoft: Color(0xFFDADDE2),
    shadow: Color(0x1C000000),
    navGlass: Color(0xF2FAFBFC),
  );

  static const dark = AppMood(
    shellTop: Color(0xFF16171A),
    shellBottom: Color(0xFF09090B),
    blush: Color(0xFF34383E),
    mint: Color(0xFF666D76),
    sun: Color(0xFFA1A8B0),
    sky: Color(0xFFD5D9DE),
    berry: Color(0xFF050608),
    surfaceSoft: Color(0xFF181A1E),
    outlineSoft: Color(0xFF2A2F35),
    shadow: Color(0x7A000000),
    navGlass: Color(0xE5111214),
  );
}

extension AppMoodContext on BuildContext {
  AppMood get mood => Theme.of(this).extension<AppMood>() ?? AppMood.light;
}

class AppTheme {
  static ThemeData light() {
    const mood = AppMood.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      brightness: Brightness.light,
      primary: AppColors.primaryBlue,
      secondary: AppColors.secondaryBlue,
      tertiary: AppColors.accentYellow,
      surface: Colors.white,
      error: AppColors.errorRed,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: mood.shellBottom,
      canvasColor: mood.shellBottom,
      splashFactory: InkRipple.splashFactory,
      dividerColor: mood.outlineSoft,
    );

    final textTheme = _buildTextTheme(base.textTheme, false);

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: mood.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: mood.outlineSoft),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryBlue,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary.withValues(alpha: 0.82),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: mood.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: mood.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide:
              const BorderSide(color: AppColors.primaryBlue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColors.errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColors.errorRed, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              AppColors.primaryBlue.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: mood.outlineSoft),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: mood.surfaceSoft,
        selectedColor: AppColors.primaryBlue.withValues(alpha: 0.18),
        secondarySelectedColor: AppColors.primaryBlue.withValues(alpha: 0.18),
        disabledColor: mood.surfaceSoft.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: mood.outlineSoft),
        ),
        side: BorderSide(color: mood.outlineSoft),
        labelStyle: textTheme.labelLarge ?? const TextStyle(),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: mood.surfaceSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surfaceBubble,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: mood.outlineSoft),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extensions: const [mood],
    );
  }

  static ThemeData dark() {
    const mood = AppMood.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accentYellow,
      brightness: Brightness.dark,
      primary: AppColors.accentYellow,
      secondary: AppColors.accentSky,
      tertiary: AppColors.secondaryBlue,
      surface: const Color(0xFF111315),
      error: AppColors.errorRed,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: mood.shellBottom,
      canvasColor: mood.shellBottom,
      dividerColor: mood.outlineSoft,
    );

    final textTheme = _buildTextTheme(base.textTheme, true);

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF17191C),
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: mood.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: mood.outlineSoft),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF17191C),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0E1012),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF17191C),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.58),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: mood.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: mood.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: AppColors.accentYellow, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentYellow,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentYellow,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: mood.outlineSoft),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentYellow,
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: mood.surfaceSoft,
        selectedColor: AppColors.accentYellow.withValues(alpha: 0.18),
        secondarySelectedColor: AppColors.accentYellow.withValues(alpha: 0.18),
        disabledColor: mood.surfaceSoft.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: mood.outlineSoft),
        ),
        side: BorderSide(color: mood.outlineSoft),
        labelStyle: textTheme.labelLarge ?? const TextStyle(),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: mood.surfaceSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF17191C),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: mood.outlineSoft),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentYellow,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      extensions: const [mood],
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, bool isDark) {
    final bodyColor = isDark ? Colors.white : AppColors.textPrimary;
    final secondaryColor =
        isDark ? Colors.white.withValues(alpha: 0.72) : AppColors.textSecondary;

    final theme = GoogleFonts.nunitoTextTheme(base).apply(
      bodyColor: bodyColor,
      displayColor: bodyColor,
    );

    return theme.copyWith(
      displayLarge: GoogleFonts.baloo2(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        height: 0.95,
      ),
      displayMedium: GoogleFonts.baloo2(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        height: 0.98,
      ),
      displaySmall: GoogleFonts.baloo2(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: bodyColor,
      ),
      headlineLarge: GoogleFonts.baloo2(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: bodyColor,
      ),
      headlineMedium: GoogleFonts.baloo2(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: bodyColor,
      ),
      headlineSmall: GoogleFonts.baloo2(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: bodyColor,
      ),
      titleLarge: GoogleFonts.baloo2(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: bodyColor,
      ),
      titleMedium: theme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: bodyColor,
      ),
      titleSmall: theme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: bodyColor,
      ),
      bodyLarge: theme.bodyLarge?.copyWith(
        color: bodyColor,
        height: 1.45,
      ),
      bodyMedium: theme.bodyMedium?.copyWith(
        color: bodyColor,
        height: 1.45,
      ),
      bodySmall: theme.bodySmall?.copyWith(
        color: secondaryColor,
        height: 1.4,
      ),
      labelLarge: theme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: bodyColor,
      ),
      labelMedium: theme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: secondaryColor,
      ),
    );
  }
}
