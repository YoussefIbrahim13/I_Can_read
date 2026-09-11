import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_screen.dart';
import '../../features/account/presentation/change_password_screen.dart';
import '../../features/account/presentation/delete_account_screen.dart';
import '../../features/account/presentation/devices_screen.dart';
import '../../features/account/presentation/password_reset_screen.dart';
import '../../features/account/presentation/verify_email_screen.dart';
import '../../features/add_book/presentation/add_book_screen.dart';
import '../../features/backup/presentation/backup_screen.dart';
import '../../features/book_detail/presentation/book_detail_screen.dart';
import '../../features/book_detail/presentation/reading_record_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/reader/presentation/reader_screen.dart';
import '../../features/relink/presentation/locate_file_screen.dart';
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
      // A step off the sign-in screen rather than a child of it: the reader
      // came here because the password they have does not work, so the screen
      // that asked for it has nothing more to offer until this one is done.
      // Its own screen for the same reason as the reset: it is one deliberate
      // task, and the only irreversible one in the app.
      GoRoute(
        path: '/account/delete',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      // Outside the shell like the account screens: one task, one way out.
      // Restoring writes over the whole library, so the tab bar has no
      // business sitting under it offering somewhere else to be.
      GoRoute(
        path: '/settings/backup',
        builder: (context, state) => const BackupScreen(),
      ),
      GoRoute(
        path: '/account/reset',
        builder: (context, state) => PasswordResetScreen(
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),
      // The three account-management screens, outside the shell like every
      // other account screen: each is one deliberate task with one way out, and
      // a tab bar underneath would only offer a way to leave it half-done.
      GoRoute(
        path: '/account/password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/account/verify-email',
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: '/account/sessions',
        builder: (context, state) => const DevicesScreen(),
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
      // Outside the shell for the same reason as adding a book: it is one task
      // — hand this book its PDF back — and the way out is back to the book.
      GoRoute(
        path: '/books/:id/locate',
        builder: (context, state) =>
            LocateFileScreen(bookId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/books/:id/plan/sessions',
        builder: (context, state) =>
            SessionsScreen(bookId: state.pathParameters['id']!),
      ),
      // Outside the shell like the rest of the book's screens: the reader came
      // from one book's record and the way out is back to that book.
      GoRoute(
        path: '/books/:id/record',
        builder: (context, state) =>
            ReadingRecordScreen(bookId: state.pathParameters['id']!),
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
        // Words, not icons: v2 dropped the glyphs because none of them meant
        // the thing its label already says.
        labels: [
          l10n.navToday,
          l10n.navLibrary,
          l10n.navStats,
          l10n.navSettings,
        ],
      ),
    );
  }
}
