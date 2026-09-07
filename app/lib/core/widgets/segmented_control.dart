import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The language / theme / plan-mode switch.
///
/// Material's [SegmentedButton] fills the selected segment and adds a
/// checkmark. Here the selection is a 1px inset accent ring and a colour
/// change — no fill, no icon — so this is a Row of [InkWell]s rather than a
/// restyled `SegmentedButton`.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    required this.segments,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Row(
        children: [
          for (final (index, segment) in segments.indexed)
            Expanded(
              child: _Segment(
                segment: segment,
                selected: segment.value == value,
                // Only the interior gets a divider; the outer box already has
                // one on each end.
                showLeadingDivider: index > 0,
                onTap: () => onChanged(segment.value),
              ),
            ),
        ],
      ),
    );
  }
}

@immutable
class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.textStyle});

  final T value;
  final String label;

  /// Overrides the family for a segment whose label is in the *other* script —
  /// the English/العربية language picker being the case that forces this.
  final TextStyle? textStyle;
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.showLeadingDivider,
    required this.onTap,
  });

  final AppSegment<T> segment;
  final bool selected;
  final bool showLeadingDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    final base = segment.textStyle ?? theme.textTheme.labelMedium;
    final style = base?.copyWith(
      fontSize: 13,
      color: selected
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
    );

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              // Drawn as an inset ring rather than an outline so it lands
              // inside the container's own border instead of doubling it.
              top: _ring(selected, colors),
              bottom: _ring(selected, colors),
              left: _ring(selected, colors),
              right: _ring(selected, colors),
            ),
          ),
          child: Stack(
            children: [
              if (showLeadingDivider && !selected)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: 1,
                    child: ColoredBox(color: colors.hairline),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                    segment.label,
                    style: style,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Always 1px wide, transparent when unselected. [BorderSide.none] is
  /// zero-width, which would inset the label by a pixel on selection and make
  /// the row twitch as the choice moves.
  static BorderSide _ring(bool selected, AppColors colors) =>
      BorderSide(color: selected ? colors.accentStroke : Colors.transparent);
}
