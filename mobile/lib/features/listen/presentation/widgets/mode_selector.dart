import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/track.dart';

/// Toggle "Ouvir música" vs "Cantarolar/Assobiar" — é aqui que o Salabim mostra
/// visualmente que é Shazam + Hum to Search num só lugar.
class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.mode, required this.onChanged});

  final ListenMode mode;
  final ValueChanged<ListenMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // Cantar primeiro: é o diferencial do Salabim (Hum to Search), por
        // isso aparece antes de Ouvir — e também é o modo selecionado por
        // padrão ao abrir o app (ver ListenState.mode).
        children: [ListenMode.hum, ListenMode.listen].map((m) {
          final selected = m == mode;
          return GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                gradient: selected
                    ? (m == ListenMode.listen ? AppColors.listenGradient : AppColors.humGradient)
                    : null,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Text(
                m == ListenMode.listen ? 'Ouvir' : 'Cantar',
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
