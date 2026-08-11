import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Resultado do diálogo de feedback: se o usuário confirmou que está certo,
/// ou marcou como errado e (opcionalmente) informou o nome real da música.
class FeedbackResult {
  final bool wasCorrect;
  final String? correctedTitle;
  final String? correctedArtist;

  const FeedbackResult({required this.wasCorrect, this.correctedTitle, this.correctedArtist});
}

/// "Essa música está certa?" — se não, pede o nome real pra guardar como
/// correção. É a peça de UI do sistema de correção/feedback: não é um
/// modelo de IA sendo retreinado (isso é do ACRCloud, fechado), mas uma
/// memória de correções real que o Salabim aplica da próxima vez que o
/// mesmo engano acontecer.
class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key, required this.currentTitle, required this.currentArtist});

  final String currentTitle;
  final String currentArtist;

  static Future<FeedbackResult?> show(BuildContext context, {required String title, required String artist}) {
    return showDialog<FeedbackResult>(
      context: context,
      builder: (_) => FeedbackDialog(currentTitle: title, currentArtist: artist),
    );
  }

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  bool _askingForCorrection = false;
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_askingForCorrection) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Essa música está certa?'),
        content: Text(
          '"${widget.currentTitle}" — ${widget.currentArtist}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _askingForCorrection = true),
            child: const Text('Não, está errada'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(const FeedbackResult(wasCorrect: true)),
            child: const Text('Sim, está certa'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Qual é a música certa?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            onChanged: (_) => setState(() {}), // reavalia se o botão "Salvar" pode ligar
            decoration: const InputDecoration(labelText: 'Nome da música'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _artistController,
            decoration: const InputDecoration(labelText: 'Artista (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _titleController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(FeedbackResult(
                    wasCorrect: false,
                    correctedTitle: _titleController.text.trim(),
                    correctedArtist: _artistController.text.trim().isEmpty ? null : _artistController.text.trim(),
                  )),
          child: const Text('Salvar correção'),
        ),
      ],
    );
  }
}
