import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'figure.dart';

/// The `−  9  ＋` control: a hairline box split into three cells, the middle one
/// a standing figure.
///
/// Used for the plan's start page and, later, for a session's page share. It is
/// deliberately not a text field — every value it holds is a small integer the
/// reader nudges, and a keyboard for that is a worse answer.
///
/// The visible box is 38 high, per the design, but the whole control lays out
/// at [AppSpacing.minTapTarget] and the two buttons fill that height. So the
/// touch targets clear 44 even though the drawing does not.
class StepperField extends StatelessWidget {
  const StepperField({
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max,
    this.decreaseLabel,
    this.increaseLabel,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;

  /// Null means unbounded above.
  final int? max;

  /// Screen-reader names for the two buttons. The glyphs are decorative.
  final String? decreaseLabel;
  final String? increaseLabel;

  static const _buttonWidth = 38.0;
  static const _valueWidth = 46.0;
  static const _boxHeight = 38.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    final canDecrease = value > min;
    final canIncrease = max == null || value < max!;

    return SizedBox(
      height: AppSpacing.minTapTarget,
      width: _buttonWidth * 2 + _valueWidth,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The drawing: one box, two interior rules. Kept behind the buttons
          // so the taps are not limited to the 38px the reader can see.
          Center(
            child: Container(
              height: _boxHeight,
              decoration: BoxDecoration(
                border: Border.all(color: colors.hairline),
                borderRadius: BorderRadius.circular(AppSpacing.radius),
              ),
              child: Row(
                children: [
                  const SizedBox(width: _buttonWidth - 1),
                  _Rule(color: colors.hairline),
                  SizedBox(
                    width: _valueWidth,
                    child: Center(
                      child: Figure.number(
                        value,
                        size: 17,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _Rule(color: colors.hairline),
                ],
              ),
            ),
          ),
          Row(
            children: [
              _StepButton(
                glyph: '−',
                label: decreaseLabel,
                onPressed: canDecrease ? () => onChanged(value - 1) : null,
              ),
              const SizedBox(width: _valueWidth),
              _StepButton(
                glyph: '＋',
                label: increaseLabel,
                onPressed: canIncrease ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 1, child: ColoredBox(color: color));
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.glyph,
    required this.label,
    required this.onPressed,
  });

  final String glyph;
  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: SizedBox(
          width: StepperField._buttonWidth,
          height: AppSpacing.minTapTarget,
          child: Center(
            // The glyph is decorative — the button's own label is what a
            // screen reader should read, not "plus sign".
            child: ExcludeSemantics(
              child: Text(
                glyph,
                style: TextStyle(
                  fontSize: 16,
                  height: 1,
                  // Disabled reads as the muted ink rather than as a gap, so
                  // the control keeps its shape at the ends of its range.
                  color: onPressed == null
                      ? theme.appColors.muted
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
