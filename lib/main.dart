import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'api/api_config.dart';
import 'api/client_identity.dart';
import 'api/token_store.dart';
import 'services/clinical_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'theme.dart';
import 'widgets/nx.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  // Guard the entire startup so a failure in any single init step can never
  // leave the app on a blank white screen. If something throws, we still get
  // into the UI (degraded) and — on a non-release build — surface the actual
  // error so it can be diagnosed (e.g. on a simulator / Appetize).
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final startupErrors = <String>[];

    // The foreground-service comm port is Android-centric; never let it block
    // launch (it's not needed until a recording starts).
    try {
      FlutterForegroundTask.initCommunicationPort();
    } catch (e) {
      startupErrors.add('foreground task: $e');
    }

    final tokens = TokenStore();
    final connectivity = ConnectivityService();
    late final ClinicalService clinical;

    // Each step is individually guarded: one failing dependency (DB, secure
    // storage, connectivity) must not stop the app from reaching the login UI.
    try {
      await ApiConfig.load();
    } catch (e) {
      startupErrors.add('config: $e');
    }
    // Client attribution headers (device id + user agent). Must resolve before
    // the first request so no call goes out unattributed; it never throws.
    await ClientIdentity.init();
    try {
      await tokens.load();
    } catch (e) {
      startupErrors.add('tokens: $e');
    }
    try {
      await connectivity.init();
    } catch (e) {
      startupErrors.add('connectivity: $e');
    }
    // Local notifications (recording uploaded / note ready). Fire-and-forget —
    // the plugin init must never delay launch, and it swallows its own errors.
    unawaited(NotificationService.instance.init());

    clinical = ClinicalService(connectivity: connectivity, tokens: tokens);
    try {
      await clinical.init();
    } catch (e, st) {
      startupErrors.add('clinical: $e');
      debugPrint('CLINICAL INIT FAILED: $e\n$st');
    }

    if (startupErrors.isNotEmpty) {
      debugPrint('STARTUP ERRORS:\n${startupErrors.join('\n')}');
    }

    final state = AppState(clinical: clinical, tokens: tokens);
    // Credentials-first launch: the app always opens to the login screen. The
    // clinician signs in with their email + password; the biometric / Face ID
    // check then runs as a second factor right after sign-in (see RootGate).
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: clinical),
        ],
        // On a debug build, if startup hit problems, show them on top of the
        // app so they're visible on a simulator with no log access.
        child: NotenraApp(
          startupError:
              (kReleaseMode || startupErrors.isEmpty)
                  ? null
                  : startupErrors.join('\n'),
        ),
      ),
    );
  }, (error, stack) {
    // Last-resort handler: paint the error instead of a blank screen.
    debugPrint('UNCAUGHT STARTUP ERROR: $error\n$stack');
    runApp(_StartupErrorApp(message: '$error'));
  });
}

/// Shown only if startup completely fails — guarantees the screen is never a
/// silent blank, so the failure is diagnosable on a device/simulator.
class _StartupErrorApp extends StatelessWidget {
  final String message;
  const _StartupErrorApp({required this.message});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Nx.ink,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Startup failed',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(message,
                        style: const TextStyle(
                            color: Color(0xFFFFB4A2), fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotenraApp extends StatefulWidget {
  final String? startupError;
  const NotenraApp({super.key, this.startupError});
  @override
  State<NotenraApp> createState() => _NotenraAppState();
}

class _NotenraAppState extends State<NotenraApp> {
  @override
  void initState() {
    super.initState();
    final err = widget.startupError;
    if (err != null) {
      // Surface non-fatal startup problems once the first frame is up, so a
      // simulator with no log access still shows what went wrong.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 12),
            backgroundColor: const Color(0xFF7A1F1F),
            content: Text('Startup issue: $err',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notenra',
      debugShowCheckedModeBanner: false,
      theme: buildNotenraTheme(),
      // Any pointer interaction resets the HIPAA automatic-logoff countdown.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => context.read<AppState>().registerActivity(),
        child: _RecordingOverlay(child: child ?? const SizedBox.shrink()),
      ),
      home: const _BootGate(),
    );
  }
}

/// Shows the branded splash animation first, then cross-fades to the real app
/// (login / home). The splash is cosmetic; startup work already ran in `main()`.
class _BootGate extends StatefulWidget {
  const _BootGate();
  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: _ready
          ? const RootGate()
          : SplashScreen(onDone: () {
              if (mounted) setState(() => _ready = true);
            }),
    );
  }
}

/// App-wide "● Recording mm:ss" banner shown above everything while a recording
/// is in progress, so the clinician always knows capture is live — even after
/// navigating away from the visit screen.
class _RecordingOverlay extends StatelessWidget {
  final Widget child;
  const _RecordingOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    final recording = context.select<AppState, bool>((s) => s.isRecording);
    if (!recording) return child;
    final secs = context.select<AppState, int>((s) => s.recordingSeconds);
    final paused = context.select<AppState, bool>((s) => s.isPaused);
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return Column(
      children: [
        Material(
          // Live capture is the brand green (the pulse in the mark); paused is
          // amber. Red is reserved for genuine failures.
          color: paused ? Nx.warning : Nx.accent,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Nx.s4, vertical: Nx.s2),
              child: Row(
                children: [
                  if (paused)
                    const Icon(Icons.pause_circle_filled,
                        color: Colors.white, size: 16)
                  else
                    const _LiveDot(),
                  const SizedBox(width: Nx.s2),
                  Text(paused ? 'Recording paused' : 'Recording',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.2)),
                  const Spacer(),
                  Text('$mm:$ss',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// A softly pulsing dot — the "we are capturing right now" tell in the banner.
class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Routes between login, the biometric PHI-vault lock, and the app.
class RootGate extends StatelessWidget {
  const RootGate({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.currentUser == null) return const LoginScreen();
    if (!state.biometricUnlocked) return const VaultLockScreen();
    // First-login tour (one time), shown inside the authenticated boundary.
    if (state.needsOnboarding) return const OnboardingScreen();
    return const HomeShell();
  }
}

class VaultLockScreen extends StatefulWidget {
  const VaultLockScreen({super.key});
  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen> {
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().unlockVault();
    });
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitPassword() async {
    setState(() => _verifying = true);
    await context.read<AppState>().unlockVaultWithPassword(_passwordCtrl.text);
    if (mounted) setState(() => _verifying = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final showPwField = _showPassword || !state.biometricAvailable;

    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Nx.s6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: NxCard(
              elevated: true,
              padding: const EdgeInsets.fromLTRB(Nx.s6, Nx.s8, Nx.s6, Nx.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand mark inside a lock ring — the vault reads as Notenra's,
                  // not as a generic system prompt.
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Nx.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.lock_outline,
                        size: 36, color: Nx.primary),
                  ),
                  const SizedBox(height: Nx.s5),
                  const Text('Vault locked',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          letterSpacing: -0.5,
                          color: Nx.ink)),
                  const SizedBox(height: Nx.s2),
                  const Text(
                      'Verify your identity to open encrypted patient records.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Nx.muted, fontSize: 13.5)),
                  if (state.vaultError != null) ...[
                    const SizedBox(height: Nx.s4),
                    NxBanner(
                      icon: Icons.error_outline,
                      color: Nx.danger,
                      message: state.vaultError!,
                    ),
                  ],
                  const SizedBox(height: Nx.s6),
                  if (state.biometricAvailable)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.read<AppState>().unlockVault(),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Unlock with biometrics'),
                      ),
                    ),
                  if (showPwField) ...[
                    const SizedBox(height: Nx.s4),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submitPassword(),
                      decoration: const InputDecoration(
                        labelText: 'Account password',
                        prefixIcon: Icon(Icons.key_outlined, color: Nx.muted),
                      ),
                    ),
                    const SizedBox(height: Nx.s3),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Nx.ink),
                        onPressed: _verifying ? null : _submitPassword,
                        child: Text(
                            _verifying ? 'Verifying…' : 'Unlock with password'),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: Nx.s2),
                      child: TextButton(
                        onPressed: () => setState(() => _showPassword = true),
                        child: const Text('Use password instead'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
