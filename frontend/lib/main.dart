import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:carpal_app/screens/auth_screen.dart';
import 'package:carpal_app/screens/home_screen.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Carpal App',
      onGenerateTitle: (context) => context.translate('app_title'),
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: AppLocalizations.localeResolutionCallback,
      home: const AuthWrapper(),
    );
  }
}

ThemeData _buildLightTheme() {
  const primaryColor = Color(0xFF6C63FF);
  const secondaryColor = Color(0xFF00C6AE);
  const backgroundColor = Color(0xFFF7F8FA);
  const surfaceColor = Color(0xFFFFFFFF);
  const accentColor = Color(0xFFFFC107);
  const errorColor = Color(0xFFFF6B6B);
  const textPrimary = Color(0xFF222222);
  const textSecondary = Color(0xFF707070);

  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primaryColor,
    onPrimary: Colors.white,
    secondary: secondaryColor,
    onSecondary: Colors.white,
    error: errorColor,
    onError: Colors.white,
    background: backgroundColor,
    onBackground: textPrimary,
    surface: surfaceColor,
    onSurface: textPrimary,
    primaryContainer: primaryColor.withOpacity(0.12),
    onPrimaryContainer: primaryColor,
    secondaryContainer: secondaryColor.withOpacity(0.12),
    onSecondaryContainer: secondaryColor,
    surfaceVariant: surfaceColor,
    onSurfaceVariant: textSecondary,
    tertiary: accentColor,
    onTertiary: textPrimary,
    tertiaryContainer: accentColor.withOpacity(0.12),
    onTertiaryContainer: accentColor,
    outline: textSecondary,
    outlineVariant: textSecondary.withOpacity(0.3),
    inverseSurface: primaryColor,
    onInverseSurface: Colors.white,
    shadow: Colors.black,
    scrim: Colors.black54,
    inversePrimary: Colors.white,
  );

  final textTheme = _buildTextTheme(
    base: ThemeData.light().textTheme,
    primaryColor: textPrimary,
    secondaryColor: textSecondary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: backgroundColor,
    cardColor: surfaceColor,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    iconTheme: const IconThemeData(color: secondaryColor),
    cardTheme: CardThemeData(
      color: surfaceColor,
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      shadowColor: Colors.black.withOpacity(0.08),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: textSecondary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: textSecondary.withOpacity(0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryColor, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: errorColor, width: 1.8),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary.withOpacity(0.7)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
    ),
    dividerTheme: DividerThemeData(
      color: textSecondary.withOpacity(0.2),
      thickness: 1,
    ),
    extensions: const [
      AppThemeExtension(
        primaryGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, secondaryColor],
        ),
        screenPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ],
  );
}

ThemeData _buildDarkTheme() {
  const primaryColor = Color(0xFF8C7EFF);
  const secondaryColor = Color(0xFF00C6AE);
  const backgroundColor = Color(0xFF121212);
  const surfaceColor = Color(0xFF1E1E1E);
  const accentColor = Color(0xFFFFC107);
  const errorColor = Color(0xFFFF6B6B);
  const textPrimary = Color(0xFFEDEDED);
  const textSecondary = Color(0xFFB0B0B0);

  final colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: primaryColor,
    onPrimary: Colors.white,
    secondary: secondaryColor,
    onSecondary: Colors.black,
    error: errorColor,
    onError: Colors.black,
    background: backgroundColor,
    onBackground: textPrimary,
    surface: surfaceColor,
    onSurface: textPrimary,
    primaryContainer: primaryColor.withOpacity(0.22),
    onPrimaryContainer: primaryColor,
    secondaryContainer: secondaryColor.withOpacity(0.22),
    onSecondaryContainer: secondaryColor,
    surfaceVariant: surfaceColor,
    onSurfaceVariant: textSecondary,
    tertiary: accentColor,
    onTertiary: Colors.black,
    tertiaryContainer: accentColor.withOpacity(0.22),
    onTertiaryContainer: accentColor,
    outline: textSecondary,
    outlineVariant: textSecondary.withOpacity(0.4),
    inverseSurface: Colors.white,
    onInverseSurface: Colors.black,
    shadow: Colors.black,
    scrim: Colors.black,
    inversePrimary: Colors.white,
  );

  final textTheme = _buildTextTheme(
    base: ThemeData(brightness: Brightness.dark).textTheme,
    primaryColor: textPrimary,
    secondaryColor: textSecondary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: backgroundColor,
    cardColor: surfaceColor,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    iconTheme: const IconThemeData(color: secondaryColor),
    cardTheme: CardThemeData(
      color: surfaceColor,
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      shadowColor: Colors.black.withOpacity(0.4),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: textSecondary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: textSecondary.withOpacity(0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryColor, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: errorColor, width: 1.8),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary.withOpacity(0.7)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
    ),
    dividerTheme: DividerThemeData(
      color: textSecondary.withOpacity(0.25),
      thickness: 1,
    ),
    extensions: const [
      AppThemeExtension(
        primaryGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, secondaryColor],
        ),
        screenPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ],
  );
}

TextTheme _buildTextTheme({
  required TextTheme base,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  TextStyle titleStyle(double size) => GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: primaryColor,
      ).copyWith(
        fontFamilyFallback: const ['Roboto', 'Cairo', 'Noto Sans Arabic'],
      );

  TextStyle bodyStyle(double size, [FontWeight weight = FontWeight.w400]) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: weight,
        color: primaryColor,
      ).copyWith(
        fontFamilyFallback: const ['Roboto', 'Cairo', 'Noto Sans Arabic'],
      );

  TextStyle secondaryStyle(double size) => GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: secondaryColor,
      ).copyWith(
        fontFamilyFallback: const ['Roboto', 'Cairo', 'Noto Sans Arabic'],
      );

  return base.copyWith(
    headlineLarge: titleStyle(26),
    headlineMedium: titleStyle(24),
    headlineSmall: titleStyle(22),
    titleLarge: titleStyle(22),
    titleMedium: titleStyle(18),
    titleSmall: titleStyle(16),
    bodyLarge: bodyStyle(16),
    bodyMedium: bodyStyle(15),
    bodySmall: secondaryStyle(14),
    labelLarge: bodyStyle(14, FontWeight.w600),
    labelMedium: secondaryStyle(13),
    labelSmall: secondaryStyle(12),
  );
}

@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final LinearGradient primaryGradient;
  final EdgeInsetsGeometry screenPadding;

  const AppThemeExtension({
    required this.primaryGradient,
    required this.screenPadding,
  });

  @override
  AppThemeExtension copyWith({
    LinearGradient? primaryGradient,
    EdgeInsetsGeometry? screenPadding,
  }) {
    return AppThemeExtension(
      primaryGradient: primaryGradient ?? this.primaryGradient,
      screenPadding: screenPadding ?? this.screenPadding,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) {
      return this;
    }

    return AppThemeExtension(
      primaryGradient: LinearGradient.lerp(primaryGradient, other.primaryGradient, t) ??
          other.primaryGradient,
      screenPadding: EdgeInsetsGeometry.lerp(screenPadding, other.screenPadding, t) ??
          other.screenPadding,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const HomeScreen();
        } else {
          return const AuthScreen();
        }
      },
    );
  }
}
