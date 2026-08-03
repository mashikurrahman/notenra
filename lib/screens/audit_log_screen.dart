import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';

/// HIPAA audit-controls viewer: a read-only trail of access and admin events.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  late Future<List<AuditEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadAuditLogs();
  }

  void _reload() {
    setState(() => _future = context.read<AppState>().loadAuditLogs());
  }

  Color _actionColor(String a) {
    if (a.contains('FAILURE') || a.contains('DELETE')) return Nx.danger;
    if (a.startsWith('ADMIN') || a.contains('AUTO_LOGOFF')) return Nx.warning;
    return Nx.success;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          NotenraHeader.titled(
            title: 'Audit trail',
            subtitle: 'Read-only record of access and admin events',
            actions: [
              HeaderIconButton(
                  icon: Icons.refresh, tooltip: 'Reload', onTap: _reload),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<AuditEntry>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final logs = snap.data!;
                if (logs.isEmpty) {
                  return const NxEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No audit events yet',
                    hint: 'Access and admin activity will be recorded here.',
                  );
                }
                return ListView.separated(
                  padding:
                      const EdgeInsets.fromLTRB(Nx.s4, Nx.s4, Nx.s4, Nx.s8),
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Nx.s2),
                  itemBuilder: (context, i) => _entry(logs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _entry(AuditEntry e) {
    final color = _actionColor(e.action);
    final ts = DateFormat('MMM d, HH:mm:ss')
        .format(DateTime.fromMillisecondsSinceEpoch(e.timestamp));
    return NxCard(
      accentEdge: color,
      padding: const EdgeInsets.all(Nx.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.action,
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: color, fontSize: 13)),
          if (e.details.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(e.details,
                style: const TextStyle(color: Nx.secondary, fontSize: 12)),
          ],
          const SizedBox(height: 3),
          Text('${e.clinicianName} · $ts',
              style: const TextStyle(color: Nx.muted, fontSize: 11)),
        ],
      ),
    );
  }
}
