import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/track.dart';

/// Botão circular grande, com pulso animado que cresce com a amplitude do
/// áudio captado — referência direta ao selo do Shazam, mudando de cor
/// conforme o modo (roxo = ouvir, rosa = cantarolar).
///
/// Durante a gravação, o botão central e os anéis ao redor reagem
/// organicamente ao que está entrando no microfone: o volume (amplitude
/// suavizada) controla o quanto ele "respira", e a variação recente desse
/// volume — um proxy simples de "quão movimentado" é o som, sem precisar de
/// FFT/análise de frequência de verdade — controla um tremor sutil
/// sobreposto. Uma nota sustentada pulsa suave e constante; uma melodia
/// cantarolada com mais variação de tom vibra de forma mais viva. Funciona
/// igual para os dois modos (ouvir e cantarolar), já que ambos alimentam o
/// mesmo `amplitude` vindo do microfone.
class PulseButton extends StatefulWidget {
  const PulseButton({
    super.key,
    required this.mode,
    required this.isRecording,
    required this.isProcessing,
    required this.amplitude,
    required this.onTap,
  });

  final ListenMode mode;
  final bool isRecording;
  final bool isProcessing;
  final double amplitude;
  final VoidCallback onTap;

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton> with TickerProviderStateMixin {
  late final AnimationController _idlePulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  // Loop de simulação a 60fps, ativo só enquanto grava: suaviza as leituras
  // de amplitude (que chegam ~10x/s do AudioRecorderService) em algo fluido,
  // e deriva um "wobble" orgânico a partir de quanto o volume anda variando.
  late final Ticker _reactiveTicker = createTicker(_onTick);
  final List<double> _recentSamples = [];
  double _smoothedVolume = 0.0;
  double _wobblePhase = 0.0;
  double _wobble = 0.0;

  // Animação de "Processando...": o ícone do mago some e reaparece em loop
  // (fade + leve encolhida, nunca some por completo — sempre mantém uma
  // presença mínima) enquanto um arco gira ao redor dele, sincronizado no
  // mesmo controller — uma rotação completa por respiração. Um único ciclo
  // (0 -> 1) começa E termina com o ícone 100% visível (ver
  // _processingOpacity/_processingScale abaixo), então o loop nunca "pisca"
  // ou dá salto perceptível na costura entre uma repetição e a próxima.
  late final AnimationController _processingController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  static final Animatable<double> _processingOpacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.22).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 0.22, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 50),
  ]);

  static final Animatable<double> _processingScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 50),
  ]);

  @override
  void initState() {
    super.initState();
    if (widget.isRecording) _reactiveTicker.start();
    if (widget.isProcessing) _processingController.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isRecording && !oldWidget.isRecording) {
      _recentSamples.clear();
      _reactiveTicker.start();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _reactiveTicker.stop();
      setState(() {
        _smoothedVolume = 0.0;
        _wobble = 0.0;
      });
    }

    if (widget.isRecording && widget.amplitude != oldWidget.amplitude) {
      _recentSamples.add(widget.amplitude);
      if (_recentSamples.length > 8) _recentSamples.removeAt(0);
    }

    if (widget.isProcessing && !oldWidget.isProcessing) {
      _processingController.repeat();
    } else if (!widget.isProcessing && oldWidget.isProcessing) {
      _processingController.stop();
      _processingController.value = 0;
    }
  }

  void _onTick(Duration elapsed) {
    // Suaviza o volume alvo (evita "pulos" a cada nova leitura do
    // microfone, que chega em degraus a cada ~100ms).
    _smoothedVolume += (widget.amplitude - _smoothedVolume) * 0.18;

    // Desvio-padrão das últimas amostras ~ quão instável/rico está o som
    // agora — usado só pra modular velocidade e força de um tremor visual,
    // não é uma análise de frequência real, mas dá a variação orgânica
    // pedida sem o custo de rodar FFT em cima do áudio.
    final jitter = _recentSamples.length < 2 ? 0.0 : _normalizedJitter(_recentSamples);
    _wobblePhase += 0.12 + jitter * 0.9;
    _wobble = math.sin(_wobblePhase) * jitter;

    setState(() {});
  }

  double _normalizedJitter(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    return (math.sqrt(variance) * 4).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _idlePulse.dispose();
    _reactiveTicker.stop();
    _reactiveTicker.dispose();
    _processingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.mode == ListenMode.listen ? AppColors.listenGradient : AppColors.humGradient;
    final glowColor = widget.mode == ListenMode.listen ? AppColors.primary : AppColors.secondary;

    // Escala orgânica combinando volume suavizado + tremor de variação —
    // aplicada tanto no círculo central quanto nos anéis ao redor, cada um
    // com um ganho diferente pra dar sensação de profundidade/camadas.
    final coreScale = 1.0 + _smoothedVolume * 0.22 + _wobble * 0.05;
    final ringScale = 1.0 + _smoothedVolume * 0.42 + _wobble * 0.08;
    final echoRingScale = 1.0 + _smoothedVolume * 0.62 + _wobble * 0.12;
    final intensity = _smoothedVolume.clamp(0.0, 1.0);

    return GestureDetector(
      // `opaque` (não o padrão `deferToChild`): sem isso, só registra toque
      // onde tem pixel desenhado de verdade — como o botão é um círculo
      // dentro de uma caixa quadrada de 260x260, os CANTOS da caixa (fora
      // do círculo visível) não respondiam a toque nenhum. Bug real
      // encontrado em teste: "toque pra finalizar" no modo Cantar às vezes
      // não fazia nada, mesmo com o dedo dentro da área do botão.
      behavior: HitTestBehavior.opaque,
      onTap: widget.isProcessing ? null : widget.onTap,
      child: SizedBox(
        width: 260,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.isRecording) ...[
              // Anel "eco": o mais externo e mais transparente, reage mais forte
              // que os demais — reforça a sensação de onda se propagando.
              Opacity(
                opacity: (0.12 + intensity * 0.18).clamp(0.0, 0.3),
                child: Transform.scale(
                  scale: echoRingScale,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25 + intensity * 0.35), width: 2),
                  ),
                ),
              ),
            ] else
              AnimatedBuilder(
                animation: _idlePulse,
                builder: (context, _) {
                  final scale = 1.0 + (_idlePulse.value * 0.06);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: gradient,
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.35),
                            blurRadius: 40,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            Transform.scale(
              scale: widget.isRecording ? coreScale : 1.0,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient,
                  boxShadow: widget.isRecording
                      ? [
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.3 + intensity * 0.3),
                            blurRadius: 30 + intensity * 30,
                            spreadRadius: 2 + intensity * 8,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: widget.isProcessing
                      ? _ProcessingMark(controller: _processingController)
                      : widget.isRecording
                          ? const Icon(Icons.stop_rounded, color: Colors.white, size: 64)
                          // Ícone parado: o próprio mago da identidade visual, só o
                          // desenho branco (sem o fundo circular colorido original —
                          // ver assets/icons/salabim_mark_white.png) por cima do
                          // preenchimento em degradê do botão, que passa a fazer as
                          // vezes do "círculo" do ícone original.
                          : Image.asset('assets/icons/salabim_mark_white.png', width: 108, fit: BoxFit.contain),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mago "respirando" enquanto processa: some (nunca por completo) e volta a
/// aparecer, com um arco girando ao redor sincronizado na mesma volta —
/// termina cada ciclo com o ícone 100% visível de novo, então o loop nunca
/// dá um salto perceptível na costura entre uma repetição e a próxima.
class _ProcessingMark extends StatelessWidget {
  const _ProcessingMark({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final opacity = _PulseButtonState._processingOpacity.evaluate(controller);
        final scale = _PulseButtonState._processingScale.evaluate(controller);
        // O arco fica mais aceso exatamente quando o mago está mais apagado
        // — como se a "energia" migrasse de um pro outro — e gira uma volta
        // inteira por respiração.
        final arcAlpha = 0.35 + (1 - opacity) * 0.45;
        return SizedBox(
          width: 128,
          height: 128,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: controller.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(122, 122),
                  painter: _LoadingArcPainter(color: Colors.white.withValues(alpha: arcAlpha)),
                ),
              ),
              Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Image.asset('assets/icons/salabim_mark_white.png', width: 92, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Arco de ~270° com esmaecimento gradual (SweepGradient de transparente até
/// a cor) — o "rastro de cometa" clássico de indicadores de carregamento
/// modernos, em vez de um círculo cheio parado.
class _LoadingArcPainter extends CustomPainter {
  _LoadingArcPainter({required this.color});

  final Color color;

  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0), color],
        startAngle: 0,
        endAngle: _sweep,
      ).createShader(rect);
    canvas.drawArc(rect.deflate(3), 0, _sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _LoadingArcPainter oldDelegate) => oldDelegate.color != color;
}
