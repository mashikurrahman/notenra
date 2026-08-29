/// Last-resort PHI filter for an audit `details` string.
///
/// Call sites are written not to include PHI, but audit rows are retained for
/// years and are shipped to the server, so a leak introduced later would be both
/// durable and remote. This catches the two identifiers the app actually
/// handles: an MRN in any of its written forms, and the name of any patient
/// currently loaded.
///
/// It is a backstop, not a licence. The clinician's own name and email stay —
/// an audit trail's whole purpose is recording who acted.
///
/// Lives outside `AppState` so it is a pure function of its inputs and can be
/// tested directly, without the Keystore/SQLCipher stack `AppState` pulls in.
class AuditScrub {
  /// Audit `details` is a human-readable note, not a payload. Anything longer
  /// than this is a bug at the call site; truncate rather than store it.
  static const maxLength = 500;

  /// Matches `MRN-339281`, `MRN 339281`, `MRN:339281`, `mrn339281`.
  static final _mrn =
      RegExp(r'\bMRN[-\s:]?[A-Za-z0-9][A-Za-z0-9-]*', caseSensitive: false);

  /// Redact [details] against the currently-known [patientNames].
  ///
  /// Longest name first, so "Sophia Martinez" is redacted as one unit rather
  /// than leaving "[patient] Martinez" behind if "Sophia" is also a name on its
  /// own.
  static String details(String details, Iterable<String> patientNames) {
    if (details.isEmpty) return details;
    var out = details.replaceAll(_mrn, '[mrn]');

    final names = patientNames
        .map((n) => n.trim())
        // Two characters or fewer would match far too much ("Al", initials).
        .where((n) => n.length >= 3)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final name in names) {
      if (out.contains(name)) out = out.replaceAll(name, '[patient]');
    }
    return out.length <= maxLength
        ? out
        : '${out.substring(0, maxLength - 3)}...';
  }
}
