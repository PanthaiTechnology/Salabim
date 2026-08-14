import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// Capa exibida por 2s ao abrir o app: fundo escuro da identidade visual
/// com o símbolo redondo centralizado (maior, pra preencher melhor o
/// espaço da tela), sem o título "salabim" (ele já aparece na tela inicial
/// logo em seguida). O círculo dá a mesma "leve pulsada" dos botões
/// Ouvir/Cantar parados; os três tracinhos de áudio saindo da boca do mago
/// "carregam" um de cada vez (não em loop — só uma vez, sincronizado com os
/// 2s inteiros da capa). Puramente decorativa — não depende de nenhum
/// carregamento real, só marca a transição de abertura.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const _duration = Duration(seconds: 2);
  static const _circleSize = 280.0;
  // Proporção medida direto no ícone oficial da logo (devops/assets/store/icon_512.png):
  // largura do glifo ≈ 75% do diâmetro do círculo — bem maior que a
  // proporção usada no botão principal (60%), que é deliberadamente menor
  // pra caber os anéis decorativos ao redor. Aqui na capa não tem anel, e o
  // usuário pediu pra respeitar o tamanho de verdade da logo oficial.
  static const _markSize = _circleSize * 0.75;

  // Pulsada leve do círculo, idêntica à dos botões Ouvir/Cantar parados
  // (mesma duração de 2s, mesma amplitude de 6%).
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  // Preenchimento dos 3 tracinhos de áudio: UMA vez só, do início ao fim
  // dos 2s da capa — não é loop. Cada tracinho vai de invisível a opaco
  // dentro da sua janela, e permanece opaco depois (nada de sumir de novo).
  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: _duration,
  )..forward();

  static const _wave1Window = Interval(0.00, 0.15, curve: Curves.easeOut);
  static const _wave2Window = Interval(0.35, 0.50, curve: Curves.easeOut);
  static const _wave3Window = Interval(0.70, 0.85, curve: Curves.easeOut);

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
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = 1.0 + (_pulseController.value * 0.06);
            return Transform.scale(scale: scale, child: child);
          },
          child: SizedBox(
            width: _circleSize,
            height: _circleSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Círculo com o degradê real da logo (cor amostrada
                // diretamente do arquivo original salabim_icon.png, não
                // recriado à mão) — é só o círculo dando a pulsada, o
                // pictograma vem por cima em camadas separadas.
                const Image(
                  image: AssetImage('assets/icons/salabim_icon_circle.png'),
                  width: _circleSize,
                  height: _circleSize,
                ),
                // Corpo do mago (chapéu, rosto, barba, estrela, brilho) —
                // estático e 100% opaco o tempo todo, sem animação.
                const Image(
                  image: AssetImage('assets/icons/salabim_mark_body.png'),
                  width: _markSize,
                  fit: BoxFit.contain,
                ),
                // Os 3 tracinhos de som saindo da boca do mago, cada um
                // aparecendo na sua janela de tempo dentro dos 2s totais.
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) => Opacity(
                    opacity: _wave1Window.transform(_waveController.value),
                    child: const Image(
                      image: AssetImage('assets/icons/salabim_mark_wave1.png'),
                      width: _markSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) => Opacity(
                    opacity: _wave2Window.transform(_waveController.value),
                    child: const Image(
                      image: AssetImage('assets/icons/salabim_mark_wave2.png'),
                      width: _markSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) => Opacity(
                    opacity: _wave3Window.transform(_waveController.value),
                    child: const Image(
                      image: AssetImage('assets/icons/salabim_mark_wave3.png'),
                      width: _markSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
