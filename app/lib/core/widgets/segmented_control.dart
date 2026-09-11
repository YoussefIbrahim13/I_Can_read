import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The language / theme / plan-mode switch.
///
/// Redesign v2 reversed how selection is drawn here. It used to be a 1px inset
/// accent ring; it is now the **ink slab** — the selected segment fills with
/// walnut and sets its label in cream, the same treatment as the primary
/// button. That is deliberate: on Settings and on Plan this control *is* the
/// decision the screen is about, and a ring was too quiet to carry it.
///
/// The slab runs to the outer edge and takes the container's corner radius on
/// whichever end it sits, so the control reads as one printed strip with a
/// block inked onto it rather than as a button inside a box.
///
/// Material's [SegmentedButton] fills the selected segment too, but adds a
/// checkmark and its own shape rules, so this stays a Row of [InkWell]s.
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
    final selectedIndex = segments.indexWhere((s) => s.value == value);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      // Clips the slab's square inner corners against the container's rounded
      // outer ones; without it the fill overruns the border on the end
      // segments.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Row(
          children: [
            for (final (index, segment) in segments.indexed)
              Expanded(
                child: _Segment(
                  segment: segment,
                  selected: index == selectedIndex,
                  // A hairline separates two *unselected* neighbours only. The
                  // slab's own edge already divides it from what it sits next
                  // to, and a rule against the fill reads as a seam.
                  showLeadingDivider:
                      index > 0 &&
                      index != selectedIndex &&
                      index - 1 != selectedIndex,
                  onTap: () => onChanged(segment.value),
                ),
              ),
          ],
        ),
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
      fontSize: 13.5,
      color: selected
          ? theme.colorScheme.onInverseSurface
          : theme.colorScheme.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.inverseSurface : null,
            border: showLeadingDivider
                ? BorderDirectional(start: BorderSide(color: colors.hairline))
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
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
        ),
      ),
    );
  }
}
