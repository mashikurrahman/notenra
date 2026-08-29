import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logo.dart';
import '../theme.dart';
import '../widgets/pressable.dart';
import 'mfa_screen.dart';

/// The screen that completes a given first-login [gate], or null when there's
/// nothing left to do (signed in / [AuthGate.none]). Shared by the login screen
/// and the gate screens so completing one gate can chain to the next
/// (e.g. password change → MFA enrollment).
Widget? nextGateScreen(AuthGate gate) {
  switch (gate) {
    case AuthGate.passwordChange:
      return const ForcePasswordChangeScreen();
    case AuthGate.phiTraining:
      return const PhiTrainingScreen();
    case AuthGate.mfaEnrollment:
      return const MfaEnrollmentScreen();
    case AuthGate.mfaChallenge:
      return const MfaChallengeScreen();
    case AuthGate.none:
      return null;
  }
}

/// First-login forced password change. An admin creates the clinician account
/// with a temporary password; the server requires it to be rotated before any
/// access. This screen captures the new password (the current one isn't needed
/// — the short-lived login token authorizes the change) and, on success, lets
/// [AppState] continue the sign-in (which may surface the PHI-training gate
/// next, handled by [PhiTrainingScreen]).
class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() =>
      _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _newCtrl.addListener(() => setState(() {}));
    _confirmCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Mirror the server's HIPAA password policy so the user gets instant feedback
  // (the server is still the source of truth and will reject anything weaker).
  bool get _hasLen => _newCtrl.text.length >= 12;
  bool get _hasUpper => RegExp(r'[A-Z]').hasMatch(_newCtrl.text);
  bool get _hasLower => RegExp(r'[a-z]').hasMatch(_newCtrl.text);
  bool get _hasDigit => RegExp(r'[0-9]').hasMatch(_newCtrl.text);
  bool get _hasSpecial => RegExp(r'[^A-Za-z0-9]').hasMatch(_newCtrl.text);
  bool get _matches =>
      _confirmCtrl.text.isNotEmpty && _newCtrl.text == _confirmCtrl.text;
  bool get _valid =>
      _hasLen && _hasUpper && _hasLower && _hasDigit && _hasSpecial && _matches;

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final signedIn = await state.completePasswordChange(_newCtrl.text);
    if (!mounted) return;
    setState(() => _busy = false);

    if (signedIn) {
      // Fully authenticated — drop back to the root gate (vault / home).
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    // Password changed, but another first-login gate is next (PHI training or
    // MFA). Advance to it.
    final next = nextGateScreen(state.authGate);
    if (next != null) {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => next));
      return;
    }
    // Otherwise the change was rejected (policy/expiry) — show why.
    if (state.authError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.authError!)));
    }
  }

  void _cancel() {
    context.read<AppState>().clearAuthGate();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AppState>().gateEmail;
    return Scaffold(
      backgroundColor: Nx.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Nx.secondary),
          onPressed: _busy ? null : _cancel,
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NotenraLogo(height: 64),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                  decoration: BoxDecoration(
                    color: Nx.card,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Nx.border),
                    boxShadow: Nx.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.lock_reset, color: Nx.primary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Set a new password',
                                style: TextStyle(
                                    color: Nx.ink,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                          email == null
                              ? 'For security, choose a new password before continuing.'
                              : 'For security, $email must choose a new password before continuing.',
                          style: TextStyle(color: Nx.muted, fontSize: 13)),
                      const SizedBox(height: 20),
                      _passwordField(
                        _newCtrl,
                        'New password',
                        _obscureNew,
                        () => setState(() => _obscureNew = !_obscureNew),
                      ),
                      const SizedBox(height: 14),
                      _passwordField(
                        _confirmCtrl,
                        'Confirm new password',
                        _obscureConfirm,
                        () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      const SizedBox(height: 16),
                      _policyChecklist(),
                      const SizedBox(height: 20),
                      Pressable(child: _submitButton()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField(TextEditingController c, String label, bool obscure,
      VoidCallback toggle) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Nx.secondary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, color: Nx.primary),
        suffixIcon: IconButton(
          icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: Nx.muted),
          onPressed: toggle,
        ),
      ),
    );
  }

  Widget _policyChecklist() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Nx.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Nx.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rule('At least 12 characters', _hasLen),
          _rule('An uppercase letter', _hasUpper),
          _rule('A lowercase letter', _hasLower),
          _rule('A number', _hasDigit),
          _rule('A special character', _hasSpecial),
          _rule('Both passwords match', _matches),
        ],
      ),
    );
  }

  Widget _rule(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(met ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: met ? Nx.success : Nx.muted.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: met ? Nx.ink : Nx.muted,
                  fontWeight: met ? FontWeight.w600 : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _submitButton() {
    final enabled = _valid && !_busy;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: Nx.buttonGradient,
            borderRadius: BorderRadius.circular(100),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: enabled ? _submit : null,
            child: SizedBox(
              height: 54,
              child: Center(
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save & continue',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 15)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// First-login PHI awareness training acknowledgement. The credentials are
/// valid but the server withholds a full session until the clinician confirms
/// they've reviewed their PHI-handling responsibilities. On acknowledgement the
/// real session is granted and the user proceeds into the app.
class PhiTrainingScreen extends StatefulWidget {
  const PhiTrainingScreen({super.key});

  @override
  State<PhiTrainingScreen> createState() => _PhiTrainingScreenState();
}

class _PhiTrainingScreenState extends State<PhiTrainingScreen> {
  bool _agreed = false;
  bool _busy = false;

  Future<void> _acknowledge() async {
    if (!_agreed || _busy) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final ok = await state.acknowledgeTrainingGate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    // PHI ack may chain into the MFA gate next.
    final next = nextGateScreen(state.authGate);
    if (next != null) {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => next));
      return;
    }
    if (state.authError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.authError!)));
    }
  }

  void _cancel() {
    context.read<AppState>().clearAuthGate();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Nx.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Nx.secondary),
          onPressed: _busy ? null : _cancel,
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _modalHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _h3('What is PHI?'),
                    _para([
                      _b('PHI'),
                      _t(' means '),
                      _b('Protected Health Information'),
                      _t(' — any information that can identify a patient '),
                      _i('and'),
                      _t(' relates to their health, care, or treatment. On '
                          'Notenra this includes '),
                      _b('patient encounter audio'),
                      _t(', '),
                      _b('transcripts and AI-generated clinical notes'),
                      _t(', and '),
                      _b('patient names and details tied to a visit'),
                      _t('.'),
                    ]),
                    _h3('How Notenra Protects PHI'),
                    _bullets(const [
                      ('Encryption',
                          ' — audio is stored with AES-256 encryption; the database is encrypted at rest; everything travels over secure (TLS) connections.'),
                      ('Audit logging',
                          " — the system records who did what and when. Logs are append-only (they can't be quietly edited or deleted) and kept for 7 years."),
                      ('Access control',
                          ' — people get only the access their role needs (admin, super_admin, clinician, scribe).'),
                      ('Automatic cleanup',
                          ' — encounter audio is deleted after 90 days.'),
                      ('Trusted partners',
                          ' — our transcription and AI partners operate under signed Business Associate Agreements (BAAs).'),
                    ]),
                    _h3('Your Responsibilities'),
                    _bullets(const [
                      ('',
                          'Access only the patient information your job requires (the "minimum necessary" rule).'),
                      ('',
                          'Keep your login private — never share your password or let someone use your account.'),
                      ('',
                          'Use strong, unique passwords and log out of shared devices.'),
                      ('',
                          'Never copy PHI to personal devices, email, or unapproved tools.'),
                      ('', 'Lock your screen when you step away.'),
                    ]),
                    _h3('If You Suspect a Breach'),
                    _para([
                      _t('A breach is any time PHI may have been seen, taken, or '
                          'changed by someone who shouldn\'t have access. '),
                      _b("Act fast and don't investigate alone:"),
                      _t(' report it immediately to '),
                      _b('support@notenra.com'),
                      _t(' (and '),
                      _b('admin@notenra.com'),
                      _t(' for anything urgent). Don\'t try to fix it quietly, '
                          'write down what you saw, and preserve evidence. '
                          'Reporting in good faith is always the right call.'),
                    ]),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _modalHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.shield, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('PHI Awareness Training',
                    style: TextStyle(
                        color: Nx.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                const SizedBox(height: 2),
                Text('Please review before your first access. This is required.',
                    style: TextStyle(color: Nx.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _h3(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: Nx.ink,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      );

  // Inline text-span helpers for mixed bold/italic paragraphs.
  TextSpan _t(String s) => TextSpan(text: s);
  TextSpan _b(String s) =>
      TextSpan(text: s, style: const TextStyle(fontWeight: FontWeight.bold));
  TextSpan _i(String s) =>
      TextSpan(text: s, style: const TextStyle(fontStyle: FontStyle.italic));

  Widget _para(List<TextSpan> spans) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(
          TextSpan(children: spans),
          style: const TextStyle(
              color: Nx.secondary, fontSize: 13.5, height: 1.55),
        ),
      );

  Widget _bullets(List<(String, String)> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                            color: Nx.secondary, shape: BoxShape.circle),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          if (it.$1.isNotEmpty) _b(it.$1),
                          _t(it.$2),
                        ]),
                        style: const TextStyle(
                            color: Nx.secondary,
                            fontSize: 13.5,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          color: Nx.card,
          border: Border(top: BorderSide(color: Nx.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _agreed = !_agreed),
              child: Row(
                children: [
                  Checkbox(
                    value: _agreed,
                    activeColor: Nx.primary,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                        "I acknowledge that I have read and understand Notenra's privacy practices",
                        style: TextStyle(
                            color: Nx.ink, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Nx.primary,
                  disabledBackgroundColor:
                      Nx.primary.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                onPressed: (_agreed && !_busy) ? _acknowledge : null,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('I Acknowledge',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
