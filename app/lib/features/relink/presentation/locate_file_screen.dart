import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/cover_plate.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../l10n/app_localizations.dart';
import '../../add_book/data/book_importer.dart';
import '../../plan/application/plan_providers.dart';
import '../application/locate_file_controller.dart';

/// Puts a book back together with its PDF on this device.
///
/// Reached from the "file not on this device" badge, which is what a reader
/// sees after signing in on a new phone: the account brought the plan and the
/// progress down, but never the file, and this is where they hand it back.
class LocateFileScreen extends ConsumerWidget {
  const LocateFileScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(locateFileControllerProvider);
    final book = ref.watch(bookProvider(bookId)).asData?.value;

    return PopScope(
      // Backing out of the confirmation must not strand the copied PDF.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(
            ref.read(locateFileControllerProvider.notifier).discardPending(),
          );
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenBackBar(title: l10n.locateTitle),
              const Divider(),
              Expanded(
                child: switch (state) {
                  LocateIdle() => _PickStep(
                    bookId: bookId,
                    title: book?.title ?? '',
                  ),
                  LocateImporting(:final stage) => _ImportingStep(stage: stage),
                  LocateUnrecognised() => _ConfirmStep(pending: state),
                  LocateWrongBook(:final owner) => _WrongBookStep(
                    bookId: bookId,
                    owner: owner,
                  ),
                  LocateLinked(:final title) => _LinkedStep(title: title),
                  LocateFailed(:final failure) => _FailedStep(failure: failure),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shape every step shares, matching the add-book flow: content in the
/// gutter, and the primary action pinned above a hairline so it does not move
/// between states.
class _Step extends StatelessWidget {
  const _Step({
    required this.child,
    this.action,
    this.secondaryAction,
    this.centred = true,
  });

  final Widget child;
  final Widget? action;
  final Widget? secondaryAction;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: 22,
            ),
            child: centred
                ? Center(child: child)
                : Align(alignment: AlignmentDirectional.topStart, child: child),
          ),
        ),
        if (action case final action?) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x4,
              AppSpacing.x3 - 2,
              AppSpacing.x4,
              AppSpacing.x4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                action,
                if (secondaryAction case final secondary?) ...[
                  const SizedBox(height: 4),
                  secondary,
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> _pick(WidgetRef ref, String bookId) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  if (picked == null) return;

  await ref
      .read(locateFileControllerProvider.notifier)
      .offerFile(
        bookId: bookId,
        fileName: picked.name,
        sizeBytes: await picked.length(),
        openStream: picked.readAsByteStream,
      );
}

class _PickStep extends ConsumerWidget {
  const _PickStep({required this.bookId, required this.title});

  final String bookId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _Step(
      action: OutlinedButton(
        onPressed: () => _pick(ref, bookId),
        child: Text(l10n.pickPdfFile),
      ),
      child: Column(
        children: [
          const CoverPlate(width: 88, height: 118),
          const SizedBox(height: 22),
          Text(
            l10n.locateIntro(title),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.locateIntroHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ImportingStep extends StatelessWidget {
  const _ImportingStep({required this.stage});

  final ImportStage stage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    const order = ImportStage.values;
    final label = switch (stage) {
      ImportStage.copying => l10n.importCopying,
      ImportStage.hashing => l10n.importHashing,
      ImportStage.readingPages => l10n.importReadingPages,
    };

    return _Step(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          // Determinate: the stages are known, and a spinner would claim less
          // than we actually know about how far along this is.
          LinearProgressIndicator(
            value: (order.indexOf(stage) + 1) / order.length,
          ),
        ],
      ),
    );
  }
}

/// The question a file the book has never seen raises.
///
/// Two readers arrive here for different reasons — one re-downloaded the same
/// book from a different source, one is linking a genuinely different edition —
/// and only the second one's page numbers need to move. So the choice is only
/// put to them when the page counts actually disagree.
class _ConfirmStep extends ConsumerStatefulWidget {
  const _ConfirmStep({required this.pending});

  final LocateUnrecognised pending;

  @override
  ConsumerState<_ConfirmStep> createState() => _ConfirmStepState();
}

class _ConfirmStepState extends ConsumerState<_ConfirmStep> {
  /// Keeping the numbers is the default: it changes nothing the reader did not
  /// ask for, and it is right whenever the two copies are the same book.
  var _rescale = false;
  var _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    await ref
        .read(locateFileControllerProvider.notifier)
        .confirmUnrecognised(rescaleProgress: _rescale);
  }

  Future<void> _chooseAnother() async {
    await ref.read(locateFileControllerProvider.notifier).discardPending();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pending = widget.pending;

    return _Step(
      centred: false,
      action: OutlinedButton(
        onPressed: _busy ? null : _confirm,
        child: Text(l10n.locateLinkFile),
      ),
      secondaryAction: TextButton(
        onPressed: _busy ? null : _chooseAnother,
        child: Text(l10n.locateChooseAnother),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.locateDifferentCopy, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(
            l10n.locateDifferentCopyBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          Text(
            pending.pageCountDiffers
                ? l10n.locatePageCountDiffers(
                    pending.pdf.pageCount,
                    pending.recordedPageCount,
                  )
                : l10n.locateSamePageCount,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.appColors.muted,
            ),
          ),
          if (pending.pageCountDiffers) ...[
            const SizedBox(height: AppSpacing.x4),
            AppSegmentedControl<bool>(
              value: _rescale,
              onChanged: _busy
                  ? (_) {}
                  : (value) => setState(() => _rescale = value),
              segments: [
                AppSegment(value: false, label: l10n.locateKeepPages),
                AppSegment(value: true, label: l10n.locateRescale),
              ],
            ),
            const SizedBox(height: AppSpacing.x3),
            Text(
              _rescale ? l10n.locateRescaleHint : l10n.locateKeepPagesHint,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WrongBookStep extends ConsumerWidget {
  const _WrongBookStep({required this.bookId, required this.owner});

  final String bookId;
  final Book owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _Step(
      action: OutlinedButton(
        onPressed: () => _pick(ref, bookId),
        child: Text(l10n.locateChooseAnother),
      ),
      secondaryAction: TextButton(
        onPressed: () {
          ref.read(locateFileControllerProvider.notifier).reset();
          context.pushReplacement('/books/${owner.id}');
        },
        child: Text(l10n.addBookOpenExisting),
      ),
      child: Column(
        children: [
          Text(
            l10n.locateWrongBook,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.locateWrongBookBody(owner.title),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LinkedStep extends ConsumerWidget {
  const _LinkedStep({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _Step(
      action: OutlinedButton(
        onPressed: () {
          ref.read(locateFileControllerProvider.notifier).reset();
          if (context.canPop()) context.pop();
        },
        child: Text(l10n.actionDone),
      ),
      child: Column(
        children: [
          const CoverPlate(width: 88, height: 118),
          const SizedBox(height: 22),
          Text(
            l10n.locateLinked(title),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FailedStep extends ConsumerWidget {
  const _FailedStep({required this.failure});

  final PdfImportFailure? failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final message = failure == PdfImportFailure.notAPdf
        ? l10n.importNotAPdf
        : l10n.importFailed;

    return _Step(
      action: OutlinedButton(
        onPressed: () =>
            ref.read(locateFileControllerProvider.notifier).reset(),
        child: Text(l10n.actionRetry),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 30, color: theme.colorScheme.error),
          const SizedBox(height: AppSpacing.x4),
          Text(
            message,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
