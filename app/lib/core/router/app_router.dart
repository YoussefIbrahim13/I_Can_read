import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_screen.dart';
import '../../features/add_book/presentation/add_book_screen.dart';
import '../../features/book_detail/presentation/book_detail_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/reader/presentation/reader_screen.dart';
import '../../features/sessions/presentation/sessions_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../../features/today/presentation/today_screen.dart';
import '../../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/app_navigation_bar.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Read, not watched: completing onboarding flips this flag, and watching it
  // would throw away the whole router — and the navigation stack with it — at
  // the exact moment the reader is being sent somewhere. The welcome screen
  // navigates on its own once it has written the flag.
  final hasOnboarded = ref.read(appSettingsProvider).hasOnboarded;

  return GoRouter(
    initialLocation: hasOnboarded ? '/today' : '/welcome',
    routes: [
      // Outside the shell: the tab bar would offer four ways to skip a screen
      // whose whole job is to be answered once.
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const OnboardingScreen(),
      ),
      // Outside the shell: signing in is one task with one way out, and it
      // closes itself the moment it succeeds.
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountScreen(),
      ),
      // Outside the shell: adding a book is a focused task, so the tab bar
      // would only offer a way to abandon it half-done.
      GoRoute(
        path: '/books/add',
        builder: (context, state) => const AddBookScreen(),
      ),
      // Outside the shell too, but for a different reason: the reader arrived
      // from one particular book on one particular shelf, and the way out is
      // back to it rather than sideways into another tab.
      GoRoute(
        path: '/books/:id',
        builder: (context, state) =>
            BookDetailScreen(bookId: state.pathParameters['id']!),
      ),
      // Also outside the shell, and for the same reason: setting a goal is one
      // task with one way out.
      GoRoute(
        path: '/books/:id/plan',
        builder: (context, state) =>
            PlanScreen(bookId: state.pathParameters['id']!),
      ),
      // Also outside the shell: the page fills the screen, and a tab bar under
      // it would be an invitation to stop reading.
      GoRoute(
        path: '/books/:id/read',
        builder: (context, state) {
          int? page(String name) =>
              int.tryParse(state.uri.queryParameters[name] ?? '');
          return ReaderScreen(
            bookId: state.pathParameters['id']!,
            startPage: page('page'),
            // Absent when a tapped reminder brought the reader here; the
            // screen works the day's portion out from the plan instead.
            fromPage: page('from'),
            toPage: page('to'),
          );
        },
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
