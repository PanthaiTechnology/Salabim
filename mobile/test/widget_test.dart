// Smoke test: garante que o app sobe sem crashar e mostra a tela inicial (Listen).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salabim/app.dart';

void main() {
  testWidgets('Salabim inicia na tela de escuta com o botão principal', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SalabimApp()));

    // O app abre na capa (SplashScreen): só o símbolo (círculo + mago em
    // camadas separadas pra animação de introdução), nada mais na tela.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/icons/salabim_icon_circle.png',
      ),
      findsOneWidget,
    );

    // A capa fica 2s antes de navegar sozinha pra tela de escuta — avança
    // esse tempo e mais um tanto pra cobrir a transição de rota inteira.
    // pumpAndSettle não dá pra usar daqui em diante: o PulseButton da tela
    // de escuta anima em loop infinito (idle pulse) assim que monta, então
    // "settle" nunca aconteceria.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));

    // Cabeçalho da tela de escuta: só o wordmark "Salabim" agora (recortado
    // da logo de verdade, sem o ícone — que saiu do topo por ficar
    // redundante com o mesmo desenho já aparecendo no botão principal).
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/icons/salabim_wordmark.png',
      ),
      findsOneWidget,
    );
    // Ícone do botão principal (mesmo desenho do mago pros dois modos, só
    // muda quando grava/processa) — não é mais um Icon de fonte de ícones.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/icons/salabim_mark_white.png',
      ),
      findsOneWidget,
    );
  });
}
