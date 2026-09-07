import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

@immutable
class AppNavigationItem {
  const AppNavigationItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The bottom bar, hand-rolled.
///
/// Material's [NavigationBar] only knows the pill indicator; here the selected
/// item is marked by an 18×1 gold rule under its label. Restyling the pill
/// away leaves an empty 32px-tall indicator slot that still eats the layout,
/// so the bar is written out — it is four items and one hairline.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<AppNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(color: colors.hairline),
        SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                for (final (index, item) in items.indexed)
                  Expanded(
                    child: _NavItem(
                      item: item,
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
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppNavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final tint = selected ? theme.colorScheme.primary : colors.muted;

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        // Squares off the ripple; a stadium here is the "Material default"
        // shape the rest of the app avoids.
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 19, color: tint),
            const SizedBox(height: AppSpacing.x1),
            Text(
              item.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10.5,
                letterSpacing: 0,
                color: tint,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            // Reserved whether or not it is drawn, so selecting a tab does not
            // shift the other three labels up.
            SizedBox(
              height: 1,
              width: 18,
              child: selected
                  ? ColoredBox(color: colors.accentStroke)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
