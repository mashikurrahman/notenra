import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logo.dart';
import '../secure_store.dart';
import '../services/clinical_service.dart';
import '../theme.dart';
import '../widgets/pressable.dart';
import 'first_login_screen.dart';
import 'mfa_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  // "Remember my email" — convenience only. We persist ONLY the email (in the
  // app's encrypted storage), never the password. The PHI vault still gates
  // access behind biometrics on every launch, so this can't weaken auth.
  bool _rememberEmail = true;
  static const _store = SecureStore();
  static const _rememberFlagKey = 'remember_email_flag';
  static const _rememberValueKey = 'remember_email_value';

  @override
  void initState() {
    super.initState();
    _restoreRememberedEmail();
  }

  Future<void> _restoreRememberedEmail() async {
    try {
      // Default ON for a first run (no saved choice yet); otherwise honor the
      // user's last toggle.
      final flag = await _store.read(key: _rememberFlagKey);
      final remember = flag == null ? true : flag == '1';
      final saved =
          remember ? await _store.read(key: _rememberValueKey) : null;
      if (!mounted) return;
      setState(() {
        _rememberEmail = remember;
        if (saved != null && saved.isNotEmpty && _userCtrl.text.isEmpty) {
          _userCtrl.text = saved;
        }
      });
    } catch (_) {
      // Storage unavailable — just start with an empty, unremembered field.
    }
  }

  /// Persist (or clear) the remembered email per the current toggle.
  Future<void> _saveRememberChoice() async {
    try {
      await _store.write(
          key: _rememberFlagKey, value: _rememberEmail ? '1' : '0');
      final email = _userCtrl.text.trim();
      if (_rememberEmail && email.isNotEmpty) {
        await _store.write(key: _rememberValueKey, value: email);
      } else {
        await _store.delete(key: _rememberValueKey);
      }
    } catch (_) {
      // Best-effort convenience; never block sign-in on a storage hiccup.
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final state = context.read<AppState>();
    await _saveRememberChoice();
    final ok = await state.login(_userCtrl.text, _passCtrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) return; // RootGate switches to the vault / home.

    // First-login gates: route to the in-app screen that completes them
    // (forced password change → possibly PHI training → signed in).
    switch (state.authGate) {
      case AuthGate.passwordChange:
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ForcePasswordChangeScreen()));
        return;
      case AuthGate.phiTraining:
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PhiTrainingScreen()));
        return;
      case AuthGate.mfaEnrollment:
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MfaEnrollmentScreen()));
        return;
      case AuthGate.mfaChallenge:
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MfaChallengeScreen()));
        return;
      case AuthGate.none:
        if (state.authError != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.authError!)));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<ClinicalService>().isLive;
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Stack(
        children: [
          // Soft decorative brand bloom behind the logo.
          Positioned(
            top: -130,
            right: -90,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Nx.primary.withValues(alpha: 0.18),
                  Nx.primary.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -110,
            left: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Nx.ink.withValues(alpha: 0.07),
                  Nx.ink.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    const NotenraLogo(height: 46),
                    const SizedBox(height: 10),
                    Text('AMBIENT CLINICAL SCRIBE',
                        style: Nx.sectionLabel.copyWith(fontSize: 10.5)),
                    const SizedBox(height: 28),
                    // Floating sign-in card.
                    Container(
                      padding: const EdgeInsets.fromLTRB(
                          Nx.s5, Nx.s6, Nx.s5, Nx.s6),
                      decoration: BoxDecoration(
                        color: Nx.card,
                        borderRadius: BorderRadius.circular(Nx.rXl),
                        border: Border.all(color: Nx.border),
                        boxShadow: Nx.cardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Welcome back',
                              style: TextStyle(
                                  color: Nx.ink,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3)),
                          const SizedBox(height: 4),
                          const Text('Sign in to continue',
                              style:
                                  TextStyle(color: Nx.muted, fontSize: 13)),
                          const SizedBox(height: 20),
                          _field(
                            _userCtrl,
                            'Username / email',
                            Icons.person_outline,
                            keyboardType: TextInputType.emailAddress,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            enableSuggestions: false,
                          ),
                          const SizedBox(height: 14),
                          _field(
                            _passCtrl,
                            'Password',
                            Icons.lock_outline,
                            obscure: _obscure,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            enableSuggestions: false,
                            suffix: IconButton(
                              icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Nx.muted),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _rememberEmailToggle(),
                          const SizedBox(height: 16),
                          Pressable(child: _signInButton()),
                          if (state.biometricAvailable && _userCtrl.text.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _biometricQuickButton(state),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (live)
                      _infoBox(
                        icon: Icons.verified_user_outlined,
                        child: const Text(
                            'Connected to the live Notenra server. Sign in '
                            'with your clinician email and password.',
                            style: TextStyle(
                                color: Nx.muted, fontSize: 12, height: 1.4)),
                      )
                    else
                      _infoBox(
                        icon: Icons.science_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Demo accounts',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Nx.ink,
                                    fontSize: 12)),
                            SizedBox(height: 6),
                            Text('admin / admin123  (administrator)',
                                style: TextStyle(
                                    color: Nx.muted, fontSize: 12)),
                            Text('dr.smith@notenra.health / password123',
                                style: TextStyle(
                                    color: Nx.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rememberEmailToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _rememberEmail = !_rememberEmail),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _rememberEmail,
                activeColor: Nx.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (v) =>
                    setState(() => _rememberEmail = v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Remember my email',
                style: TextStyle(
                    color: Nx.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Tooltip(
              message:
                  'Saves only your email for next time — never your password.',
              child: Icon(Icons.info_outline,
                  size: 15, color: Nx.muted.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signInButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        boxShadow: _busy ? null : Nx.buttonGlow,
      ),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: Nx.buttonGradient,
            borderRadius: BorderRadius.circular(100),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: _busy ? null : _submit,
            child: SizedBox(
              height: 54,
              child: Center(
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Sign in securely',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 15)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 18),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoBox({required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Nx.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Nx.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Nx.primary),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _biometricQuickButton(AppState state) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Nx.primary,
        side: BorderSide(color: Nx.primary.withValues(alpha: 0.45)),
        minimumSize: const Size(0, 48),
      ),
      onPressed: _busy
          ? null
          : () async {
              HapticFeedback.selectionClick();
              await state.unlockVault();
            },
      icon: const Icon(Icons.fingerprint, size: 22),
      label: const Text('Unlock with Biometrics',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool obscure = false,
      Widget? suffix,
      TextInputType? keyboardType,
      TextCapitalization textCapitalization = TextCapitalization.none,
      bool autocorrect = true,
      bool enableSuggestions = true}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      style: const TextStyle(color: Nx.secondary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Nx.primary),
        suffixIcon: suffix,
      ),
    );
  }
}
