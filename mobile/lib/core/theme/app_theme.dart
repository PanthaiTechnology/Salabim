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

  // Testado na prática (14/ago/2026): o final azul (0xFF4D6BFF) criava um
  // "conflito" visual — o círculo do ícone da logo é roxo puro (mesmo tom
  // inicial daqui, 0x7C4DFF), então o Ouvir acabava parecendo uma cor
  // diferente da identidade visual, não uma variação dela. Trocado por um
  // lilás mais claro — mesmo tom/matiz do roxo escuro do humGradient
  // abaixo (0x6023D6), só clareado — criando um par intencional: Cantar
  // aprofunda pro escuro, Ouvir clareia pro lilás, os dois inequívocos como
  // roxo/lilás (nunca azul, nunca rosa) e claramente diferentes entre si.
  static const LinearGradient listenGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFFAF91EA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Começa no mesmo roxo/lilás do "Ouvir" (e do item selecionado no menu
  // inferior) e aprofunda pra um roxo mais escuro/saturado — sem virar azul
  // (isso é a marca do "Ouvir") nem rosa. A diferenciação entre os modos
  // vem de pra onde cada gradiente vai, não do ponto de partida.
  static const LinearGradient humGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFF6023D6)],
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
