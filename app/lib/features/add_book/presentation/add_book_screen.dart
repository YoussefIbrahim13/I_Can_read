import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/cover_plate.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/add_book_controller.dart';
import '../data/book_importer.dart';

class AddBookScreen extends ConsumerWidget {
  const AddBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(addBookControllerProvider);

    ref.listen<AddBookState>(addBookControllerProvider, (previous, next) {
      if (next is AddBookSaved) {
        // Straight on to the goal, replacing this screen rather than stacking
        // on it: a book with no plan is the one state the app has no use for,
        // and the plan screen names the book, so it confirms the import too.
        ref.read(addBookControllerProvider.notifier).reset();
        context.pushReplacement('/books/${next.bookId}/plan');
      }
    });

    return PopScope(
      // Backing out of the details form must not strand the copied PDF.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(
            ref.read(addBookControllerProvider.notifier).discardPending(),
          );
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenBackBar(title: l10n.addBook),
              const Divider(),
              Expanded(
                child: switch (state) {
                  AddBookIdle() || AddBookSaved() => const _PickStep(),
                  AddBookImporting(:final stage) => _ImportingStep(
                    stage: stage,
                  ),
                  AddBookReady(:final pdf) => _DetailsStep(pdf: pdf),
                  AddBookDuplicate(:final existing, :final relinked) =>
                    _DuplicateStep(title: existing.title, relinked: relinked),
                  AddBookFailed(:final failure) => _FailedStep(
                    failure: failure,
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shape every step shares: content in the gutter, and — when the step has
/// an action — one outlined button pinned above a hairline at the bottom.
///
/// Pinning it means the primary action sits in the same place in all five
/// states, so the flow does not feel like five unrelated screens.
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

class _PickStep extends ConsumerWidget {
  const _PickStep();

  Future<void> _pick(WidgetRef ref) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked == null) return;

    await ref
        .read(addBookControllerProvider.notifier)
        .importPicked(
          fileName: picked.name,
          sizeBytes: await picked.length(),
          // A factory, so the source is read exactly once and on our terms.
          openStream: picked.readAsByteStream,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _Step(
      action: OutlinedButton(
        onPressed: () => _pick(ref),
        child: Text(l10n.pickPdfFile),
      ),
      child: Column(
        children: [
          const CoverPlate(width: 88, height: 118),
          const SizedBox(height: 22),
          Text(
            l10n.addBookIntro,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.addBookIntroHint,
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

/// Import progress as a checklist rather than a spinner.
///
/// The three stages are quick but not instant, and naming them is what stops a
/// slow hash on a large scan from reading as a hang.
class _ImportingStep extends StatelessWidget {
  const _ImportingStep({required this.stage});

  final ImportStage stage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.appColors;

    const order = ImportStage.values;
    final current = order.indexOf(stage);
    final labels = [
      l10n.importCopying,
      l10n.importHashing,
      l10n.importReadingPages,
    ];

    return _Step(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, label) in labels.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    child: Text(
                      index < current ? '✓' : '·',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: index < current
                            ? colors.done
                            : index == current
                            ? theme.colorScheme.onSurface
                            : colors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: index < current
                          ? colors.done
                          : index == current
                          ? theme.colorScheme.onSurface
                          : colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // Determinate, because the stage count is known. A spinner here
          // would claim less than we actually know.
          LinearProgressIndicator(value: (current + 1) / order.length),
        ],
      ),
    );
  }
}

class _DetailsStep extends ConsumerStatefulWidget {
  const _DetailsStep({required this.pdf});

  final ImportedPdf pdf;

  @override
  ConsumerState<_DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends ConsumerState<_DetailsStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.pdf.suggestedTitle,
  );
  final _author = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(addBookControllerProvider.notifier)
        .save(title: _title.text, author: _author.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final megabytes = widget.pdf.sizeBytes / (1024 * 1024);

    return Form(
      key: _formKey,
      child: _Step(
        centred: false,
        action: OutlinedButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.addBookSave),
        ),
        secondaryAction: TextButton(
          onPressed: _saving
              ? null
              : () => ref
                    .read(addBookControllerProvider.notifier)
                    .discardPending(),
          child: Text(l10n.addBookChooseAnother),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Kicker(l10n.addBookDetails),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _title,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: l10n.bookTitle),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.addBookTitleRequired
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _author,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: l10n.bookAuthorOptional),
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.x4),
            // Facts about the file, stated once. The last clause is the
            // privacy promise, and it belongs where the file is described.
            DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall!.copyWith(
                fontSize: 12,
                color: theme.appColors.muted,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${l10n.bookPageCount(widget.pdf.pageCount)} · '),
                  Figure('${megabytes.toStringAsFixed(1)} MB', size: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateStep extends ConsumerWidget {
  const _DuplicateStep({required this.title, required this.relinked});

  final String title;
  final bool relinked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _Step(
      action: OutlinedButton(
        onPressed: () {
          ref.read(addBookControllerProvider.notifier).reset();
          if (context.canPop()) context.pop();
        },
        child: Text(relinked ? l10n.addBookOpenExisting : l10n.actionDone),
      ),
      child: Column(
        children: [
          const CoverPlate(width: 88, height: 118),
          const SizedBox(height: 22),
          Text(
            relinked ? l10n.addBookRelinked(title) : l10n.addBookDuplicate,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (!relinked) ...[
            const SizedBox(height: 10),
            Text(
              l10n.addBookDuplicateBody(title),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
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
        onPressed: () => ref.read(addBookControllerProvider.notifier).reset(),
        child: Text(l10n.actionRetry),
      ),
      child: Column(
        children: [
          // The one place red is allowed: a genuine system failure, not a
          // state the reader caused.
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
