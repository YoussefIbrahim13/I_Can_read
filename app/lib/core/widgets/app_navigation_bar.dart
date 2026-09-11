import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The bottom bar, hand-rolled.
///
/// Redesign v2 took the icons out. Four words in the app's own type say what
/// four generic glyphs were only approximating — there is no icon that means
/// "وردي اليوم" — and dropping them lets the bar sit low and quiet instead of
/// competing with the page above it.
///
/// Selection is a 2px brass band laid **on the bar's own top rule**, over the
/// active item's segment: the tab is a tab in a printed index, marked at its
/// edge. Material's [NavigationBar] only knows the pill indicator, and
/// restyling the pill away leaves an empty 32px indicator slot that still eats
/// the layout, so the bar is written out — it is four labels and one rule.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// The brass band's thickness. Twice the hairline it covers, so the mark
  /// reads at a glance without becoming a bar in its own right.
  static const _band = 2.0;

  static const _height = 58.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _band,
          child: Stack(
            children: [
              // The rule runs the full width unbroken; the band covers its own
              // segment of it rather than replacing it, so the bar still has a
              // continuous top edge when a tab is selected.
              PositionedDirectional(
                start: 0,
                end: 0,
                top: 0,
                height: 1,
                child: ColoredBox(color: colors.hairline),
              ),
              Positioned.fill(
                child: Row(
                  // Stretch, not the default centre: a centred child is given
                  // a loose height, and a `ColoredBox` with no child collapses
                  // to zero under one — the band would be in the tree and
                  // never on the screen.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < labels.length; index++)
                      Expanded(
                        child: index == selectedIndex
                            ? ColoredBox(color: colors.accentStroke)
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: SizedBox(
            height: _height,
            child: Row(
              children: [
                for (final (index, label) in labels.indexed)
                  Expanded(
                    child: _NavItem(
                      label: label,
                      selected: index == selectedIndex,
                      onTap: () => onSelected(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        // Squares off the ripple; a stadium here is the "Material default"
        // shape the rest of the app avoids.
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              letterSpacing: 0,
              // The active tab goes to full ink and gains weight. It does not
              // go gold: the band above it is already the brass, and a gold
              // label under a gold band says the same thing twice.
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.appColors.muted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
