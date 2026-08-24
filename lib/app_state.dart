import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'secure_store.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/clinical_models.dart' show VisitStatus;
import 'api/patients_api.dart';
import 'api/token_store.dart';
import 'audio_vault.dart';
import 'database.dart';
import 'models.dart';
import 'recording_foreground.dart';
import 'security.dart';
import 'services/clinical_service.dart';
import 'services/notification_service.dart';

/// A gate the server requires a clinician to clear on first login (an account
/// the admin created) before a full session is granted.
enum AuthGate { none, passwordChange, phiTraining, mfaEnrollment, mfaChallenge }

/// The [AuthGate] a login/gate response maps to, or null when it's not a gate
/// (success / failure). Gate precedence matches the server: password → PHI → MFA.
AuthGate? gateForOutcome(LoginOutcome o) => switch (o) {
      LoginOutcome.forcePasswordChange => AuthGate.passwordChange,
      LoginOutcome.phiTraining => AuthGate.phiTraining,
      LoginOutcome.mfaEnrollment => AuthGate.mfaEnrollment,
      LoginOutcome.mfaChallenge => AuthGate.mfaChallenge,
      _ => null,
    };

/// Central app state — the Flutter analog of the original `ScribeViewModel`.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final _db = AppDatabase.instance;
  final _localAuth = LocalAuthentication();

  /// HIPAA automatic-logoff: re-lock the PHI vault after this much inactivity.
  static const inactivityTimeout = Duration(minutes: 5);

  /// Brute-force protection.
  static const _maxFailedAttempts = 5;
  static const _lockoutDuration = Duration(seconds: 30);

  /// In live mode, [_clinical] tells us the active backend and the API helpers
  /// drive auth + patient roster against the real server. In demo mode they are
  /// unused and everything stays on the local encrypted vault.
  final ClinicalService? _clinical;
  AuthApi? _authApi;
  PatientsApi? _patientsApi;

  // ignore: prefer_initializing_formals — the field is private but the param is public.
  AppState({ClinicalService? clinical, TokenStore? tokens}) : _clinical = clinical {
    if (tokens != null) {
      final client = ApiClient(tokens);
      client.onUnauthorized = _onSessionExpired;
      _authApi = AuthApi(client, tokens);
      _patientsApi = PatientsApi(client);
    }
    // The server may accept a recording long after submitRecording() returned
    // (the outbox drains in the background, or after a reconnect). Mark the
    // local row uploaded whenever that happens, so the recovery scan below
    // never re-sends a file the server already has.
    clinical?.onAudioUploaded = (path) => markRecordingUploaded(path);
    WidgetsBinding.instance.addObserver(this);
    _loadConfig();
  }

  /// When the app returns to the foreground during a recording, immediately
  /// resync the on-screen elapsed time to the wall clock so the doctor sees the
  /// correct duration the instant they pick the phone back up (the per-second
  /// timer may have been paused while the phone slept).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRecording && !_isPaused) {
      _recordingSeconds = _elapsedRecordingMs() ~/ 1000;
      notifyListeners();
    }
  }

  /// Whether the live server backend is active (vs. local demo data).
  bool get _live => _clinical?.isLive ?? false;

  // Guards re-entry while we re-validate the session (its own /auth/me 401 would
  // otherwise call back into here).
  bool _validatingSession = false;

  /// The server rejected a request with 401. Return to the login gate ONLY if
  /// the session is genuinely gone — a single stray 401 (a cookie race right
  /// after a long sleep, a hiccup on a large multipart upload) must not sign the
  /// doctor out mid-visit and make a just-saved recording look lost.
  Future<void> _onSessionExpired() async {
    if (_currentUser == null || _validatingSession) return;
    // Never tear the session down while a capture is live: the recording (and
    // the audio already on disk) must survive. Uploads only run after stop, so
    // an in-progress recording should never trip this — but guard anyway.
    if (_isRecording) return;
    // Confirm the session is really dead before tearing it down. If /auth/me
    // still succeeds, the 401 was spurious — keep the doctor signed in; the
    // failed upload is retried by the outbox / on the next recovery pass.
    _validatingSession = true;
    try {
      final me = await _authApi?.me();
      if (me != null) return; // session still valid — ignore the stray 401
    } catch (_) {
      // /auth/me failed too → the session is genuinely gone; fall through.
    } finally {
      _validatingSession = false;
    }
    // Session confirmed expired (e.g. a long visit outlived the backend's idle
    // timeout while the phone slept). Re-authentication is required, but the
    // just-saved recording is safe in the local DB and is re-sent automatically
    // after the next sign-in (see [_reuploadPendingRecordings]). Say so plainly
    // so a recording that drops off the screen never looks like lost data.
    logout();
    _authError =
        'Your session timed out, so you were signed out. Please sign in again — '
        'any saved recording is kept and finishes uploading automatically.';
    notifyListeners();
  }

  Future<void> _loadConfig() async {
    _onboardingComplete =
        (await _markerStore.read(key: _onboardingKey)) == '1';
    notifyListeners();
  }

  User? _currentUser;
  User? get currentUser => _currentUser;
  bool get isAdmin => _currentUser?.role == 'admin';

  // First-login app tour. Default true so an established user never sees a flash
  // before [_loadConfig] resolves; a first-timer is flipped to false on load.
  bool _onboardingComplete = true;
  static const _onboardingKey = 'onboarding_complete';
  bool get needsOnboarding => !_onboardingComplete;

  /// Mark the first-login tour as seen (persisted so it won't show again).
  Future<void> completeOnboarding() async {
    _onboardingComplete = true;
    await _markerStore.write(key: _onboardingKey, value: '1');
    notifyListeners();
  }

  // The backend address is not configurable here: it is fixed at build time in
  // [ApiConfig] (`--dart-define=API_BASE_URL=…`). A previous `serverUrl` setting
  // lived on this class with its own getter, setter and audit write, but was
  // never passed to the HTTP layer — so changing it moved no traffic. Removed
  // rather than wired up, since a clinician-editable server address would let
  // PHI uploads be redirected.

  /// Manually re-lock the PHI vault (Settings ▸ Lock now).
  void lockVaultNow() {
    _audit('MANUAL_LOCK', details: 'Vault manually locked');
    _biometricUnlocked = false;
    _inactivityTimer?.cancel();
    notifyListeners();
  }

  bool _biometricUnlocked = false;
  bool get biometricUnlocked => _biometricUnlocked;

  // Guards against the biometric prompt being triggered twice (e.g. the lock
  // screen rebuilding while a prompt is already on screen).
  bool _authInProgress = false;

  // True when the user was restored from a saved token (no password entered),
  // so the vault's password fallback must re-auth live instead of checking a
  // local hash we don't have.
  bool _restoredSession = false;

  // Vault-unlock UI state.
  String? _vaultError;
  String? get vaultError => _vaultError;
  bool _biometricAvailable = true;
  bool get biometricAvailable => _biometricAvailable;

  Timer? _inactivityTimer;
  final Map<String, int> _failedAttempts = {};
  final Map<String, DateTime> _lockedUntil = {};

  // --- Recording state ---
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  Timer? _durationTimer;
  StreamSubscription<Amplitude>? _ampSub;

  // Crash-recovery marker for an in-progress recording.
  static const _markerStore = SecureStore();
  static const _activeRecKey = 'active_recording';

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  // Normalized 0..1 microphone level for the live meter.
  double _recordingLevel = 0;
  double get recordingLevel => _recordingLevel;

  int? _recordingPatientId;
  int? get recordingPatientId => _recordingPatientId;

  int _recordingSeconds = 0;
  int get recordingSeconds => _recordingSeconds;

  // Wall-clock anchor for the current recording. Elapsed time is derived from
  // this rather than a running counter, so it stays correct even if the UI
  // isolate was paused while the phone slept (the per-second timer can't be
  // trusted to keep ticking in the background). Paused time is subtracted.
  int? _recordStartMs;
  int _pausedAccumMs = 0;
  int? _pauseStartMs;

  /// True wall-clock elapsed recording time (minus paused spans), in ms.
  int _elapsedRecordingMs() {
    final start = _recordStartMs;
    if (start == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    var paused = _pausedAccumMs;
    if (_isPaused && _pauseStartMs != null) paused += now - _pauseStartMs!;
    return (now - start - paused).clamp(0, 24 * 3600 * 1000);
  }

  String? _playingPath;
  String? get playingPath => _playingPath;
  String? _playingTempPath; // decrypted temp file currently playing

  Patient? _selectedPatient;
  Patient? get selectedPatient => _selectedPatient;

  List<Recording> _recordings = [];
  List<Recording> get recordings => _recordings;

  Recording? _recoveredRecording;
  Recording? get recoveredRecording => _recoveredRecording;
  void clearRecoveredRecording() {
    _recoveredRecording = null;
    notifyListeners();
  }

  String? _authError;
  String? get authError => _authError;

  // --- First-login gates (forced password change, PHI-training ack) ---
  // When a live login succeeds but the server requires a gate to be completed
  // before granting a full session, we hold the gate + its short-lived token
  // here so the login screen can route to the matching in-app screen instead
  // of dead-ending. Mirrors the web app's first-login experience.
  AuthGate _authGate = AuthGate.none;
  String? _gateToken;
  String? _gateEmail;
  AuthGate get authGate => _authGate;
  String? get gateEmail => _gateEmail;

  /// Abandon an in-progress first-login gate (user backed out). Clears the
  /// short-lived token so nothing lingers.
  void clearAuthGate() {
    _authGate = AuthGate.none;
    _gateToken = null;
    _gateEmail = null;
    _authError = null;
    notifyListeners();
  }

  String? _adminMessage;
  String? get adminMessage => _adminMessage;
  void clearAdminMessage() {
    _adminMessage = null;
  }

  List<Patient> _patients = [];
  List<Patient> get patients => _patients;

  // Maps a just-added patient -> the visit created for them, so the first
  // recording attaches to that visit instead of spawning a duplicate.
  final Map<int, String> _openVisitByPatient = {};
  String? openVisitFor(int patientId) => _openVisitByPatient[patientId];

  /// Id of the most recently added patient, so the "Save & record" shortcut can
  /// jump straight into capturing their visit.
  int? _lastAddedPatientId;
  int? get lastAddedPatientId => _lastAddedPatientId;

  /// Proactively ensure microphone permission (idempotent — the OS only prompts
  /// the first time). Pre-warming this means the first tap on Record starts
  /// capture in a single tap instead of the permission dialog racing auto-start.
  Future<bool> ensureMicPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  List<User> _users = [];
  List<User> get users => _users;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  set searchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  List<Patient> get visiblePatients {
    var list = _patients;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.mrn.toLowerCase().contains(q) ||
              p.medicalHistory.toLowerCase().contains(q))
          .toList();
    }
    int rank(String pr) => pr == 'High' ? 0 : (pr == 'Medium' ? 1 : 2);
    final sorted = [...list]..sort((a, b) {
        final r = rank(a.priority).compareTo(rank(b.priority));
        return r != 0 ? r : b.lastContactDate.compareTo(a.lastContactDate);
      });
    return sorted;
  }

  // --- Auth ---
  Future<bool> login(String username, String password) async {
    _authError = null;
    final key = username.trim().toLowerCase();

    // Brute-force lockout check.
    final until = _lockedUntil[key];
    if (until != null && DateTime.now().isBefore(until)) {
      final secs = until.difference(DateTime.now()).inSeconds + 1;
      _authError = 'Too many failed attempts. Try again in ${secs}s.';
      notifyListeners();
      return false;
    }

    // Live mode authenticates against the real API (/auth/login -> JWT).
    if (_live) return _loginLive(username.trim(), password, key);

    final user = await _db.getUserByUsername(username.trim());
    final ok = user != null && Security.verifyPassword(password, user.passwordHash);
    if (ok) {
      _failedAttempts.remove(key);
      _lockedUntil.remove(key);
      _currentUser = user;
      _biometricUnlocked = false;
      await _refreshPatients();
      await _refreshUsers();
      await _recoverInterruptedRecording();
      await purgeOldRecordings();
      await _audit('LOGIN_SUCCESS', details: 'Clinician ${user.username} authenticated');
      notifyListeners();
      return true;
    }

    return _failLogin(key, username);
  }

  /// Authenticate against the live API. On success builds an in-memory [User]
  /// (the JWT lives in the secure TokenStore; the password is kept only as a
  /// hash so the PHI-vault password fallback still works). On failure/gates it
  /// funnels through the same lockout accounting as local login.
  Future<bool> _loginLive(String email, String password, String key) async {
    if (_authApi == null) {
      _authError = 'Live mode is not configured.';
      notifyListeners();
      return false;
    }
    try {
      final result = await _authApi!.login(email, password);
      if (result.outcome == LoginOutcome.success) {
        final u = result.user ?? const <String, dynamic>{};
        // This app is for CLINICIANS ONLY. Admin / scribe / QPS accounts have
        // valid credentials but must not sign in here — reject and drop the
        // session the login just established.
        if (await _rejectIfNotClinician(u)) return false;
        _failedAttempts.remove(key);
        _lockedUntil.remove(key);
        _currentUser = User(
          id: _asInt(u['id']),
          username: (u['email'] ?? email).toString(),
          passwordHash: Security.hashPassword(password),
          fullName: (u['name'] ?? email).toString(),
          provider: 'live',
          role: (u['role'] ?? 'clinician').toString(),
        );
        _biometricUnlocked = false;
        // The token is now saved, so load the clinician's visits/notes. Without
        // this the patient list keeps the pre-login fetch's "session expired"
        // error until a manual reload (the startup refresh ran before sign-in).
        await _clinical?.refresh();
        await _refreshPatients();
        await _recoverInterruptedRecording();
        await purgeOldRecordings();
        await _audit('LOGIN_SUCCESS',
            details: 'Live login ${_currentUser!.username}');
        // Now that the clinician is engaged, ask for notification permission
        // (recording-uploaded / note-ready alerts). Best-effort, non-blocking.
        NotificationService.instance.requestPermission();
        notifyListeners();
        return true;
      }
      // First-login gates. The credentials were VALID (the server logs these as
      // successful logins), so don't count them against the lockout — instead
      // hold the gate + short-lived token so the UI can complete it in-app.
      final gate = gateForOutcome(result.outcome);
      if (gate != null) {
        if (result.temporaryToken == null || result.temporaryToken!.isEmpty) {
          // No token to complete the gate with — fall back to a clear message.
          return _failLogin(key, email,
              message: result.message ??
                  'Additional setup is required. Please sign in on the web app.');
        }
        _failedAttempts.remove(key);
        _lockedUntil.remove(key);
        _authGate = gate;
        _gateToken = result.temporaryToken;
        _gateEmail = email;
        _authError = null;
        notifyListeners();
        return false; // not signed in yet; the login screen routes to the gate
      }
      return _failLogin(key, email, message: result.message ?? 'Sign in failed.');
    } catch (e) {
      // AuthApi.login no longer throws, so this only fires on an unexpected
      // local error — show its detail rather than a misleading network message.
      _authError = 'Sign-in error: $e';
      notifyListeners();
      return false;
    }
  }

  /// Complete the forced first-login password change with [newPassword], then
  /// continue signing in. Returns true once the user is fully signed in. If the
  /// account must also acknowledge PHI training, this returns false but leaves
  /// [authGate] == phiTraining so the UI advances to that step. On a rejected
  /// password (policy/expiry) it returns false with [authError] set.
  Future<bool> completePasswordChange(String newPassword) async {
    if (!_live || _authApi == null || _gateToken == null || _gateEmail == null) {
      _authError = 'Your session expired. Please sign in again.';
      clearAuthGate();
      return false;
    }
    _authError = null;
    final err = await _authApi!.completeForcedPasswordChange(
        temporaryToken: _gateToken!, newPassword: newPassword);
    if (err != null) {
      _authError = err;
      notifyListeners();
      return false;
    }
    // Password rotated; the forced-change token is now spent. Sign in again with
    // the new password to obtain a real session (or surface the next gate).
    final email = _gateEmail!;
    _authGate = AuthGate.none;
    _gateToken = null;
    await _audit('SELF_PASSWORD_CHANGED',
        clinician: email, details: 'First-login password change for $email');
    return _loginLive(email, newPassword, email.trim().toLowerCase());
  }

  /// Complete the PHI-training acknowledgement gate, finishing first-login.
  /// On success the real session token is persisted and the user is signed in.
  Future<bool> acknowledgeTrainingGate() async {
    if (!_live || _authApi == null || _gateToken == null) {
      _authError = 'Your session expired. Please sign in again.';
      clearAuthGate();
      return false;
    }
    _authError = null;
    final res = await _authApi!.acknowledgePhiTraining(_gateToken!);
    // The PHI ack may sign the user in OR hand back the next gate (MFA).
    if (res.outcome == LoginOutcome.success && res.user != null) {
      return await _signInFromUserMap(res.user!, 'PHI acknowledged');
    }
    final next = gateForOutcome(res.outcome);
    if (next != null && (res.temporaryToken?.isNotEmpty ?? false)) {
      _authGate = next;
      _gateToken = res.temporaryToken;
      _authError = null;
      notifyListeners();
      return false; // PhiTrainingScreen routes to the next gate (MFA)
    }
    _authError = res.message ?? 'Could not record the acknowledgement.';
    notifyListeners();
    return false;
  }

  /// Begin MFA enrollment (first-time TOTP setup). Returns the secret / QR data
  /// for the enrollment screen, or an error message.
  Future<
      ({
        String? secret,
        String? otpauthUrl,
        String? qrCode,
        List<String> recoveryCodes,
        String? error
      })> mfaSetup() async {
    if (!_live || _authApi == null || _gateToken == null) {
      return (
        secret: null,
        otpauthUrl: null,
        qrCode: null,
        recoveryCodes: <String>[],
        error: 'Your session expired. Please sign in again.'
      );
    }
    return _authApi!.mfaSetup(_gateToken!);
  }

  /// Finish MFA enrollment with the current 6-digit [code]; signs the user in.
  Future<bool> completeMfaEnrollment(String code) async {
    if (!_live || _authApi == null || _gateToken == null) {
      _authError = 'Your session expired. Please sign in again.';
      clearAuthGate();
      return false;
    }
    _authError = null;
    final res = await _authApi!
        .mfaEnrollVerify(temporaryToken: _gateToken!, code: code.trim());
    if (res.user == null) {
      _authError = res.error ?? 'Could not verify the code.';
      notifyListeners();
      return false;
    }
    return await _signInFromUserMap(res.user!, 'MFA enrolled');
  }

  /// Complete the per-login MFA challenge with the current 6-digit [code].
  Future<bool> completeMfaChallenge(String code) async {
    if (!_live || _authApi == null || _gateToken == null) {
      _authError = 'Your session expired. Please sign in again.';
      clearAuthGate();
      return false;
    }
    _authError = null;
    final res = await _authApi!
        .mfaChallengeVerify(temporaryToken: _gateToken!, code: code.trim());
    if (res.user == null) {
      _authError = res.error ?? 'Could not verify the code.';
      notifyListeners();
      return false;
    }
    return await _signInFromUserMap(res.user!, 'MFA verified');
  }

  /// Build the in-memory session from a server user map after a gate hands back
  /// a real token (PHI ack / MFA). The JWT is already in the TokenStore; we hold
  /// no password, so the PHI vault re-authenticates against the server.
  Future<bool> _signInFromUserMap(Map<String, dynamic> u, String how) async {
    final email = _gateEmail ?? (u['email']?.toString() ?? '');
    // Clinician-only access control applies to the gate paths too.
    if (await _rejectIfNotClinician(u)) return false;
    _currentUser = User(
      id: _asInt(u['id']),
      username: (u['email'] ?? email).toString(),
      passwordHash: '',
      fullName: (u['name'] ?? email).toString(),
      provider: 'live',
      role: (u['role'] ?? 'clinician').toString(),
    );
    _restoredSession = true;
    _biometricUnlocked = false;
    _authGate = AuthGate.none;
    _gateToken = null;
    _gateEmail = null;
    _failedAttempts.clear();
    await _clinical?.refresh();
    await _refreshPatients();
    await _recoverInterruptedRecording();
    await purgeOldRecordings();
    await _audit('LOGIN_SUCCESS', details: 'Live login ($how) ${_currentUser!.username}');
    NotificationService.instance.requestPermission();
    notifyListeners();
    return true;
  }

  /// Clinician-only access control: an admin / scribe / QPS account has valid
  /// credentials but must NOT be able to sign in to this clinician app. Returns
  /// true (and drops the session the login just established) when the account is
  /// not a clinician. The role comes from the auth response; if it's missing it
  /// is confirmed via GET /auth/me before deciding (fail-closed on ambiguity).
  Future<bool> _rejectIfNotClinician(Map<String, dynamic> u) async {
    var role = (u['role'] ?? '').toString().toLowerCase();
    if (role.isEmpty) {
      try {
        final me = await _authApi?.me();
        final mu = (me?['user'] ?? me);
        if (mu is Map) role = (mu['role'] ?? '').toString().toLowerCase();
      } catch (_) {}
    }
    if (role == 'clinician') return false;
    await _authApi?.logout(); // clear the JWT / server session
    _currentUser = null;
    _biometricUnlocked = false;
    _authError = role.isEmpty
        ? 'This app is for clinicians only.'
        : 'This app is for clinicians only — $role accounts use the web app.';
    notifyListeners();
    return true;
  }

  /// Shared failed-login accounting (lockout + audit) for local and live paths.
  Future<bool> _failLogin(String key, String username, {String? message}) async {
    final attempts = (_failedAttempts[key] ?? 0) + 1;
    _failedAttempts[key] = attempts;
    if (attempts >= _maxFailedAttempts) {
      _lockedUntil[key] = DateTime.now().add(_lockoutDuration);
      _failedAttempts[key] = 0;
      _authError =
          'Account temporarily locked after $attempts failed attempts.';
    } else {
      _authError = message ?? 'Invalid username or password credentials.';
    }
    await _audit('LOGIN_FAILURE',
        clinician: 'unknown', details: 'Failed login for $username');
    notifyListeners();
    return false;
  }

  int _asInt(Object? v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  /// Biometric-first launch: if a saved JWT is still valid, restore the user
  /// (GET /auth/me) so the app opens straight to the biometric vault instead of
  /// the password screen. No-op in demo mode or when there's no token.
  Future<void> tryRestoreSession() async {
    if (!_live || _authApi == null) return;
    if (!_authApi!.tokens.hasToken) return;
    try {
      final me = await _authApi!.me();
      final u = (me?['user'] ?? me) as Map?;
      if (u == null || u['email'] == null) return;
      // Clinician-only: never restore a non-clinician session.
      if ((u['role'] ?? '').toString().toLowerCase() != 'clinician') {
        await _authApi!.logout();
        return;
      }
      _currentUser = User(
        id: _asInt(u['id']),
        username: u['email'].toString(),
        passwordHash: '', // unknown on restore; vault uses biometric / live re-auth
        fullName: (u['name'] ?? u['email']).toString(),
        provider: 'live',
        role: (u['role'] ?? 'clinician').toString(),
      );
      _restoredSession = true;
      _biometricUnlocked = false;
      await _refreshPatients();
      notifyListeners();
    } catch (_) {
      // Token expired/invalid or offline — fall back to the login screen.
    }
  }

  void logout() {
    _audit('LOGOUT', details: 'User ${_currentUser?.username} signed out');
    // Live mode: drop the JWT so the next session must re-authenticate.
    if (_live) _authApi?.logout();
    _inactivityTimer?.cancel();
    // Purge in-memory PHI so nothing lingers after sign-out (HIPAA access ctrl).
    _currentUser = null;
    _biometricUnlocked = false;
    _vaultError = null;
    _patients = [];
    _users = [];
    _recordings = [];
    _selectedPatient = null;
    _searchQuery = '';
    _adminMessage = null;
    _openVisitByPatient.clear();
    _restoredSession = false;
    notifyListeners();
  }

  // --- HIPAA automatic logoff ---
  /// Called on user interaction to reset the inactivity countdown.
  void registerActivity() {
    if (_currentUser == null || !_biometricUnlocked) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(inactivityTimeout, _onInactivityTimeout);
  }

  void _onInactivityTimeout() {
    if (_currentUser == null) return;
    // Never auto-logoff mid-recording: the clinician is in an active visit with
    // the patient and isn't touching the screen, so a re-lock here would
    // interrupt the recording with a biometric prompt. Re-arm and re-check once
    // the recording is done (an active recording is itself "activity").
    if (_isRecording) {
      _inactivityTimer = Timer(inactivityTimeout, _onInactivityTimeout);
      return;
    }
    _audit('AUTO_LOGOFF', details: 'Session locked after inactivity timeout');
    _biometricUnlocked = false; // re-lock the PHI vault; biometric required again
    notifyListeners();
  }

  // --- Audit trail (HIPAA audit controls) ---

  /// Every audit write goes through here, so this is the one place that can
  /// guarantee the trail is PHI-free.
  ///
  /// [patientId] is the correct way to tie an event to a patient: it is a
  /// reference, not an identifier, and it stays meaningful after the row leaves
  /// the device. [details] is free text for the human reading the log and must
  /// never name a patient — it is scrubbed by [_scrubDetails] as a backstop.
  Future<void> _audit(String action, {String? clinician, int? patientId, String details = ''}) async {
    await _db.insertAudit(AuditEntry(
      clinicianId: _currentUser?.id ?? -1,
      clinicianName: clinician ?? _currentUser?.fullName ?? 'system',
      action: action,
      patientId: patientId,
      details: _scrubDetails(details),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// Last-resort PHI filter for an audit detail string.
  ///
  /// Call sites are written not to include PHI, but audit rows are retained for
  /// years and are shipped to the server, so a leak introduced later would be
  /// both durable and remote. This catches the two identifiers the app actually
  /// handles: an MRN in any of its written forms, and the name of any patient
  /// currently loaded. It is a backstop, not a licence — the clinician's own
  /// name and email stay, because an audit trail's whole purpose is recording
  /// who acted.
  String _scrubDetails(String details) {
    if (details.isEmpty) return details;
    var out = details.replaceAll(
        RegExp(r'\bMRN[-\s:]?[A-Za-z0-9][A-Za-z0-9-]*', caseSensitive: false),
        '[mrn]');
    for (final p in _patients) {
      final name = p.name.trim();
      // Two characters or fewer would match far too much ("Al", initials).
      if (name.length < 3) continue;
      if (out.contains(name)) out = out.replaceAll(name, '[patient]');
    }
    return out.length <= 500 ? out : '${out.substring(0, 497)}...';
  }

  Future<List<AuditEntry>> loadAuditLogs() => _db.getAuditLogs();

  Future<List<Recording>> loadAllRecordings() => _db.getAllRecordings();

  String patientNameById(int id) {
    for (final p in _patients) {
      if (p.id == id) return p.name;
    }
    return 'Patient #$id';
  }

  /// Biometric PHI-vault gate. FAILS CLOSED: on any error, cancellation, or
  /// missing biometric hardware the vault stays locked and the user must enter
  /// their account password (see [unlockVaultWithPassword]). It never
  /// auto-unlocks — a HIPAA access-control requirement.
  Future<void> unlockVault() async {
    // Don't prompt again if a prompt is already showing or we're already in.
    if (_authInProgress || _biometricUnlocked) return;
    _authInProgress = true;
    _vaultError = null;
    try {
      final supported = await _localAuth.isDeviceSupported() ||
          await _localAuth.canCheckBiometrics;
      _biometricAvailable = supported;
      if (!supported) {
        _vaultError = 'Biometrics unavailable. Enter your password to unlock.';
        notifyListeners();
        return;
      }
      final ok = await _localAuth.authenticate(
        localizedReason: 'Verify your identity to access patient records.',
        // biometricOnly:true avoids the deprecated DEVICE_CREDENTIAL path that
        // double-prompts on Android 10. persistAcrossBackgrounding:false stops
        // local_auth from re-launching the prompt when the system BiometricPrompt
        // briefly pauses/resumes the activity — the cause of the "prompt shows
        // twice" bug. The PHI vault still has its own in-app password fallback.
        biometricOnly: true,
        persistAcrossBackgrounding: false,
      );
      if (ok) {
        _unlockSuccess('biometric');
      } else {
        _vaultError = 'Verification failed. Try again or use your password.';
        notifyListeners();
      }
    } catch (_) {
      // Fail CLOSED: never grant access on a platform error.
      _biometricAvailable = false;
      _vaultError = 'Biometric error. Enter your password to unlock.';
      notifyListeners();
    } finally {
      _authInProgress = false;
    }
  }

  /// Password fallback for the PHI vault (when biometrics fail/unavailable).
  /// On a restored session we have no local password hash, so we verify by
  /// re-authenticating against the live server instead.
  Future<bool> unlockVaultWithPassword(String password) async {
    final user = _currentUser;
    if (user == null) return false;

    if (_restoredSession && _live && _authApi != null) {
      final r = await _authApi!.login(user.username, password);
      if (r.outcome == LoginOutcome.success) {
        _currentUser = user.copyWith(passwordHash: Security.hashPassword(password));
        _restoredSession = false;
        _unlockSuccess('password');
        return true;
      }
      _vaultError = r.message ?? 'Incorrect password.';
      notifyListeners();
      return false;
    }

    if (Security.verifyPassword(password, user.passwordHash)) {
      _unlockSuccess('password');
      return true;
    }
    _vaultError = 'Incorrect password.';
    notifyListeners();
    return false;
  }

  void _unlockSuccess(String method) {
    _biometricUnlocked = true;
    _vaultError = null;
    _audit('VAULT_UNLOCK', details: 'PHI vault unlocked via $method');
    registerActivity(); // begin the automatic-logoff countdown
    notifyListeners();
  }

  /// Add a new patient. In live mode this mirrors the web app's "Schedule New
  /// Patient": it creates the patient AND an initial visit (so the patient shows
  /// up for the clinician on both app and web), then routes the recording to
  /// that same visit. [dob] is `YYYY-MM-DD` (optional).
  Future<bool> addPatient({
    required String name,
    required String mrn,
    String? dob,
    String visitType = 'New Patient',
    String? visitDate,
    String? visitTime,
    String gender = 'Unknown',
    String priority = 'Medium',
    String specialty = 'General',
    String medicalHistory = '',
  }) async {
    if (name.trim().isEmpty || mrn.trim().isEmpty) {
      _adminMessage = 'Patient name and MRN are required.';
      notifyListeners();
      return false;
    }
    if (_live && _patientsApi != null) {
      try {
        final created = (await _patientsApi!
                .create(name: name.trim(), mrn: mrn.trim(), dob: dob))
            // Keep the chosen DOB + visit type + visit date on the in-memory
            // patient so the card shows them immediately (the server's
            // GET /patients payload omits visit type/date).
            .copyWith(
                dob: dob,
                visitType: visitType,
                visitDate: _visitMillis(visitDate, visitTime));
        // Create the visit so the patient is visible to the clinician (the
        // server's GET /patients INNER JOINs visits), and remember it so the
        // recording attaches here instead of creating a second visit.
        final visitId = await _patientsApi!.createVisitForPatient(created.id,
            visitType: visitType, visitDate: visitDate, visitTime: visitTime);
        if (visitId != null) _openVisitByPatient[created.id] = visitId;
        _patients = [created, ..._patients.where((p) => p.id != created.id)];
        _lastAddedPatientId = created.id;
      } catch (e) {
        _adminMessage = e is ApiException ? e.message : 'Could not add patient.';
        notifyListeners();
        return false;
      }
      await _audit('ADD_PATIENT',
          patientId: _lastAddedPatientId, details: 'Added patient [live]');
      notifyListeners();
      return true;
    }
    await _db.insertPatient(Patient(
      name: name.trim(),
      mrn: mrn.trim(),
      age: _ageFromDob(dob),
      gender: gender,
      priority: priority,
      lastContactDate: DateTime.now().millisecondsSinceEpoch,
      medicalHistory: medicalHistory.trim(),
      specialty: specialty.trim().isEmpty ? 'General' : specialty.trim(),
    ));
    await _refreshPatients();
    final match = _patients.where((p) => p.mrn == mrn.trim()).toList();
    _lastAddedPatientId = match.isNotEmpty ? match.first.id : null;
    // Audited after the refresh so the row can carry the patient id instead of
    // the name and MRN it used to record.
    await _audit('ADD_PATIENT',
        patientId: _lastAddedPatientId, details: 'Added patient');
    notifyListeners();
    return true;
  }

  /// Combines a 'YYYY-MM-DD' date + optional 'HH:mm' time into epoch millis.
  int _visitMillis(String? date, String? time) {
    if (date == null || date.isEmpty) return 0;
    final t = (time != null && time.isNotEmpty) ? time : '00:00';
    final dt = DateTime.tryParse('${date}T$t');
    return dt?.millisecondsSinceEpoch ?? 0;
  }

  int _ageFromDob(String? dob) {
    if (dob == null || dob.isEmpty) return 0;
    final d = DateTime.tryParse(dob);
    if (d == null) return 0;
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age < 0 || age > 130 ? 0 : age;
  }

  /// Public pull-to-refresh entry point for the patient list.
  Future<void> refreshPatients() async {
    await _refreshPatients();
    notifyListeners();
  }

  Future<void> _refreshPatients() async {
    if (_live && _patientsApi != null) {
      try {
        final server = await _patientsApi!.list();
        final ids = server.map((p) => p.id).toSet();
        // Preserve just-created patients the server still omits (no visit yet),
        // so they stay recordable until their first visit makes them appear.
        final pending =
            _patients.where((p) => p.id != 0 && !ids.contains(p.id)).toList();
        _patients = [...pending, ...server];
      } catch (_) {/* transient: keep last known roster */}
    } else {
      _patients = await _db.getAllPatients();
    }
  }

  Future<void> _refreshUsers() async {
    _users = await _db.getAllUsers();
  }

  // --- Administration (admin-gated) ---
  Future<void> adminCreateAccount(
      String username, String fullName, String password, String role) async {
    if (!isAdmin) return;
    final u = username.trim();
    if (u.isEmpty || fullName.trim().isEmpty || password.isEmpty) {
      _adminMessage = 'Username, full name and password are all required.';
      notifyListeners();
      return;
    }
    if (await _db.getUserByUsername(u) != null) {
      _adminMessage = "Username '$u' already exists.";
      notifyListeners();
      return;
    }
    await _db.insertUser(User(
        username: u,
        passwordHash: Security.hashPassword(password),
        fullName: fullName.trim(),
        role: role));
    _adminMessage = "Account '$u' created.";
    await _audit('ADMIN_CREATE_USER', details: 'Created $role account: $u');
    await _refreshUsers();
    notifyListeners();
  }

  Future<void> adminResetPassword(int userId, String newPassword) async {
    if (!isAdmin) return;
    if (newPassword.isEmpty) {
      _adminMessage = 'Password cannot be empty.';
      notifyListeners();
      return;
    }
    final hashed = Security.hashPassword(newPassword);
    await _db.updatePassword(userId, hashed);
    if (_currentUser?.id == userId) {
      _currentUser = _currentUser!.copyWith(passwordHash: hashed);
    }
    _adminMessage = 'Password updated.';
    await _audit('ADMIN_RESET_PASSWORD', details: 'Password reset for user id $userId');
    await _refreshUsers();
    notifyListeners();
  }

  Future<void> adminDeleteAccount(int userId) async {
    if (!isAdmin) return;
    if (userId == _currentUser?.id) {
      _adminMessage = 'You cannot delete the account you are signed in with.';
      notifyListeners();
      return;
    }
    final target = await _db.getUserById(userId);
    if (target == null) return;
    if (target.role == 'admin' && await _db.getAdminCount() <= 1) {
      _adminMessage = 'Cannot delete the last remaining administrator.';
      notifyListeners();
      return;
    }
    await _db.deleteUser(userId);
    _adminMessage = 'Account removed.';
    await _audit('ADMIN_DELETE_USER', details: 'Deleted user id $userId (${target.username})');
    await _refreshUsers();
    notifyListeners();
  }

  // --- Recording (per-patient clinical audio) ---
  Patient? patientById(int id) {
    for (final p in _patients) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> openPatientVisit(int patientId) async {
    _selectedPatient = patientById(patientId);
    await loadRecordings(patientId);
    await _audit('VIEW_PATIENT_RECORDS', patientId: patientId,
        details: 'Opened visit');
    notifyListeners();
  }

  Future<void> loadRecordings(int patientId) async {
    _recordings = await _db.getRecordingsForPatient(patientId);
    notifyListeners();
  }

  /// HIPAA data-minimisation: delete local encrypted recordings that have been
  /// uploaded to the scribe and are older than [keepFor]. Recently-uploaded
  /// audio is kept so the clinician can still replay it; this just bounds the
  /// device's storage and limits how long PHI lingers on the phone.
  Future<void> purgeOldRecordings(
      {Duration keepFor = const Duration(days: 7)}) async {
    try {
      final cutoff = DateTime.now().subtract(keepFor).millisecondsSinceEpoch;
      final all = await _db.getAllRecordings();
      for (final r in all) {
        if (r.isUploaded && r.timestamp < cutoff) {
          try {
            final f = File(r.audioFilePath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
          await _db.deleteRecording(r.id);
        }
      }
    } catch (_) {/* best-effort cleanup */}
  }

  Future<void> startRecording(int patientId) async {
    if (_isRecording) return;
    registerActivity();
    if (!await _recorder.hasPermission()) {
      _adminMessage = 'Microphone permission denied.';
      notifyListeners();
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final recDir = Directory('${dir.path}/recordings');
    if (!await recDir.exists()) await recDir.create(recursive: true);
    final path =
        '${recDir.path}/visit_${patientId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
    // Speech-optimized: mono, modest bitrate → small files, fast upload.
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 22050,
        numChannels: 1,
        bitRate: 64000,
      ),
      path: path,
    );
    _isRecording = true;
    _isPaused = false;
    _recordingPatientId = patientId;
    _recordingSeconds = 0;
    _recordStartMs = DateTime.now().millisecondsSinceEpoch;
    _pausedAccumMs = 0;
    _pauseStartMs = null;
    _recordingLevel = 0;
    // Tactile confirmation the recording actually started (eyes-free).
    HapticFeedback.mediumImpact();

    // Let the phone follow its NATURAL sleep/lock behavior during recording —
    // forcing the screen on for 30-40 min heats the device and drains battery.
    // Capture keeps running with the screen off via the microphone foreground
    // service (partial wakelock: CPU stays awake, screen may sleep). Elapsed time
    // is computed from a wall-clock start stamp (see _durationTimer) so it stays
    // correct even if the UI isolate was paused while the phone slept.

    // Foreground service keeps capture alive when backgrounded / screen-locked.
    await RecordingForeground.start(
      title: 'Recording visit',
      text: 'Notenra is recording. Tap to return.',
    );

    // Persist a recovery marker so a crash/kill doesn't lose the recording.
    await _markerStore.write(
      key: _activeRecKey,
      value: jsonEncode({
        'path': path,
        'patientId': patientId,
        'start': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) {
        // Recompute from the wall clock (not ++) so a background pause doesn't
        // undercount — on resume this jumps straight to the true elapsed time.
        _recordingSeconds = _elapsedRecordingMs() ~/ 1000;
        notifyListeners();
      }
    });
    // Live input level for the meter.
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
      // dBFS (~-60 floor .. 0 max) → 0..1.
      final norm = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      _recordingLevel = norm;
      notifyListeners();
    });

    await _audit('START_RECORDING', patientId: patientId,
        details: 'Recording started');
    notifyListeners();
  }

  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    try {
      await _recorder.pause();
      _isPaused = true;
      _pauseStartMs = DateTime.now().millisecondsSinceEpoch;
      registerActivity();
      await _audit('PAUSE_RECORDING', patientId: _recordingPatientId,
          details: 'Recording paused');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;
    try {
      await _recorder.resume();
      if (_pauseStartMs != null) {
        _pausedAccumMs += DateTime.now().millisecondsSinceEpoch - _pauseStartMs!;
        _pauseStartMs = null;
      }
      _isPaused = false;
      _recordingSeconds = _elapsedRecordingMs() ~/ 1000;
      registerActivity();
      await _audit('RESUME_RECORDING', patientId: _recordingPatientId,
          details: 'Recording resumed');
      notifyListeners();
    } catch (_) {}
  }

  /// Stops recording, persists it locally, and returns the saved [Recording]
  /// (or null) so the caller can hand it off to the clinical workflow/sync.
  Future<Recording?> stopAndSaveRecording() async {
    if (!_isRecording) return null;
    _durationTimer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    final rawPath = await _recorder.stop();
    final patientId = _recordingPatientId;
    final durationMs = _elapsedRecordingMs(); // true wall-clock length
    _recordStartMs = null;
    _isRecording = false;
    _isPaused = false;
    HapticFeedback.mediumImpact(); // confirm the recording stopped
    _recordingLevel = 0;
    _recordingPatientId = null;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    await RecordingForeground.stop();
    Recording? saved;
    if (rawPath != null && patientId != null) {
      final count = _recordings.length;
      final label = count == 0 ? 'Primary Consultation' : 'Addendum Note #$count';
      final now = DateTime.now().millisecondsSinceEpoch;
      // Persist + show the recording IMMEDIATELY using the plaintext path, so a
      // long recording appears the instant you stop — instead of only after the
      // slow (multi-second) at-rest encryption of a large file. The encryption
      // and the hand-off to the scribe then run in the background, so the UI
      // never freezes on stop.
      final id = await _db.insertRecording(Recording(
        patientId: patientId,
        audioFilePath: rawPath,
        label: label,
        durationMs: durationMs,
        timestamp: now,
      ));
      saved = Recording(
        id: id,
        patientId: patientId,
        audioFilePath: rawPath,
        label: label,
        durationMs: durationMs,
        timestamp: now,
      );
      await _db.updatePatientLastContact(patientId, now);
      await _audit('SAVE_RECORDING', patientId: patientId,
          details: 'Saved "$label" (${durationMs ~/ 1000}s)');
      await loadRecordings(patientId); // ← recording is visible now
      // The recording is safely in the DB, so the crash-recovery marker for the
      // in-progress capture can be cleared; a kill during background securing is
      // handled by _recoverOrphanRecordings (it finalizes DB rows still on a
      // plaintext path).
      await _markerStore.delete(key: _activeRecKey);
      unawaited(_finalizeRecording(saved));
    } else {
      await _markerStore.delete(key: _activeRecKey);
    }
    await _refreshPatients();
    notifyListeners();
    return saved;
  }

  /// Statuses that can only be reached once the server actually holds the
  /// audio. `pendingUpload`/`recording` mean it hasn't landed yet; `failed`
  /// means it never will, and must stay re-sendable.
  static bool _serverHasAudio(VisitStatus s) =>
      s == VisitStatus.withScribe ||
      s == VisitStatus.readyForReview ||
      s == VisitStatus.changesRequested ||
      s == VisitStatus.approved ||
      s == VisitStatus.syncedToEhr;

  /// Background finalize for a saved recording: encrypt it at rest, repoint the
  /// stored path to the `.enc` file, then hand it to the scribe (offline-safe
  /// outbox). Runs off the UI path so stopping a long recording never blocks.
  Future<void> _finalizeRecording(Recording rec) async {
    final patientId = rec.patientId;
    var finalPath = rec.audioFilePath;
    try {
      if (!AudioVault.isEncrypted(finalPath)) {
        final enc = await AudioVault.encryptInPlace(finalPath);
        if (enc != finalPath) {
          await _db.updateRecordingPath(finalPath, enc);
          finalPath = enc;
          if (_selectedPatient?.id == patientId) await loadRecordings(patientId);
        }
      }
      final visit = await _clinical?.submitRecording(
        patientId: patientId,
        patientName: patientNameById(patientId),
        audioPath: finalPath,
        durationMs: rec.durationMs,
        existingVisitId: openVisitFor(patientId),
      );
      // Mark uploaded for ANY status that means the server has the audio — not
      // just 'withScribe'. If the scribe had already submitted a note the
      // status comes back readyForReview/approved, and the old exact-match
      // check left the row 'pending', so every later sign-in re-uploaded the
      // same file and the visit grew a duplicate audio card each time.
      // (A still-queued upload is marked later via onAudioUploaded.)
      if (visit != null && _serverHasAudio(visit.status)) {
        await markRecordingUploaded(finalPath);
      }
    } catch (_) {/* outbox retries the upload; audio is safe on disk */}
  }

  Future<void> playRecording(String path) async {
    registerActivity();
    if (_playingPath == path) {
      await _player.stop();
      await _cleanupPlaybackTemp();
      _playingPath = null;
      notifyListeners();
      return;
    }
    _playingPath = path;
    notifyListeners();
    // Encrypted audio is decrypted to a short-lived temp file just for playback.
    String playPath = path;
    if (AudioVault.isEncrypted(path)) {
      try {
        playPath = await AudioVault.decryptToTemp(path);
        _playingTempPath = playPath;
      } catch (_) {
        _playingPath = null;
        notifyListeners();
        return;
      }
    }
    await _player.setFilePath(playPath);
    await _player.play();
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _cleanupPlaybackTemp();
        _playingPath = null;
        notifyListeners();
      }
    });
  }

  Future<void> _cleanupPlaybackTemp() async {
    final t = _playingTempPath;
    _playingTempPath = null;
    if (t != null) {
      try {
        final f = File(t);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> deleteRecording(int id) async {
    final rec = await _db.getRecordingById(id);
    if (rec != null) {
      try {
        final f = File(rec.audioFilePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      await _db.deleteRecording(id);
      await _audit('DELETE_RECORDING', patientId: rec.patientId,
          details: 'Deleted recording id $id');
      await loadRecordings(rec.patientId);
    }
  }

  /// Marks a recording as sent to the scribe but KEEPS the local encrypted copy
  /// so the clinician can play it back to review what was captured. The audio
  /// stays AES-GCM encrypted at rest; the clinician can delete it from the visit
  /// screen once they no longer need it.
  Future<void> markRecordingUploaded(String path) async {
    await _db.updateRecordingUploadStatus(path, 'uploaded');
    final pid = _selectedPatient?.id;
    if (pid != null) await loadRecordings(pid);
    notifyListeners();
  }

  /// Recovers audio left behind by a crash/kill mid-recording (or a stop that
  /// was interrupted before the file was encrypted+saved), so a capture is never
  /// lost. Called after login: first the marker-tracked recording, then any
  /// orphaned raw file still sitting in the recordings folder.
  Future<void> _recoverInterruptedRecording() async {
    await _recoverFromMarker();
    await _recoverOrphanRecordings();
    await _reuploadPendingRecordings();
  }

  /// Re-send any saved recording that never reached the scribe — in particular
  /// one that was already encrypted at rest but whose upload was cut short (for
  /// example, the session timed out mid-upload after a long recording, which
  /// forced a sign-out). The file-scan recovery above only catches *plaintext*
  /// leftovers; this closes the gap for encrypted-but-un-uploaded rows so a
  /// recording is never stranded on the device. Runs after every sign-in/unlock.
  Future<void> _reuploadPendingRecordings() async {
    try {
      for (final r in await _db.getAllRecordings()) {
        if (r.isUploaded) continue;
        // Plaintext leftovers are handled by _recoverOrphanRecordings; here we
        // only re-send rows already secured at rest whose upload was interrupted.
        if (!AudioVault.isEncrypted(r.audioFilePath)) continue;
        if (!await File(r.audioFilePath).exists()) continue;
        // Already waiting its turn in the outbox — re-submitting here would
        // put a SECOND copy of the same file in the queue, and the server
        // appends rather than replaces, so the visit would show duplicate
        // audio cards. Leave it to the queue that already owns it.
        if (_clinical?.isUploadQueued(r.audioFilePath) ?? false) continue;
        await _finalizeRecording(r);
      }
    } catch (_) {/* best-effort; the outbox also retries when possible */}
  }

  Future<void> _recoverFromMarker() async {
    final raw = await _markerStore.read(key: _activeRecKey);
    if (raw == null) return;
    await _markerStore.delete(key: _activeRecKey);
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final path = m['path'] as String;
      final patientId = m['patientId'] as int;
      final start = m['start'] as int;
      if (!await File(path).exists()) return;
      final approxMs = (DateTime.now().millisecondsSinceEpoch - start)
          .clamp(0, 6 * 3600 * 1000);
      final id = await _db.insertRecording(Recording(
        patientId: patientId,
        audioFilePath: path,
        label: 'Recovered Recording',
        durationMs: approxMs,
        timestamp: start,
      ));
      final rec = Recording(
        id: id,
        patientId: patientId,
        audioFilePath: path,
        label: 'Recovered Recording',
        durationMs: approxMs,
        timestamp: start,
      );
      _recoveredRecording = rec;
      await _audit('RECOVER_RECORDING', patientId: patientId,
          details: 'Recovered an interrupted recording');
      _adminMessage = 'Recovered an interrupted recording.';
      if (_selectedPatient?.id == patientId) await loadRecordings(patientId);
      notifyListeners();
      await _finalizeRecording(rec); // encrypt at rest + hand to the scribe
    } catch (_) {}
  }

  /// Scan the recordings folder for a raw (unencrypted) `.m4a` with no `.enc`
  /// sibling — i.e. a capture whose encrypt/save never completed (e.g. an older
  /// build that could hang when stopping a long recording). Encrypt and save it
  /// so it's not lost. A leftover plaintext that WAS already encrypted is just
  /// deleted (data-minimisation). Normally a no-op.
  Future<void> _recoverOrphanRecordings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recDir = Directory('${dir.path}/recordings');
      if (!await recDir.exists()) return;
      final byPath = {
        for (final r in await _db.getAllRecordings()) r.audioFilePath: r
      };
      for (final entity in recDir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.m4a')) continue;
        final p = entity.path;
        if (await File('$p.enc').exists()) {
          try {
            await entity.delete(); // already encrypted; drop the plaintext
          } catch (_) {}
          continue;
        }
        final len = await entity.length();
        if (len < 1024) {
          try {
            await entity.delete(); // empty/aborted capture
          } catch (_) {}
          continue;
        }
        // Already a saved recording still on its plaintext path (killed while
        // securing in the background) — just finish encrypting + uploading it;
        // don't create a duplicate.
        final existingRec = byPath[p];
        if (existingRec != null) {
          await _finalizeRecording(existingRec);
          continue;
        }
        // A truly orphaned raw file not in the DB (e.g. from an older build that
        // could hang on stop). Filename: visit_<patientId>_<startMs>.m4a
        final name = p.split(Platform.pathSeparator).last;
        final parts = name.replaceAll('.m4a', '').split('_');
        if (parts.length < 3) continue;
        final patientId = int.tryParse(parts[1]);
        if (patientId == null) continue;
        final start =
            int.tryParse(parts[2]) ?? DateTime.now().millisecondsSinceEpoch;
        // Estimate duration from size (~8 KB/s at 64 kbps mono).
        final approxMs = (len / 8).round();
        final id = await _db.insertRecording(Recording(
          patientId: patientId,
          audioFilePath: p,
          label: 'Recovered Recording',
          durationMs: approxMs,
          timestamp: start,
        ));
        final rec = Recording(
          id: id,
          patientId: patientId,
          audioFilePath: p,
          label: 'Recovered Recording',
          durationMs: approxMs,
          timestamp: start,
        );
        _recoveredRecording = rec;
        await _audit('RECOVER_RECORDING', patientId: patientId,
            details: 'Recovered an orphaned recording (${len ~/ 1024} KB)');
        _adminMessage = 'Recovered an interrupted recording.';
        if (_selectedPatient?.id == patientId) await loadRecordings(patientId);
        notifyListeners();
        await _finalizeRecording(rec); // encrypt at rest + hand to the scribe
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _durationTimer?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}
