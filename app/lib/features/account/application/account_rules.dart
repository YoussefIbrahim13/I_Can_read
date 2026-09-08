/// The two rules both account flows are held to, in one place so signing in and
/// resetting a password cannot drift apart on what counts as valid.
library;

/// The shortest password the server will take.
///
/// Checked here too, so the reader finds out before a round trip rather than
/// after one.
const minPasswordLength = 8;

/// The length of the code the server emails.
const passwordResetCodeLength = 6;

/// Enough of a check to catch a typo, and no more.
///
/// Deliberately not an RFC-shaped pattern: those reject addresses that work,
/// and the only thing that really settles it is the server accepting it.
bool looksLikeEmail(String value) {
  final at = value.indexOf('@');
  return at > 0 &&
      at == value.lastIndexOf('@') &&
      value.indexOf('.', at) > at + 1 &&
      !value.endsWith('.') &&
      !value.contains(' ');
}
