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
/// alternado pelo ModeSelector acima do botão OU deslizando o botão
/// central pra qualquer lado (ver _onDragUpdate/_onDragEnd abaixo).
class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});

  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> with SingleTickerProviderStateMixin {
  // Até onde o botão acompanha o dedo antes de travar (sensação de
  // resistência, em vez de seguir infinitamente) — e o quanto de arrasto
  // já é suficiente pra confirmar a troca de modo ao soltar.
  static const _dragMaxOffset = 90.0;
  static const _commitThreshold = 50.0;
  // Distância que o botão "sai" da tela antes de reaparecer do lado oposto
  // já no novo modo — dá a sensação de um botão saindo e outro entrando,
  // não só um teleporte.
  static const _exitOffset = 300.0;

  late final AnimationController _slideController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Animation<double>? _slideAnimation;

  bool _isDragging = false;
  double _liveDragDx = 0;

  double get _buttonOffset => _isDragging ? _liveDragDx : (_slideAnimation?.value ?? 0);

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    // Enquanto uma transição de troca de modo ainda está terminando, ignora
    // um novo arrasto — evita disparar duas trocas de modo encavaladas.
    if (_slideController.isAnimating) return;
    if (ref.read(listenControllerProvider).status == ListenStatus.recording) return;

    setState(() {
      _isDragging = true;
      _liveDragDx = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      final next = _liveDragDx + details.delta.dx;
      _liveDragDx = next.clamp(-_dragMaxOffset, _dragMaxOffset);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    final velocity = details.primaryVelocity ?? 0;
    final isRecording = ref.read(listenControllerProvider).status == ListenStatus.recording;
    final shouldCommit = !isRecording && (_liveDragDx.abs() > _commitThreshold || velocity.abs() > 700);
    final direction = _liveDragDx != 0 ? (_liveDragDx > 0 ? 1 : -1) : (velocity < 0 ? -1 : 1);

    setState(() => _isDragging = false);

    if (shouldCommit) {
      _animateCommit(direction);
    } else {
      _animateSpringBack();
    }
  }

  /// Arrasto curto/fraco demais (ou gravando) — volta suavemente pro centro,
  /// com um leve "quique" (easeOutBack) pra parecer elástico, não travado.
  void _animateSpringBack() {
    _slideAnimation = Tween<double>(begin: _liveDragDx, end: 0)
        .chain(CurveTween(curve: Curves.easeOutBack))
        .animate(_slideController);
    _slideController.forward(from: 0);
  }

  /// Arrasto confirmado: termina de "sair" na direção que já estava indo,
  /// troca o modo no instante em que sai de vista, e reaparece do lado
  /// oposto deslizando de volta ao centro já com o novo modo.
  void _animateCommit(int direction) {
    _slideAnimation = Tween<double>(begin: _liveDragDx, end: direction * _exitOffset)
        .chain(CurveTween(curve: Curves.easeIn))
        .animate(_slideController);

    _slideController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      final controller = ref.read(listenControllerProvider.notifier);
      final current = ref.read(listenControllerProvider).mode;
      controller.setMode(current == ListenMode.listen ? ListenMode.hum : ListenMode.listen);

      _slideAnimation = Tween<double>(begin: -direction * _exitOffset, end: 0)
          .chain(CurveTween(curve: Curves.easeOutBack))
          .animate(_slideController);
      _slideController.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
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

    return Column(
      children: [
        const SizedBox(height: 24),
        Image.asset('assets/icons/salabim_logo_lockup.png', height: 44, fit: BoxFit.contain),
        const Spacer(),
        ModeSelector(mode: state.mode, onChanged: controller.setMode),
        const Spacer(),
        GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: AnimatedBuilder(
            animation: _slideController,
            builder: (context, child) => Transform.translate(
              offset: Offset(_buttonOffset, 0),
              child: child,
            ),
            child: PulseButton(
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
          ),
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
    );
  }
}
