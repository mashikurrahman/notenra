import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logo.dart';
import '../theme.dart';
import '../widgets/nx.dart';

/// First-time MFA (TOTP) enrollment. The server mandates an authenticator-app
/// second factor for PHI access. We fetch the secret + QR, the clinician adds
/// it to Google Authenticator / Authy, then confirms with a 6-digit code.
class MfaEnrollmentScreen extends StatefulWidget {
  const MfaEnrollmentScreen({super.key});

  @override
  State<MfaEnrollmentScreen> createState() => _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends State<MfaEnrollmentScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = true;
  bool _verifying = false;
  String? _setupError;
  String? _secret;
  Uint8List? _qrBytes;
  List<String> _recoveryCodes = const [];

  @override
  void initState() {
    super.initState();
    _codeCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSetup();
      _checkClipboard();
    });
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (RegExp(r'^\d{6}$').hasMatch(text) && mounted && _codeCtrl.text.isEmpty) {
        _codeCtrl.text = text;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSetup() async {
    setState(() {
      _loading = true;
      _setupError = null;
    });
    final res = await context.read<AppState>().mfaSetup();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _secret = res.secret;
      _qrBytes = _decodeQr(res.qrCode);
      _recoveryCodes = res.recoveryCodes;
      _setupError = (res.secret == null && res.qrCode == null)
          ? (res.error ?? 'Could not start MFA setup.')
          : null;
    });
  }

  /// Decode a `data:image/png;base64,…` QR into bytes for Image.memory.
  /// Robust to whitespace/newlines and missing padding in the data-uri.
  Uint8List? _decodeQr(String? dataUri) {
    if (dataUri == null || dataUri.isEmpty) return null;
    final i = dataUri.indexOf('base64,');
    var b64 = (i >= 0 ? dataUri.substring(i + 7) : dataUri).trim();
    b64 = b64.replaceAll(RegExp(r'\s'), '');
    try {
      return base64Decode(base64.normalize(b64));
    } catch (_) {
      try {
        return base64Decode(b64);
      } catch (_) {
        return null;
      }
    }
  }

  bool get _codeValid => _codeCtrl.text.trim().length == 6;

  Future<void> _verify() async {
    if (!_codeValid || _verifying) return;
    setState(() => _verifying = true);
    final state = context.read<AppState>();
    final ok = await state.completeMfaEnrollment(_codeCtrl.text);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (state.authError != null) {
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
        title: const Text('Set up two-factor',
            style: TextStyle(
                color: Nx.ink, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Nx.secondary),
          onPressed: _verifying ? null : _cancel,
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Nx.primary))
            : _setupError != null
                ? _errorState()
                : _content(),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 44, color: Nx.danger.withValues(alpha: 0.8)),
            const SizedBox(height: 14),
            Text(_setupError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Nx.ink)),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Nx.primary),
              onPressed: _loadSetup,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              '1. Open your authenticator app (Google Authenticator, Authy, …) and scan this QR code.',
              style: TextStyle(color: Nx.muted, fontSize: 13, height: 1.4)),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Nx.border),
                boxShadow: Nx.rowShadow,
              ),
              child: _qrBytes != null
                  ? Image.memory(_qrBytes!,
                      width: 220,
                      height: 220,
                      filterQuality: FilterQuality.none,
                      gaplessPlayback: true,
                      fit: BoxFit.contain)
                  : const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(
                          child: Icon(Icons.qr_code_2,
                              size: 80, color: Nx.secondary))),
            ),
          ),
          const SizedBox(height: 16),
          if (_secret != null) _manualKey(),
          if (_recoveryCodes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _recoveryCodesBox(),
          ],
          const SizedBox(height: 20),
          Text('2. Enter the 6-digit code your app shows.',
              style: TextStyle(color: Nx.muted, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          NxPinInput(controller: _codeCtrl, onSubmit: _verify),
          const SizedBox(height: 20),
          _verifyButton(),
        ],
      ),
    );
  }

  Widget _manualKey() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Nx.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Nx.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.vpn_key, size: 16, color: Nx.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    "Can't scan? In your authenticator tap \"Enter a setup key\" and type this:",
                    style: TextStyle(color: Nx.muted, fontSize: 11)),
                const SizedBox(height: 2),
                SelectableText(_secret!,
                    style: const TextStyle(
                        color: Nx.ink,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.5)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18, color: Nx.primary),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _secret!));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Key copied.')));
            },
          ),
        ],
      ),
    );
  }

  Widget _recoveryCodesBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Nx.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Nx.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 16, color: Nx.warning),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Save your backup codes',
                    style: TextStyle(
                        color: Nx.ink,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
              IconButton(
                tooltip: 'Copy all',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 18, color: Nx.primary),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: _recoveryCodes.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Backup codes copied.')));
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              'Use one of these if you ever lose your authenticator. Each works once — store them somewhere safe.',
              style: TextStyle(color: Nx.muted, fontSize: 11, height: 1.3)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recoveryCodes
                .map((c) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Nx.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Nx.border),
                      ),
                      child: SelectableText(c,
                          style: const TextStyle(
                              color: Nx.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              letterSpacing: 1)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _verifyButton() {
    final enabled = _codeValid && !_verifying;
    return SizedBox(
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Nx.primary,
          disabledBackgroundColor: Nx.primary.withValues(alpha: 0.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
        onPressed: enabled ? _verify : null,
        child: _verifying
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Text('Verify & continue',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 15)),
      ),
    );
  }
}

/// Per-login MFA challenge for an already-enrolled clinician: enter the current
/// 6-digit code from the authenticator app.
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _codeCtrl = TextEditingController();
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _codeCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (RegExp(r'^\d{6}$').hasMatch(text) && mounted && _codeCtrl.text.isEmpty) {
        _codeCtrl.text = text;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  bool get _codeValid => _codeCtrl.text.trim().length == 6;

  Future<void> _verify() async {
    if (!_codeValid || _verifying) return;
    setState(() => _verifying = true);
    final state = context.read<AppState>();
    final ok = await state.completeMfaChallenge(_codeCtrl.text);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (state.authError != null) {
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
          onPressed: _verifying ? null : _cancel,
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
                const NotenraLogo(height: 60),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
                          Icon(Icons.verified_user, color: Nx.primary),
                          SizedBox(width: 8),
                          Text('Two-factor verification',
                              style: TextStyle(
                                  color: Nx.ink,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                          'Enter the 6-digit code from your authenticator app.',
                          style:
                              TextStyle(color: Nx.muted, fontSize: 13)),
                      const SizedBox(height: 20),
                      NxPinInput(controller: _codeCtrl, onSubmit: _verify),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Nx.primary,
                            disabledBackgroundColor:
                                Nx.primary.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100)),
                          ),
                          onPressed:
                              (_codeValid && !_verifying) ? _verify : null,
                          child: _verifying
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Verify',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 15)),
                        ),
                      ),
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
}

