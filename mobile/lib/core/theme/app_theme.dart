import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidade visual do Salabim: fundo escuro, gradiente vibrante no botão de
/// escuta (referência direta ao selo circular do Shazam, mas com paleta própria).
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0B0714);
  static const Color surface = Color(0xFF181025);
  static const Color primary = Color(0xFF7C4DFF); // roxo Salabim
  static const Color secondary = Color(0xFFC945E3); // magenta-violeta de destaque (modo "cantar")
  static const Color accentListen = Color(0xFF7C4DFF);
  static const Color accentHum = Color(0xFFC945E3);
  static const Color textPrimary = Color(0xFFF5F3FA);
  static const Color textSecondary = Color(0xFFA79FBD);
  static const Color success = Color(0xFF34D399);
  static const Color error = Color(0xFFF87171);

  static const LinearGradient listenGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFF4D6BFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Rosa/magenta -> violeta: continua na família do roxo do app (diferente
  // do azul-arroxeado do modo "Ouvir"), sem cair pro laranja/vermelho.
  static const LinearGradient humGradient = LinearGradient(
    colors: [Color(0xFFFF4DC8), Color(0xFF9A3DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
