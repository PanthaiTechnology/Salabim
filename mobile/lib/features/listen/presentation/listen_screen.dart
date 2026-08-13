import 'dart:math';

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
  // Mensagens de "não encontrado" — sorteadas aleatoriamente, tom leve e
  // descontraído (nunca debochando de verdade, sempre convidando a tentar
  // de novo). Cantar zoa com o "talento" de cantor e lembra que cada
  // tentativa ajuda a treinar o reconhecimento; Ouvir é mais sobre "não
  // captei o som", tom diferente porque o motivo é outro (ambiente/volume,
  // não a pessoa em si).
  static const _notFoundMessagesHum = [
    'Hmm, isso nem o Simon Cowell reconheceria 😂 Bora tentar de novo?',
    'Precisando de aula de canto? 😅 Brincadeira! Cada tentativa nos ajuda a ficar mais espertos.',
    'Tenho certeza que você canta melhor que isso! Na próxima você acerta 🎤',
    'Essa melodia ficou só entre você e o universo 🌌 Tenta de novo?',
    'Ainda estamos aprendendo a te entender... e você nos ajuda toda vez que tenta! 🎶',
    'Ok, isso foi bem... experimental 🎨 Bora tentar de novo, sem vergonha!',
    'Nem o Shazam arriscaria um palpite nessa 😂 Tenta de novo!',
    'Confesso que fiquei confuso(a) com essa 😅 Relaxa e tenta de novo!',
    'Uau. Só isso: uau 😳 Bora tentar de novo?',
    'Essa música tá se escondendo bem de mim 🙈 Tenta de novo?',
  ];

  static const _notFoundMessagesListen = [
    'Putz, não encontrei 💩 Chega mais perto da música e tenta de novo!',
    'Eita, essa passou batido 👀 Aumenta o volume e tenta de novo!',
    'Hmm, não rolou dessa vez 😅 Chega mais pertinho da fonte do som!',
    'Essa foi difícil até pra mim 🕵️ Tenta de novo, mais perto do som!',
    'Silêncio na linha por aqui... 🤫 Aumenta o volume e tenta de novo!',
    'Essa música tá se escondendo de mim 🙈 Bora tentar de novo?',
    'Acho que meus ouvidos digitais falharam dessa vez 😅 Tenta de novo!',
    'Nada por aqui, capitão 🧐 Chega mais perto e tenta de novo!',
    'Ruído demais, música de menos 📡 Tenta de novo, bem pertinho!',
    'Essa passou voando 🚀 Tenta de novo, mais perto da fonte!',
  ];

  static final _random = Random();

  String _randomNotFoundMessage(ListenMode mode) {
    final pool = mode == ListenMode.hum ? _notFoundMessagesHum : _notFoundMessagesListen;
    return pool[_random.nextInt(pool.length)];
  }

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
  // Sem resistência nenhuma: o botão segue o dedo 1:1, exatamente na
  // distância que o dedo andou — testado com resistência (até com metade
  // da força) e não ficava natural, então foi removida de vez.
  double _liveDragDx = 0;

  double get _buttonOffset => _isDragging ? _liveDragDx : (_slideAnimation?.value ?? 0);

  /// Mapeamento fixo, não alternância: não existe um terceiro modo pra ficar
  /// girando — arrastar pra esquerda sempre aponta pra Cantar, pra direita
  /// sempre aponta pra Ouvir. Arrastar pro lado que já é o modo atual não
  /// faz nada (não tem "próximo" modo pra ir).
  ListenMode _targetModeForDirection(int direction) => direction < 0 ? ListenMode.hum : ListenMode.listen;

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
    setState(() => _liveDragDx += details.delta.dx);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    final velocity = details.primaryVelocity ?? 0;
    final direction = _liveDragDx != 0 ? (_liveDragDx > 0 ? 1 : -1) : (velocity < 0 ? -1 : 1);
    final targetMode = _targetModeForDirection(direction);
    final currentMode = ref.read(listenControllerProvider).mode;
    final isRecording = ref.read(listenControllerProvider).status == ListenStatus.recording;

    final farEnough = _liveDragDx.abs() > _commitThreshold || velocity.abs() > 700;
    final shouldCommit = !isRecording && farEnough && targetMode != currentMode;

    setState(() => _isDragging = false);

    if (shouldCommit) {
      _animateCommit(direction, targetMode);
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
  /// troca pro `targetMode` no instante em que sai de vista, e reaparece do
  /// lado oposto deslizando de volta ao centro já com o novo modo.
  void _animateCommit(int direction, ListenMode targetMode) {
    _slideAnimation = Tween<double>(begin: _liveDragDx, end: direction * _exitOffset)
        .chain(CurveTween(curve: Curves.easeIn))
        .animate(_slideController);

    _slideController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      ref.read(listenControllerProvider.notifier).setMode(targetMode);

      _slideAnimation = Tween<double>(begin: -direction * _exitOffset, end: 0)
          .chain(CurveTween(curve: Curves.easeOutBack))
          .animate(_slideController);
      _slideController.forward(from: 0);
    });
  }

  /// SnackBar com a identidade visual do app (fundo surface escuro, cantos
  /// arredondados, barrinha colorida lateral) em vez do SnackBar cinza
  /// padrão do Material — pra qualquer mensagem parecer parte do app, não
  /// um alerta de sistema genérico. `accent` pode ser um gradiente (mensagem
  /// descontraída de "não encontrado", colorida por modo) ou uma cor sólida
  /// (erro, sempre vermelho — não teria sentido "zoar" um erro de verdade).
  void _showBrandedSnackBar(BuildContext context, String message, {Gradient? gradient, Color? solidColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        elevation: 6,
        margin: const EdgeInsets.all(16),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: const Duration(seconds: 4),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: solidColor,
                gradient: gradient,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotFoundSnackBar(BuildContext context, ListenMode mode) {
    final gradient = mode == ListenMode.hum ? AppColors.humGradient : AppColors.listenGradient;
    _showBrandedSnackBar(context, _randomNotFoundMessage(mode), gradient: gradient);
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
        _showNotFoundSnackBar(context, next.mode);
      }
      if (next.status == ListenStatus.error && next.errorMessage != null) {
        _showBrandedSnackBar(context, next.errorMessage!, solidColor: AppColors.error);
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
                  if (state.mode == ListenMode.hum) {
                    // Cantar: toca de novo pra ENCERRAR a gravação na hora
                    // (não cancela) — usa o que já foi cantado até aqui pra
                    // buscar, sem precisar esperar o silêncio ser detectado
                    // ou o tempo máximo acabar. Pedido explícito do
                    // usuário: dar controle manual sem mudar os parâmetros
                    // técnicos de análise (duração, silêncio) em si.
                    controller.finishRecordingNow();
                  } else {
                    // Ouvir: continua cancelando — a busca já acontece
                    // sozinha em segmentos curtos automáticos, não precisa
                    // desse controle manual.
                    controller.cancel();
                  }
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
          Text(
            state.mode == ListenMode.hum ? 'toca pra finalizar e buscar' : 'toca de novo pra cancelar',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
        const Spacer(flex: 2),
      ],
    );
  }
}
