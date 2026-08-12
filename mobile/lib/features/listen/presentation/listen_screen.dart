import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../state/app_providers.dart';
import 'widgets/mode_selector.dart';
import 'widgets/pulse_button.dart';

/// Tela principal — o coração do Salabim: um único toque começa a escutar
/// e já busca em tempo real, em segmentos curtos, sem precisar de um
/// segundo toque para "parar e buscar". O resultado aparece assim que
/// qualquer segmento bater. Serve tanto para "ouvir a música tocando"
/// (Shazam) quanto para "cantarolar/assobiar/cantar" (Hum to Search),
/// alternado pelo ModeSelector acima do botão.
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
      ListenStatus.idle => state.mode == ListenMode.listen
          ? 'Ouça a música e... Salabim !!'
          : 'Cante ou toque a música e... Salabim !!',
      // A busca já acontece automaticamente a cada poucos segundos, sem
      // precisar tocar de novo — o número de tentativa é só pra dar
      // feedback de que o app continua tentando.
      ListenStatus.recording => 'Ouvindo e buscando... (tentativa ${state.attempt + 1})',
      ListenStatus.notFound => 'Não encontramos essa música',
      ListenStatus.error => 'Algo deu errado',
    };

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Deslizar pra qualquer lado alterna entre Ouvir/Cantar — além dos
      // botões do ModeSelector, que continuam funcionando normalmente.
      // Ignora enquanto grava (mesma regra do ModeSelector/setMode) pra
      // não trocar de modo no meio de uma escuta em andamento.
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 150) return; // arrasto fraco/acidental, ignora
        if (state.status == ListenStatus.recording) return;
        final next = state.mode == ListenMode.listen ? ListenMode.hum : ListenMode.listen;
        controller.setMode(next);
      },
      child: Column(
        children: [
          const SizedBox(height: 24),
          Image.asset('assets/icons/salabim_logo_lockup.png', height: 44, fit: BoxFit.contain),
          const Spacer(),
          ModeSelector(mode: state.mode, onChanged: controller.setMode),
          const Spacer(),
          PulseButton(
            mode: state.mode,
            isRecording: state.status == ListenStatus.recording,
            isProcessing: false,
            amplitude: state.amplitude,
            onTap: () {
              if (state.status == ListenStatus.recording) {
                // Cancela antes da hora — a busca em si já acontece sozinha
                // enquanto grava, não é preciso tocar pra "buscar".
                controller.cancel();
              } else {
                controller.startListening();
              }
            },
          ),
          const SizedBox(height: 24),
          Text(statusLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          if (state.status == ListenStatus.recording) ...[
            const SizedBox(height: 4),
            const Text(
              'toca de novo pra cancelar',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}
