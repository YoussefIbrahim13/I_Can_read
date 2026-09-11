import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/core/theme/app_tokens.dart';
import 'package:i_can_read/core/widgets/app_navigation_bar.dart';
import 'package:i_can_read/core/widgets/progress_shapes.dart';

/// The painted height of every [ColoredBox] filled with [colour].
///
/// A childless `ColoredBox` under loose constraints lays out to
/// `constraints.smallest` — zero — and paints nothing while still being found
/// by `find.byType`. Measuring the box is the only way to tell a drawn mark
/// from one that is merely in the tree.
List<double> heightsOf(WidgetTester tester, Color colour) {
  return tester
      .widgetList<ColoredBox>(find.byType(ColoredBox))
      .where((box) => box.color == colour)
      .map((box) => tester.getSize(find.byWidget(box)).height)
      .toList();
}

void main() {
  final theme = AppTheme.of(
    brightness: Brightness.light,
    locale: const Locale('ar'),
  );

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: const SizedBox.shrink(), bottomNavigationBar: child),
        ),
      ),
    );
  }

  testWidgets('the navigation bar draws a brass band over the active tab', (
    tester,
  ) async {
    await pump(
      tester,
      AppNavigationBar(
        labels: const ['اليوم', 'مكتبتي', 'إحصائياتي', 'الإعدادات'],
        selectedIndex: 1,
        onSelected: (_) {},
      ),
    );

    final brass = heightsOf(tester, theme.appColors.accentStroke);
    expect(brass, hasLength(1), reason: 'exactly one tab is marked');
    expect(
      brass.single,
      greaterThan(0),
      reason: 'the band must have height, not merely exist in the tree',
    );

    // And the rule it sits on still runs the full width underneath it.
    final hairline = heightsOf(tester, theme.appColors.hairline);
    expect(hairline.where((h) => h > 0), isNotEmpty);
  });

  testWidgets('the day bar draws a segment per session', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: TodayBar(
                segments: [
                  TodaySegment(pages: 10, done: true),
                  TodaySegment(pages: 5, done: false),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final drawn = [
      ...heightsOf(tester, theme.appColors.done),
      ...heightsOf(tester, theme.appColors.hairline),
    ];
    expect(drawn, hasLength(2));
    for (final height in drawn) {
      expect(height, greaterThan(0), reason: 'a zero-height segment is invisible');
    }
  });

  testWidgets('the session rule draws both its track and its fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: SessionRule(fraction: 0.5),
            ),
          ),
        ),
      ),
    );

    expect(heightsOf(tester, theme.appColors.hairline).single, greaterThan(0));
    expect(
      heightsOf(tester, theme.appColors.accentStroke).single,
      greaterThan(0),
      reason: 'the fill is the progress; a zero-height fill shows none of it',
    );
  });

  testWidgets('the book rule draws both its track and its fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: BookRule(fraction: 0.5),
            ),
          ),
        ),
      ),
    );

    expect(heightsOf(tester, theme.appColors.hairline).single, greaterThan(0));
    expect(
      heightsOf(tester, theme.colorScheme.onSurface).single,
      greaterThan(0),
    );
  });
}
