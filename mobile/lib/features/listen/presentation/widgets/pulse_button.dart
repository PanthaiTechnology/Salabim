import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/track.dart';

/// Botão circular grande, com pulso animado que cresce com a amplitude do
/// áudio captado — referência direta ao selo do Shazam, mudando de cor
/// conforme o modo (roxo = ouvir, rosa = cantarolar).
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

class _PulseButtonState extends State<PulseButton> with SingleTickerProviderStateMixin {
  late final AnimationController _idlePulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _idlePulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.mode == ListenMode.listen ? AppColors.listenGradient : AppColors.humGradient;
    final ringScale = widget.isRecording ? 1.0 + (widget.amplitude * 0.35) : 1.0;

    return GestureDetector(
      onTap: widget.isProcessing ? null : widget.onTap,
      child: SizedBox(
        width: 260,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.isRecording)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 220 * ringScale,
                height: 220 * ringScale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
                ),
              )
            else
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
                            color: (widget.mode == ListenMode.listen ? AppColors.primary : AppColors.secondary)
                                .withValues(alpha: 0.35),
                            blurRadius: 40,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
              child: Center(
                child: widget.isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Icon(
                        widget.isRecording
                            ? Icons.stop_rounded
                            : (widget.mode == ListenMode.listen ? Icons.hearing_rounded : Icons.mic_rounded),
                        color: Colors.white,
                        size: 64,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
