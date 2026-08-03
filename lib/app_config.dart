/// Compile-time application configuration.
///
/// Production builds MUST disable the seeded demo accounts:
///   flutter build apk --release --dart-define=DEMO_ACCOUNTS=false
///   flutter build ipa --release --dart-define=DEMO_ACCOUNTS=false
class AppConfig {
  /// When true, the local DB is seeded with demo clinician/admin logins so the
  /// app is testable without a live backend. Defaults to true for development;
  /// pass `--dart-define=DEMO_ACCOUNTS=false` to ship a production build with
  /// no built-in credentials.
  static const bool seedDemoAccounts =
      bool.fromEnvironment('DEMO_ACCOUNTS', defaultValue: true);

  /// Convenience for UI hints ("Demo build" banners, etc.).
  static const bool isDemoBuild = seedDemoAccounts;
}
