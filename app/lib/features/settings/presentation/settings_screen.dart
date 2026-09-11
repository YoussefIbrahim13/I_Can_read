import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/branding/app_mark.dart';
import '../../../core/config/app_version.dart';
import '../../../core/config/legal_links.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../l10n/app_localizations.dart';

/// Sentinel for "follow the system language". Using an explicit value rather
/// than `null` keeps the control from reading the choice as "nothing selected".
const _systemLanguage = 'system';

/// Screen 11 — the few things about the app the reader gets to decide.
///
/// Redesign v2 sorted it into two kinds of thing. At the top are the choices
/// that change what is in front of you right now — language, day or night, how
/// cream the paper is — each one a control you can see the result of without
/// leaving. Below them are the doors: account, backup, privacy, one line of
/// what each is about. What used to be here inline, a sync status and two
/// backup buttons and a way to delete your account, are all behind those doors
/// now, because none of them is a setting.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(title: l10n.navSettings),
            Expanded(
              // No horizontal padding: the rows below run edge to edge, and
              // each block of controls insets itself instead.
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.x6),
                children: [
                  _Block(
                    children: [
                      const SizedBox(height: AppSpacing.x4),
                      Kicker(l10n.settingsLanguage),
                      const SizedBox(height: 11),
                      AppSegmentedControl<String>(
                        value: settings.locale?.languageCode ?? _systemLanguage,
                        onChanged: (value) => notifier.setLocale(
                          value == _systemLanguage ? null : Locale(value),
                        ),
                        segments: [
                          AppSegment(
                            value: 'ar',
                            label: l10n.settingsLanguageArabic,
                            // Each language names itself in its own script, so
                            // the segment has to opt out of the locale's stack.
                            textStyle: const TextStyle(
                              fontFamily: AppFonts.arabic,
                            ),
                          ),
                          AppSegment(
                            value: 'en',
                            label: l10n.settingsLanguageEnglish,
                            textStyle: const TextStyle(
                              fontFamily: AppFonts.serif,
                            ),
                          ),
                          AppSegment(
                            value: _systemLanguage,
                            label: l10n.settingsLanguageSystem,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x4 + 2),
                      Kicker(l10n.settingsTheme),
                      const SizedBox(height: 11),
                      AppSegmentedControl<ThemeMode>(
                        value: settings.themeMode,
                        onChanged: notifier.setThemeMode,
                        segments: [
                          AppSegment(
                            value: ThemeMode.light,
                            label: l10n.settingsThemeLight,
                          ),
                          AppSegment(
                            value: ThemeMode.dark,
                            label: l10n.settingsThemeDark,
                          ),
                          AppSegment(
                            value: ThemeMode.system,
                            label: l10n.settingsThemeSystem,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x4 + 2),
                      _WarmthSlider(
                        warmth: settings.paperWarmth,
                        onChanged: notifier.setPaperWarmth,
                      ),
                      const SizedBox(height: AppSpacing.x6 - 4),
                    ],
                  ),
                  const Divider(),
                  const _AccountRow(),
                  const Divider(),
                  _NavRow(
                    title: l10n.settingsBackup,
                    subtitle: l10n.settingsBackupSubtitle,
                    onTap: () => context.push('/settings/backup'),
                  ),
                  const Divider(),
                  const _PrivacyPolicyRow(),
                  const Divider(),
                  const SizedBox(height: AppSpacing.x8),
                  const _Colophon(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Insets a group of controls to the text gutter, inside a full-bleed list.
class _Block extends StatelessWidget {
  const _Block({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// How cream the paper is, across the whole app.
///
/// The value is a word, never a number: the reader is choosing a feel, and
/// "62" is not one. The label sits opposite the kicker so the current setting
/// is readable without moving the thumb to find out.
class _WarmthSlider extends StatelessWidget {
  const _WarmthSlider({required this.warmth, required this.onChanged});

  final int warmth;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final word = switch (PaperWarmth.bandOf(warmth)) {
      PaperWarmthBand.cool => l10n.settingsWarmthCool,
      PaperWarmthBand.light => l10n.settingsWarmthLight,
      PaperWarmthBand.medium => l10n.settingsWarmthMedium,
      PaperWarmthBand.warm => l10n.settingsWarmthWarm,
      PaperWarmthBand.warmest => l10n.settingsWarmthWarmest,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Kicker(l10n.settingsWarmth)),
            Text(
              word,
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x1),
        Slider(
          value: PaperWarmth.clamped(warmth).toDouble(),
          min: PaperWarmth.min.toDouble(),
          max: PaperWarmth.max.toDouble(),
          divisions: (PaperWarmth.max - PaperWarmth.min) ~/ PaperWarmth.step,
          label: word,
          onChanged: (value) => onChanged(value.round()),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          l10n.settingsWarmthHint,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            height: 1.6,
            color: theme.appColors.muted,
          ),
        ),
      ],
    );
  }
}

/// The account, in one line: the address if there is one, and the plain fact
/// if there is not.
class _AccountRow extends ConsumerWidget {
  const _AccountRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(authStateProvider);

    return _NavRow(
      title: l10n.settingsAccount,
      subtitle: session?.email ?? l10n.settingsSignedOut,
      onTap: () => context.push('/account'),
    );
  }
}

/// The way to the published privacy policy.
///
/// Absent entirely in a build that was not given a URL.
class _PrivacyPolicyRow extends ConsumerWidget {
  const _PrivacyPolicyRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(privacyPolicyUrlProvider);
    if (url == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    return _NavRow(
      title: l10n.settingsPrivacyPolicy,
      subtitle: l10n.settingsPrivacyPolicyHint,
      // External on purpose: an in-app browser would put our chrome around a
      // document whose whole point is that the reader can check it for
      // themselves, and share it with anyone.
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}

/// A door: what is behind it, one line about it, and a chevron.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.x4 - 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: theme.appColors.muted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            // `chevron_right` carries `matchTextDirection`, so it points the
            // way the reader is going without a manual flip.
            Icon(Icons.chevron_right, size: 18, color: theme.appColors.muted),
          ],
        ),
      ),
    );
  }
}

/// The mark, both names, and the one fact worth repeating at the foot of the
/// app: the files never leave the phone.
class _Colophon extends StatelessWidget {
  const _Colophon();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        const AppMark(size: 34),
        const SizedBox(height: AppSpacing.x2 + 2),
        Text(
          // Both names, always, in either language: the app is called one
          // thing, and it is called it in two scripts.
          'Yaqra · يقرأ',
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
        ),
        const SizedBox(height: 3),
        Text(
          l10n.settingsFooterLine(appVersion),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            color: theme.appColors.muted,
          ),
        ),
      ],
    );
  }
}
