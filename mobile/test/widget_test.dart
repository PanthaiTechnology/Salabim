// Smoke test: garante que o app sobe sem crashar e mostra a tela inicial (Listen).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salabim/app.dart';

void main() {
  testWidgets('Salabim inicia na tela de escuta com o botão principal', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SalabimApp()));
    // pumpAndSettle não é usado aqui de propósito: o PulseButton anima em loop
    // infinito (idle pulse), então "settle" nunca aconteceria.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Image), findsOneWidget); // logo no topo
    expect(find.byIcon(Icons.hearing_rounded), findsOneWidget); // ícone do modo "Ouvir" por padrão
  });
}
