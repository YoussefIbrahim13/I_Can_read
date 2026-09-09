import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import 'reading_pace.dart';

/// The reader's pace across every book they have ever read, measured.
///
/// Library-wide and lifetime on purpose. A reader has one reading speed, and
/// the screens that use this are predicting how long a portion will take — a
/// question a wider sample answers better than this book's last week does.
/// Kept out of `reading_pace.dart` so the arithmetic stays free of Riverpod.
final readingPaceProvider = StreamProvider<ReadingPace>(
  (ref) => ref.watch(appDatabaseProvider).watchReadingPace(),
);

/// The pace as a plain value, unknown until the first query settles.
///
/// The screens that read this are drawing an aside, not a body: a spinner or a
/// gap where an estimate will appear is worse than the estimate simply arriving
/// a frame later.
final currentPaceProvider = Provider<ReadingPace>(
  (ref) => ref.watch(readingPaceProvider).value ?? ReadingPace.unknown,
);
