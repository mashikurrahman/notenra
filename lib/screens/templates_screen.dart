import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/clinician_templates.dart';
import '../services/clinical_service.dart';
import '../services/templates_service.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';

Color _hexColor(String hex, Color fallback) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Count the note's section headers (uppercase lines ending in ':') for a quick
/// at-a-glance preview on the list card.
int _sectionCount(String content) {
  var n = 0;
  for (final line in content.split('\n')) {
    final t = line.trim();
    if (t.length > 1 &&
        t.endsWith(':') &&
        t == t.toUpperCase() &&
        t.toUpperCase() != t.toLowerCase()) {
      n++;
    }
  }
  return n;
}

/// Manage the clinician's reusable note templates: view the prebuilt set and
/// edit them to their own requirements. Backed by [TemplatesService], which
/// syncs with the server and falls back to on-device storage.
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  /// Push the screen with its own [TemplatesService] (reusing the app's
  /// authenticated client), and kick off the initial load.
  static Future<void> open(BuildContext context) {
    final svc = context.read<ClinicalService>();
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) =>
            TemplatesService(ClinicianTemplatesApi(svc.apiClient))..load(),
        child: const TemplatesScreen(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<TemplatesService>();
    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          NotenraHeader.titled(
            title: 'Note templates',
            subtitle: 'Reusable note structures you can edit',
            actions: [
              HeaderIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                busy: svc.loading,
                onTap: svc.loading ? null : svc.load,
              ),
            ],
          ),
          Expanded(child: _body(context, svc)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        backgroundColor: Nx.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
    );
  }

  Widget _body(BuildContext context, TemplatesService svc) {
    final templates = svc.templates;
    final showOffline = svc.error != null && !svc.serverReached;

    if (svc.loading && templates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (showOffline)
          Padding(
            padding: const EdgeInsets.only(bottom: Nx.s1),
            child: NxBanner(
              icon: Icons.cloud_off,
              color: Nx.warning,
              message: svc.error!,
            ),
          )
        else if (svc.pendingSync)
          Padding(
            padding: const EdgeInsets.only(bottom: Nx.s1),
            child: NxBanner(
              icon: Icons.sync_problem,
              color: Nx.warning,
              message: 'Changes saved on this device — not yet synced to the server.',
            ),
          ),
        if (templates.isEmpty)
          Expanded(
            child: NxEmptyState(
              icon: Icons.description_outlined,
              title: 'No templates yet',
              hint: 'Create a reusable note structure to start from.',
              action: FilledButton.icon(
                onPressed: () => _openEditor(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New template'),
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s4, Nx.s4, 96),
              children: [
                for (final t in templates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Nx.s3),
                    child: _templateCard(context, svc, t),
                  ),
                const SizedBox(height: Nx.s2),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _confirmReset(context, svc),
                    style: TextButton.styleFrom(foregroundColor: Nx.muted),
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Reset to default templates'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _templateCard(
      BuildContext context, TemplatesService svc, NoteTemplate t) {
    final bg = _hexColor(t.color, Nx.surface);
    final sections = _sectionCount(t.content);
    return NxCard(
      onTap: () => _openEditor(context, t),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Nx.rSm),
            ),
            alignment: Alignment.center,
            child: Text(t.icon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: Nx.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Nx.ink)),
                const SizedBox(height: 2),
                Text(
                    sections == 0
                        ? 'Empty template · tap to edit'
                        : '$sections section${sections == 1 ? '' : 's'} · tap to edit',
                    style: const TextStyle(color: Nx.muted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Nx.muted),
            tooltip: 'Delete template',
            onPressed: () => _confirmDelete(context, svc, t),
          ),
          const Icon(Icons.chevron_right, color: Nx.muted, size: 20),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, NoteTemplate? existing) {
    final svc = context.read<TemplatesService>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: svc,
        child: _TemplateEditorScreen(existing: existing),
      ),
    ));
  }

  Future<void> _confirmDelete(
      BuildContext context, TemplatesService svc, NoteTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('"${t.name}" will be removed from your templates.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Nx.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await svc.deleteTemplate(t.id);
  }

  Future<void> _confirmReset(
      BuildContext context, TemplatesService svc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to defaults?'),
        content: const Text(
            'This replaces your templates with the built-in set (New Patient, '
            'Follow-Up, Virtual Visit, Other). Your edits will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) await svc.resetToDefaults();
  }
}

/// Full-screen editor for a single template: its name and section content.
class _TemplateEditorScreen extends StatefulWidget {
  final NoteTemplate? existing;
  const _TemplateEditorScreen({this.existing});

  @override
  State<_TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<_TemplateEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _content;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    // A new template starts from the standard section skeleton so the clinician
    // has a structure to adapt rather than a blank page.
    _content = TextEditingController(
        text: widget.existing?.content ??
            defaultClinicianTemplates.first.content);
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  String _slugId(String name, List<NoteTemplate> existing) {
    var slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) slug = 'template';
    final ids = existing.map((e) => e.id).toSet();
    if (!ids.contains(slug)) return slug;
    var i = 2;
    while (ids.contains('$slug-$i')) {
      i++;
    }
    return '$slug-$i';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give the template a name.')));
      return;
    }
    setState(() => _saving = true);
    final svc = context.read<TemplatesService>();
    final base = widget.existing;
    final saved = base != null
        ? base.copyWith(name: name, content: _content.text)
        : NoteTemplate(
            id: _slugId(name, svc.templates),
            name: name,
            content: _content.text);
    await svc.upsert(saved);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Template "${saved.name}" saved.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          NotenraHeader.titled(
            title: _isNew ? 'New template' : 'Edit template',
            subtitle: _isNew ? null : widget.existing!.name,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s5, Nx.s4, Nx.s8),
              children: [
                const SectionHeader(
                    label: 'Template name', icon: Icons.label_outline),
                const SizedBox(height: Nx.s2),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Diabetes Follow-Up',
                    filled: true,
                    fillColor: Nx.card,
                  ),
                ),
                const SizedBox(height: Nx.s5),
                const SectionHeader(
                    label: 'Note structure', icon: Icons.notes_outlined),
                const SizedBox(height: Nx.s1),
                const Text(
                  'Section headers (e.g. CHIEF COMPLAINT:) are recognized when '
                  'written in capitals. Edit the structure to suit your practice.',
                  style: TextStyle(color: Nx.muted, fontSize: 12),
                ),
                const SizedBox(height: Nx.s3),
                NxCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Nx.s3, vertical: Nx.s1),
                  child: TextField(
                    controller: _content,
                    maxLines: null,
                    minLines: 14,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                        fontSize: 14, height: 1.5, color: Nx.ink),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _saveBar(),
        ],
      ),
    );
  }

  Widget _saveBar() {
    return Container(
      padding: const EdgeInsets.all(Nx.s4),
      decoration: BoxDecoration(
        color: Nx.card,
        border: const Border(top: BorderSide(color: Nx.border)),
        boxShadow: Nx.cardShadow,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving ? 'Saving…' : 'Save template'),
          ),
        ),
      ),
    );
  }
}
