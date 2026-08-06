import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../state/app_providers.dart';
import 'widgets/mode_selector.dart';
import 'widgets/pulse_button.dart';

/// Tela principal — o coração do Salabim: um único botão que serve tanto para
/// "ouvir a música tocando" (Shazam) quanto para "cantarolar/assobiar/cantar"
/// (Hum to Search), alternado pelo ModeSelector acima do botão.
class ListenScreen extends ConsumerWidget {
  const ListenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listenControllerProvider);
    final controller = ref.read(listenControllerProvider.notifier);

    ref.listen(listenControllerProvider, (previous, next) {
      if (next.result != null && previous?.result != next.result) {
        context.push('/result', extra: next.result).then((_) => controller.reset());
      }
      if (next.status == ListenStatus.notFound) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não reconhecemos essa música. Tenta de novo, bem pertinho da fonte de som 🎧')),
        );
      }
      if (next.status == ListenStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    final statusLabel = switch (state.status) {
      ListenStatus.idle => state.mode.label == 'Ouvir música'
          ? 'Toca para identificar a música'
          : 'Toca e cantarole, assobie ou cante',
      ListenStatus.recording => 'Escutando...',
      ListenStatus.identifying => 'Identificando...',
      ListenStatus.notFound => 'Não encontramos essa música',
      ListenStatus.error => 'Algo deu errado',
    };

    return Column(
      children: [
        const SizedBox(height: 24),
        Text(
          'Salabim',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            foreground: Paint()
              ..shader = AppColors.listenGradient.createShader(const Rect.fromLTWH(0, 0, 160, 40)),
          ),
        ),
        const Spacer(),
        ModeSelector(mode: state.mode, onChanged: controller.setMode),
        const Spacer(),
        PulseButton(
          mode: state.mode,
          isRecording: state.status == ListenStatus.recording,
          isProcessing: state.status == ListenStatus.identifying,
          amplitude: state.amplitude,
          onTap: () {
            if (state.status == ListenStatus.recording) {
              controller.stopAndIdentify();
            } else if (state.status == ListenStatus.idle || state.status == ListenStatus.notFound || state.status == ListenStatus.error) {
              controller.startListening();
            }
          },
        ),
        const SizedBox(height: 24),
        Text(statusLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
        const Spacer(flex: 2),
      ],
    );
  }
}
