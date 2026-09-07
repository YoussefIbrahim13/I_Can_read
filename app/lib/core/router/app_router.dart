import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/add_book/presentation/add_book_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/sessions/presentation/sessions_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../../features/today/presentation/today_screen.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/app_navigation_bar.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/today',
    routes: [
      // Outside the shell: adding a book is a focused task, so the tab bar
      // would only offer a way to abandon it half-done.
      GoRoute(
        path: '/books/add',
        builder: (context, state) => const AddBookScreen(),
      ),
      // Also outside the shell, and for the same reason: setting a goal is one
      // task with one way out.
      GoRoute(
        path: '/books/:id/plan',
        builder: (context, state) =>
            PlanScreen(bookId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/books/:id/plan/sessions',
        builder: (context, state) =>
            SessionsScreen(bookId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _HomeShell extends StatelessWidget {
  const _HomeShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppNavigationBar(
        selectedIndex: navigationShell.currentIndex,
        // `initialLocation: true` re-selecting the current tab pops it to root.
        onSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        // Outlined throughout — there is no filled "selected" icon, because
        // selection is carried by the gold rule under the label.
        items: [
          AppNavigationItem(
            icon: Icons.wb_sunny_outlined,
            label: l10n.navToday,
          ),
          AppNavigationItem(
            icon: Icons.menu_book_outlined,
            label: l10n.navLibrary,
          ),
          AppNavigationItem(
            icon: Icons.insights_outlined,
            label: l10n.navStats,
          ),
          AppNavigationItem(
            icon: Icons.settings_outlined,
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
