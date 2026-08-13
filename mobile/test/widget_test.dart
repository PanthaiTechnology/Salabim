// Smoke test: garante que o app sobe sem crashar e mostra a tela inicial (Listen).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salabim/app.dart';

void main() {
  testWidgets('Salabim inicia na tela de escuta com o botão principal', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SalabimApp()));

    // O app abre na capa (SplashScreen): só o símbolo, nada mais na tela.
    expect(find.byType(Image), findsOneWidget);

    // A capa fica 1s antes de navegar sozinha pra tela de escuta — avança
    // esse tempo e mais um tanto pra cobrir a transição de rota inteira.
    // pumpAndSettle não dá pra usar daqui em diante: o PulseButton da tela
    // de escuta anima em loop infinito (idle pulse) assim que monta, então
    // "settle" nunca aconteceria.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));

    // Identifica a logo da tela de escuta pelo asset (não só "algum Image"
    // — durante a transição de rota os dois Images, capa e tela de
    // escuta, podem coexistir por um instante).
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/icons/salabim_logo_lockup.png',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.hearing_rounded), findsOneWidget); // ícone do modo "Ouvir" por padrão
  });
}
