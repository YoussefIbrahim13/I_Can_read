/// The version the app shows the reader, at the foot of Settings.
///
/// Hand-kept rather than read from the bundle: reading it back needs a plugin
/// round-trip and a package whose only job in this app would be to restate one
/// line of `pubspec.yaml`. **Keep it in step with `pubspec.yaml`'s `version:`**
/// — the marketing part only, without the build number, which is a fact about
/// the store rather than about the app.
const appVersion = '1.0';
