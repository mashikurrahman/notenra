import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Surface admin action messages as snackbars.
    final msg = state.adminMessage;
    if (msg != null) {
      state.clearAdminMessage();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      });
    }

    if (!state.isAdmin) {
      return Scaffold(
        backgroundColor: Nx.canvas,
        body: Column(
          children: [
            NotenraHeader.titled(title: 'User administration'),
            const Expanded(
              child: NxEmptyState(
                icon: Icons.lock_outline,
                title: 'Administrator access required',
                hint: 'Sign in with an administrator account to manage users.',
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Nx.canvas,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Nx.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New account',
            style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => _showAddDialog(context, state),
      ),
      body: Column(
        children: [
          NotenraHeader.titled(
            title: 'User administration',
            subtitle:
                '${state.users.length} account${state.users.length == 1 ? '' : 's'}',
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s4, Nx.s4, 88),
              itemCount: state.users.length,
              separatorBuilder: (_, _) => const SizedBox(height: Nx.s3),
              itemBuilder: (context, i) {
                final u = state.users[i];
                final isSelf = u.id == state.currentUser?.id;
                return NxCard(
                  padding: const EdgeInsets.all(Nx.s4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                Nx.primary.withValues(alpha: 0.12),
                            child: Icon(
                                u.isAdmin
                                    ? Icons.shield_outlined
                                    : Icons.person_outline,
                                color: Nx.primary),
                          ),
                          const SizedBox(width: Nx.s3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Nx.ink)),
                                Text(u.username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Nx.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                          _RoleBadge(isAdmin: u.isAdmin),
                        ],
                      ),
                      const SizedBox(height: Nx.s3),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.lock_reset, size: 18),
                              label: const Text('Reset password',
                                  style: TextStyle(fontSize: 13)),
                              onPressed: () =>
                                  _showResetDialog(context, state, u),
                            ),
                          ),
                          if (!isSelf) ...[
                            const SizedBox(width: Nx.s2),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Nx.danger,
                                side: const BorderSide(color: Nx.danger),
                              ),
                              onPressed: () =>
                                  _confirmDelete(context, state, u),
                              child: const Icon(Icons.delete_outline, size: 18),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, AppState state) {
    final user = TextEditingController();
    final name = TextEditingController();
    final pass = TextEditingController();
    bool admin = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Nx.card,
          title: const Text('New account',
              style: TextStyle(fontWeight: FontWeight.bold, color: Nx.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(name, 'Full name'),
              const SizedBox(height: 10),
              _dialogField(user, 'Username / email'),
              const SizedBox(height: 10),
              _dialogField(pass, 'Initial password'),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: Nx.primary,
                value: admin,
                onChanged: (v) => setLocal(() => admin = v ?? false),
                title: const Text('Grant administrator privileges',
                    style: TextStyle(fontSize: 14, color: Nx.secondary)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Nx.secondary))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Nx.primary),
              onPressed: () {
                state.adminCreateAccount(
                    user.text, name.text, pass.text, admin ? 'admin' : 'clinician');
                Navigator.pop(ctx);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, AppState state, User u) {
    final pass = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Nx.card,
        title: const Text('Reset password',
            style: TextStyle(fontWeight: FontWeight.bold, color: Nx.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Set a new password for ${u.fullName} (${u.username}).',
                style: TextStyle(
                    fontSize: 13, color: Nx.secondary.withValues(alpha: 0.7))),
            const SizedBox(height: 12),
            _dialogField(pass, 'New password'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Nx.secondary))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Nx.primary),
            onPressed: () {
              state.adminResetPassword(u.id, pass.text);
              Navigator.pop(ctx);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState state, User u) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Nx.card,
        title: const Text('Remove account',
            style: TextStyle(fontWeight: FontWeight.bold, color: Nx.ink)),
        content: Text(
            'Delete the account for ${u.fullName} (${u.username})? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Nx.secondary))),
          TextButton(
            onPressed: () {
              state.adminDeleteAccount(u.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Nx.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController c, String label) => TextField(
        controller: c,
        style: const TextStyle(color: Nx.secondary),
        decoration: InputDecoration(
          labelText: label,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Nx.outline)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Nx.primary, width: 2)),
        ),
      );
}

class _RoleBadge extends StatelessWidget {
  final bool isAdmin;
  const _RoleBadge({required this.isAdmin});
  @override
  Widget build(BuildContext context) {
    final color = isAdmin ? Nx.ink : Nx.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100)),
      child: Text(isAdmin ? 'ADMIN' : 'CLINICIAN',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }
}
