import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logo.dart';
import '../services/clinical_service.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';

/// Clinician profile: identity, role, and security posture.
///
/// Identity moves up into the brand header — the clinician's name and role sit
/// on the gradient the way they do on Today — so the body is purely the
/// security posture and the sign-out. Settings live in the web app; there is
/// deliberately no Settings anywhere in this app.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;
    final name = user?.fullName ?? 'Clinician';
    final isAdmin = user?.role == 'admin';

    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          NotenraHeader.titled(
            title: 'Profile',
            bottom: _identity(name, user?.username ?? '', isAdmin),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s5, Nx.s4, Nx.s8),
              children: [
                _section('Practice', Icons.local_hospital_outlined, [
                  _row('Primary department',
                      isAdmin ? 'Administration' : 'Primary Care'),
                  _row('Credential level',
                      isAdmin ? 'System Administrator' : 'MD / Senior Resident'),
                ]),
                const SizedBox(height: Nx.s3),
                _section('Security', Icons.shield_outlined, [
                  _row('Account role', user?.role ?? 'clinician'),
                  _row('Biometric vault', 'Enabled', good: true),
                  _row('Auto-logoff',
                      '${AppState.inactivityTimeout.inMinutes} min inactivity'),
                  _row('Password storage', 'PBKDF2 (hashed)', good: true),
                  _row('Screenshots', 'Blocked on device', good: true),
                ]),
                const SizedBox(height: Nx.s6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Nx.danger,
                      side: const BorderSide(color: Nx.danger),
                    ),
                    onPressed: () {
                      // Purge in-memory PHI from both stores on sign-out.
                      context.read<ClinicalService>().clearForLogout();
                      state.logout();
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out securely'),
                  ),
                ),
                const SizedBox(height: Nx.s8),
                Center(
                  child: Column(
                    children: [
                      Opacity(
                        opacity: 0.5,
                        child: const NotenraLogo(height: 22),
                      ),
                      const SizedBox(height: Nx.s2),
                      Text('Version 1.0.0',
                          style: Nx.sectionLabel.copyWith(
                              fontSize: 10,
                              color: Nx.muted.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Identity block on the gradient: monogram, name, sign-in address, role.
  Widget _identity(String name, String username, bool isAdmin) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Nx.s5, 0, Nx.s5, Nx.s2),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize: 26,
                      color: Nx.primary,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: Nx.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                const SizedBox(height: 2),
                Text(username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12.5)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(Nx.rPill),
                  ),
                  child: Text(isAdmin ? 'ADMINISTRATOR' : 'CLINICIAN',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return NxCard(
      padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s3, Nx.s4, Nx.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            label: title,
            icon: icon,
            padding: const EdgeInsets.only(bottom: Nx.s2),
          ),
          ...children,
        ],
      ),
    );
  }

  /// One label/value line. [good] marks a safeguard that is actively on, so the
  /// security posture can be scanned in a glance.
  Widget _row(String label, String value, {bool good = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Nx.muted, fontSize: 13)),
            ),
            const SizedBox(width: Nx.s3),
            if (good) ...[
              const Icon(Icons.check_circle, size: 13, color: Nx.accent),
              const SizedBox(width: 4),
            ],
            Text(value,
                style: TextStyle(
                    color: good ? Nx.accent : Nx.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
      );
}
