import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// Capa exibida por 1s ao abrir o app: fundo escuro da identidade visual
/// com só o símbolo redondo centralizado, sem o título "salabim" (ele já
/// aparece na tela inicial logo em seguida). Puramente decorativa — não
/// depende de nenhum carregamento real, só marca a transição de abertura.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _duration = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    Future.delayed(_duration, () {
      if (!mounted) return;
      // go() (não push()) — substitui a rota, então o botão "voltar" a
      // partir da tela inicial não retorna pra capa.
      context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Image(
          image: AssetImage('assets/icons/salabim_icon.png'),
          width: 140,
          height: 140,
        ),
      ),
    );
  }
}
