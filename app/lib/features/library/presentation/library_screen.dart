import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/cover_plate.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../plan/application/plan_providers.dart';
import '../application/library_providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // The kicker counts the shelf the screen opens on, which is the one the
    // reader thinks of as "my library".
    final reading = ref
        .watch(booksByStatusProvider(BookStatus.reading))
        .asData
        ?.value;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                kicker: reading == null
                    ? null
                    : l10n.libraryBookCount(reading.length),
                title: l10n.navLibrary,
                // The design has no floating action button; adding a book is a
                // deliberate, header-level act, not something that hovers over
                // the shelf and covers the last row.
                trailing: OutlinedButton.icon(
                  onPressed: () => context.push('/books/add'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.addBook),
                ),
                divider: false,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                child: TabBar(
                  // Left-packed and only as wide as their labels, so the three
                  // shelves read as a line of links under the title rather
                  // than as three equal buttons.
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: EdgeInsets.zero,
                  // The bar sits inside the gutter, so its own divider would
                  // stop short at both ends; the rule below is full-bleed.
                  dividerHeight: 0,
                  labelPadding: const EdgeInsetsDirectional.only(
                    end: AppSpacing.gutter,
                  ),
                  tabs: [
                    Tab(height: 34, text: l10n.libraryTabReading),
                    Tab(height: 34, text: l10n.libraryTabFinished),
                    Tab(height: 34, text: l10n.libraryTabArchived),
                  ],
                ),
              ),
              const Divider(),
              const Expanded(
                child: TabBarView(
                  children: [
                    _Shelf(status: BookStatus.reading),
                    _Shelf(status: BookStatus.finished),
                    _Shelf(status: BookStatus.archived),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shelf extends ConsumerWidget {
  const _Shelf({required this.status});

  final BookStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final books = ref.watch(booksByStatusProvider(status));
    final missingIds =
        ref.watch(missingFileBookIdsProvider).asData?.value ?? const <String>{};
    final plans =
        ref.watch(activePlansProvider).asData?.value ??
        const <String, ReadingPlan>{};

    return books.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Center(child: Text('$error')),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            title: l10n.libraryEmpty,
            message: l10n.libraryEmptyHint,
            action: OutlinedButton(
              onPressed: () => context.push('/books/add'),
              child: Text(l10n.addBook),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.x1,
            AppSpacing.gutter,
            AppSpacing.x6,
          ),
          itemCount: items.length,
          // A hairline between rows, not a gap between cards: the shelf is one
          // list, and boxing each book would make four books look like four
          // separate screens' worth of content.
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) => _BookRow(
            book: items[index],
            fileMissing: missingIds.contains(items[index].id),
            plan: plans[items[index].id],
          ),
        );
      },
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.book,
    required this.fileMissing,
    required this.plan,
  });

  final Book book;
  final bool fileMissing;

  /// The book's goal, or null while it has none.
  final ReadingPlan? plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return InkWell(
      // The whole row opens the goal — set it the first time, adjust it after.
      // The reader thinks of "the book" as one thing, so tapping any part of
      // it should lead somewhere rather than only the small caption below.
      onTap: () => context.push('/books/${book.id}/plan'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4 - 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CoverPlate(),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author case final author?)
                    Text(
                      author,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: colors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: AppSpacing.x1),
                  if (fileMissing)
                    const _MissingFile()
                  else if (plan case final plan?)
                    _PlanProgress(book: book, plan: plan)
                  else ...[
                    // A page count is a fact about the book, so it sets in the
                    // caption ink rather than in the accent.
                    Text(
                      l10n.bookPageCount(book.pageCount),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Gold, because it is the one thing on the row worth
                    // acting on — not a warning.
                    Text(
                      l10n.libraryNoPlanYet,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far through the plan the reader is: the book-scope rule, its percentage,
/// and the daily portion that produced it.
class _PlanProgress extends StatelessWidget {
  const _PlanProgress({required this.book, required this.plan});

  final Book book;
  final ReadingPlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.appColors;

    final total = plan.endPage - plan.startPage + 1;
    final read = plan.lastPageRead < plan.startPage
        ? 0
        : (plan.lastPageRead > plan.endPage ? plan.endPage : plan.lastPageRead) -
              plan.startPage +
              1;
    final fraction = total == 0 ? 0.0 : read / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(child: BookRule(fraction: fraction, height: 1)),
            const SizedBox(width: AppSpacing.x2),
            Figure(
              AppNumbers.percent(fraction),
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x1 + 1),
        Text(
          '${l10n.libraryReadOfTotal(read, total)} · '
          '${l10n.libraryDailyPortion(plan.pagesPerDay)}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: colors.muted,
          ),
        ),
      ],
    );
  }
}

/// A file that is not on this device.
///
/// Stated in gold at body weight, not in red: the reader did nothing wrong —
/// they are on a different phone, or the file was moved — and there is a
/// one-tap way out.
class _MissingFile extends StatelessWidget {
  const _MissingFile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.fileMissing,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.x1 + 1),
        OutlinedButton(
          // Relinking is not built yet; the add-book flow already recognises a
          // known fingerprint and reattaches the file to its existing book.
          onPressed: () => context.push('/books/add'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: theme.textTheme.labelMedium?.copyWith(fontSize: 12),
          ),
          child: Text(l10n.libraryLocateFile),
        ),
      ],
    );
  }
}
