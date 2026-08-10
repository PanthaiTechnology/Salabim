import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Botão de prévia: um anel circular fino mostra visualmente quanto do
/// preview já passou (sem números — só a forma), e o ícone central alterna
/// entre "play" parado e barrinhas de áudio animadas enquanto toca. Tocar
/// de novo enquanto as barrinhas estão animando pausa a reprodução.
class PreviewPlayButton extends StatelessWidget {
  const PreviewPlayButton({
    super.key,
    required this.isPlaying,
    required this.progress,
    required this.onTap,
  });

  final bool isPlaying;

  /// 0.0 a 1.0 — quanto do preview já foi reproduzido.
  final double progress;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 3,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.14),
              ),
              child: Center(
                child: isPlaying
                    ? const _AnimatedAudioBars()
                    : const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Três barrinhas oscilando fora de fase — o mesmo tipo de indicador que
/// apps de música usam pra dizer "isso está tocando agora".
class _AnimatedAudioBars extends StatefulWidget {
  const _AnimatedAudioBars();

  @override
  State<_AnimatedAudioBars> createState() => _AnimatedAudioBarsState();
}

class _AnimatedAudioBarsState extends State<_AnimatedAudioBars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const barCount = 3;
    const maxHeight = 16.0;
    const minHeightFactor = 0.3;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final phase = _controller.value * 2 * math.pi + (i * 2.1);
            final factor = minHeightFactor + (1 - minHeightFactor) * (0.5 + 0.5 * math.sin(phase));
            return Container(
              width: 3.5,
              height: maxHeight * factor,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
