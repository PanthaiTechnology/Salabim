import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidade visual do Salabim: fundo escuro, gradiente vibrante no botão de
/// escuta (referência direta ao selo circular do Shazam, mas com paleta própria).
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0B0714);
  static const Color surface = Color(0xFF181025);
  static const Color primary = Color(0xFF7C4DFF); // roxo Salabim (mesmo tom do item selecionado no menu inferior)
  static const Color secondary = primary; // "cantar" parte do mesmo roxo/lilás, a pedido do usuário
  static const Color accentListen = Color(0xFF7C4DFF);
  static const Color accentHum = primary;
  static const Color textPrimary = Color(0xFFF5F3FA);
  static const Color textSecondary = Color(0xFFA79FBD);
  static const Color success = Color(0xFF34D399);
  static const Color error = Color(0xFFF87171);

  // Ajustado por várias rodadas de prévia com o usuário (14/ago/2026):
  // início num roxo mais vívido/saturado que o primary padrão (0x7C4DFF),
  // terminando num azul mais puro — mais contraste de matiz que a versão
  // "cor exata da logo" anterior, escolhido a dedo pelo usuário entre
  // várias opções mostradas.
  static const LinearGradient listenGradient = LinearGradient(
    colors: [Color(0xFF7515C7), Color(0xFF2F5CF0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Começa no mesmo roxo do "Ouvir" e clareia pra um lilás — a pedido
  // explícito do usuário (14/ago/2026), que gostou desse tom (surgiu sem
  // querer numa tentativa anterior pro Ouvir, revertida por não bater com
  // a logo — mas o lilás em si agradou, só pro modo errado). A
  // diferenciação entre os modos vem de pra onde cada gradiente vai (azul
  // pro Ouvir, lilás pro Cantar), não do ponto de partida, que os dois
  // compartilham.
  static const LinearGradient humGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFFAF91EA)],
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
