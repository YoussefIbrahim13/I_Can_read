import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the published privacy policy lives.
///
/// Supplied at build time, like the API address:
///
/// ```
/// flutter build appbundle \
///   --dart-define=PRIVACY_POLICY_URL=https://example.github.io/repo/privacy-policy.html
/// ```
///
/// Empty until the page is actually published, and the settings row disappears
/// with it — the same rule the Google button follows. A link that goes nowhere
/// is worse than no link: it reads as the promise being missing rather than the
/// page.
///
/// The source of the page is `docs/privacy-policy.html` in this repository.
/// Play requires the URL in the store listing as well; this is the copy the
/// reader can reach without leaving the app, which is where anybody actually
/// looks for it.
abstract final class LegalLinks {
  static const privacyPolicy = String.fromEnvironment('PRIVACY_POLICY_URL');
}

/// The privacy policy URL, or null when this build has none.
///
/// A provider rather than a bare constant so the settings test can drive both
/// states; a `String.fromEnvironment` cannot be changed from a test.
final privacyPolicyUrlProvider = Provider<String?>((ref) {
  final url = LegalLinks.privacyPolicy.trim();
  return url.isEmpty ? null : url;
});
