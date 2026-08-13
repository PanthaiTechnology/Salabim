import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/listen/presentation/listen_screen.dart';
import 'features/result/presentation/result_screen.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'features/text_search/presentation/text_search_screen.dart';
import 'data/models/track.dart';

final _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    ShellRoute(
      builder: (context, state, child) => _MainShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const ListenScreen()),
        GoRoute(path: '/search', builder: (context, state) => const TextSearchScreen()),
        GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
      ],
    ),
    GoRoute(
      path: '/result',
      builder: (context, state) => ResultScreen(track: state.extra as Track),
    ),
  ],
);

class SalabimApp extends StatelessWidget {
  const SalabimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Salabim',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}

class _MainShell extends StatelessWidget {
  const _MainShell({required this.child});
  final Widget child;

  int _indexForLocation(String location) {
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/history')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(location);

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              context.go('/search');
            case 2:
              context.go('/history');
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.graphic_eq_rounded), label: 'Ouvir'),
          BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'Buscar'),
          BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: 'Histórico'),
        ],
      ),
    );
  }
}
