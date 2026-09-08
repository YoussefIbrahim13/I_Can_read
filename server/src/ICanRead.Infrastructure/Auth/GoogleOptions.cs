namespace ICanRead.Infrastructure.Auth;

/// <summary>
/// What the server needs to check a Google ID token.
/// </summary>
/// <remarks>
/// There is no client secret here, and there should not be. The secret belongs
/// to the authorization-code flow, where a server trades a code for tokens.
/// This app does not do that: the device gets an ID token and the server
/// verifies its signature against Google's public keys. Storing a secret we
/// never use would only be somewhere for one to leak from.
/// </remarks>
public class GoogleOptions
{
    public const string Section = "Google";

    /// <summary>
    /// The **Web** client ID, not the Android one.
    /// </summary>
    /// <remarks>
    /// This is the audience the device asks Google to mint the token for, and
    /// therefore the only value that proves the token was meant for us rather
    /// than replayed from some other app the reader signed into. The Android
    /// client ID never appears in code — Google matches that one by package
    /// name and signing certificate.
    ///
    /// Not a secret: it ships inside the APK. It is configuration because it
    /// changes between Google Cloud projects, not because it is sensitive.
    /// </remarks>
    public string ClientId { get; set; } = "";

    /// <summary>Whether Google sign-in is configured at all.</summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(ClientId);

    /// <summary>
    /// How far this server's clock is allowed to disagree with Google's, in
    /// minutes. Zero — the default, and the only correct value in deployment.
    /// </summary>
    /// <remarks>
    /// This exists for exactly one situation: a development machine whose clock
    /// is wrong. Google mints an ID token that is valid for an hour, and a
    /// server running an hour fast rejects every one of them as expired the
    /// moment it arrives — a sign-in that fails with nothing wrong on either
    /// side of it.
    ///
    /// It is not a fix, and it is a real hole while it is set: an ID token
    /// stays usable for this long past the expiry Google gave it. Startup
    /// refuses to run with a non-zero value outside Development, so this cannot
    /// reach a deployed server by being left in a config file.
    ///
    /// The actual fix is the machine's clock. See the note in
    /// appsettings.Development.json for why one was needed here.
    /// </remarks>
    public int ClockToleranceMinutes { get; set; }
}
