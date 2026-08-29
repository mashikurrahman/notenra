import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/clinical_models.dart';
import '../services/clinical_service.dart';
import '../status_ui.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';

class _SoapSection {
  final String key;
  final String title;
  final String content;
  final Color color;
  final IconData icon;

  const _SoapSection({
    required this.key,
    required this.title,
    required this.content,
    required this.color,
    required this.icon,
  });
}

List<_SoapSection> _parseSoap(String text) {
  final lines = text.split('\n');
  final result = <_SoapSection>[];
  String? curKey;
  String? curTitle;
  Color curColor = Nx.primary;
  IconData curIcon = Icons.notes;
  final buf = StringBuffer();

  void flush() {
    final key = curKey;
    if (key != null && buf.isNotEmpty) {
      result.add(_SoapSection(
        key: key,
        title: curTitle ?? key,
        content: buf.toString().trim(),
        color: curColor,
        icon: curIcon,
      ));
      buf.clear();
    }
  }

  for (final line in lines) {
    final t = line.trim();
    final lower = t.toLowerCase();
    if (lower.startsWith('subjective:') || lower == 'subjective') {
      flush();
      curKey = 'SUBJECTIVE';
      curTitle = 'Subjective';
      curColor = const Color(0xFF2563EB);
      curIcon = Icons.record_voice_over;
      final rest = t.replaceFirst(RegExp(r'^subjective:?', caseSensitive: false), '').trim();
      if (rest.isNotEmpty) buf.writeln(rest);
    } else if (lower.startsWith('objective:') || lower == 'objective') {
      flush();
      curKey = 'OBJECTIVE';
      curTitle = 'Objective';
      curColor = const Color(0xFF0D9488);
      curIcon = Icons.biotech;
      final rest = t.replaceFirst(RegExp(r'^objective:?', caseSensitive: false), '').trim();
      if (rest.isNotEmpty) buf.writeln(rest);
    } else if (lower.startsWith('assessment:') || lower == 'assessment') {
      flush();
      curKey = 'ASSESSMENT';
      curTitle = 'Assessment';
      curColor = const Color(0xFFD97706);
      curIcon = Icons.analytics_outlined;
      final rest = t.replaceFirst(RegExp(r'^assessment:?', caseSensitive: false), '').trim();
      if (rest.isNotEmpty) buf.writeln(rest);
    } else if (lower.startsWith('plan:') || lower == 'plan') {
      flush();
      curKey = 'PLAN';
      curTitle = 'Plan';
      curColor = const Color(0xFF10B981);
      curIcon = Icons.playlist_add_check;
      final rest = t.replaceFirst(RegExp(r'^plan:?', caseSensitive: false), '').trim();
      if (rest.isNotEmpty) buf.writeln(rest);
    } else {
      if (curKey != null) {
        buf.writeln(line);
      }
    }
  }
  flush();
  return result;
}

/// The clinician's review of a scribe-completed note:
///   read -> small edits yourself  OR  request changes (comment to scribe)
///   OR  approve as final.
/// No "generate transcript" action; no EHR upload (the scribe does that).
class NoteReviewScreen extends StatefulWidget {
  final String visitId;
  const NoteReviewScreen({super.key, required this.visitId});

  @override
  State<NoteReviewScreen> createState() => _NoteReviewScreenState();
}

class _NoteReviewScreenState extends State<NoteReviewScreen> {
  bool _editing = false;
  String _selected = '';
  String _soapFilter = 'ALL';
  late TextEditingController _editCtrl;

  bool _loadingNote = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
  }

  Future<void> _loadNote() async {
    if (!mounted) return;
    setState(() {
      _loadingNote = true;
      _loadFailed = false;
    });
    final ok = await context.read<ClinicalService>().ensureNote(widget.visitId);
    if (!mounted) return;
    setState(() {
      _loadingNote = false;
      final v = context.read<ClinicalService>().visitById(widget.visitId);
      _loadFailed = !ok && v?.note == null;
    });
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ClinicalService>();
    final visit = svc.visitById(widget.visitId);

    if (visit == null) {
      return Scaffold(
        backgroundColor: Nx.canvas,
        body: Column(
          children: [
            NotenraHeader.titled(title: 'Note'),
            const Expanded(
              child: NxEmptyState(
                icon: Icons.help_outline,
                title: 'Visit not found',
                hint: 'It may have been removed on the server.',
              ),
            ),
          ],
        ),
      );
    }

    final s = styleFor(visit.status);
    final when = DateFormat('MMM d, h:mm a')
        .format(DateTime.fromMillisecondsSinceEpoch(visit.createdAt));

    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          NotenraHeader.titled(
            title: visit.patientName.isEmpty
                ? 'Clinical note'
                : visit.patientName,
            subtitle: '${s.detail}  ·  $when',
            actions: [
              if (visit.note != null) ...[
                HeaderIconButton(
                  icon: Icons.copy,
                  tooltip: 'Copy full note',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: visit.note!.content));
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Full note copied to clipboard.')));
                  },
                ),
                HeaderIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Reload note',
                  busy: _loadingNote,
                  onTap: _loadingNote ? null : _loadNote,
                ),
              ],
            ],
          ),
          Expanded(child: _body(context, svc, visit)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ClinicalService svc, Visit visit) {
    final note = visit.note;
    final isBusy = visit.status == VisitStatus.withScribe ||
        visit.status == VisitStatus.changesRequested ||
        visit.status == VisitStatus.pendingUpload;

    if (note == null && !isBusy) {
      if (_loadFailed) return _loadFailedState();
      if (!_loadingNote) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadNote());
      }
      return _spinnerState('Loading the note…');
    }
    if (isBusy || note == null) {
      return _busyState(visit);
    }

    final reviewable = visit.status == VisitStatus.readyForReview;
    final approved = visit.status == VisitStatus.approved ||
        visit.status == VisitStatus.syncedToEhr;

    final parsedSections = _parseSoap(note.content);

    return Column(
      children: [
        if (!_editing && parsedSections.isNotEmpty) _soapTabs(parsedSections),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s3, Nx.s4, Nx.s8),
            children: [
              if (note.feedback.isNotEmpty) ...[
                _feedbackHistory(note),
                const SizedBox(height: Nx.s3),
              ],
              _noteCard(note, reviewable, parsedSections),
            ],
          ),
        ),
        if (_editing)
          _editActions(context, svc, visit)
        else if (reviewable)
          _reviewActions(context, svc, visit)
        else if (approved)
          _approvedFooter(),
      ],
    );
  }

  Widget _soapTabs(List<_SoapSection> sections) {
    final availableKeys = {'ALL', ...sections.map((s) => s.key)};
    final tabs = [
      ('ALL', 'All sections', Icons.dashboard_outlined),
      ('SUBJECTIVE', 'Subjective (S)', Icons.record_voice_over),
      ('OBJECTIVE', 'Objective (O)', Icons.biotech),
      ('ASSESSMENT', 'Assessment (A)', Icons.analytics_outlined),
      ('PLAN', 'Plan (P)', Icons.playlist_add_check),
    ].where((t) => availableKeys.contains(t.$1)).toList();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: Nx.s4, vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final t = tabs[i];
          final active = _soapFilter == t.$1;
          return FilterChip(
            selected: active,
            showCheckmark: false,
            avatar: Icon(t.$3,
                size: 14, color: active ? Colors.white : Nx.primary),
            label: Text(t.$2,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : Nx.ink)),
            selectedColor: Nx.primary,
            backgroundColor: Nx.card,
            side: BorderSide(
                color: active ? Nx.primary : Nx.border, width: 1),
            onSelected: (_) {
              HapticFeedback.selectionClick();
              setState(() => _soapFilter = t.$1);
            },
          );
        },
      ),
    );
  }

  Widget _noteCard(ClinicalNote note, bool reviewable, List<_SoapSection> sections) {
    return NxCard(
      elevated: true,
      borderColor: _editing ? Nx.primary : Nx.border,
      padding: const EdgeInsets.all(Nx.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_editing ? Icons.edit : Icons.description_outlined,
                  color: Nx.primary, size: 18),
              const SizedBox(width: Nx.s2),
              Text(_editing ? 'Editing note' : 'Clinical note',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Nx.ink,
                      fontSize: 15)),
              const SizedBox(width: Nx.s2),
              StatusPill(label: 'v${note.version}', color: Nx.muted),
              const Spacer(),
              if (reviewable && !_editing)
                TextButton.icon(
                  onPressed: () => _startEditing(note),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Nx.s2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Nx.s3),
            child: Divider(height: 1),
          ),
          if (_editing)
            TextField(
              controller: _editCtrl,
              autofocus: true,
              maxLines: null,
              minLines: 12,
              style: const TextStyle(
                  color: Nx.secondary, height: 1.6, fontSize: 14.5),
              decoration: const InputDecoration(isDense: true),
            )
          else if (sections.isNotEmpty)
            _renderSoapSections(sections, note)
          else
            SelectableText(note.content,
                onSelectionChanged: (sel, _) => setState(
                    () => _selected = sel.textInside(note.content).trim()),
                style: const TextStyle(
                    color: Nx.secondary, height: 1.6, fontSize: 14.5)),
          if (!_editing && reviewable && sections.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Nx.s3),
              child: Text(
                  _selected.isEmpty
                      ? 'Tip: highlight a sentence to comment on it specifically.'
                      : 'Selected — tap "Comment on selection" below.',
                  style: const TextStyle(
                      color: Nx.muted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _renderSoapSections(List<_SoapSection> sections, ClinicalNote note) {
    final filtered = _soapFilter == 'ALL'
        ? sections
        : sections.where((s) => s.key == _soapFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filtered.map((sec) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Nx.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Nx.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: sec.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(sec.icon, size: 14, color: sec.color),
                        const SizedBox(width: 5),
                        Text(
                          sec.title.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: sec.color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 15, color: Nx.muted),
                    tooltip: 'Copy ${sec.title}',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: sec.content));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${sec.title} copied to clipboard.')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                sec.content,
                onSelectionChanged: (sel, _) => setState(
                    () => _selected = sel.textInside(sec.content).trim()),
                style: const TextStyle(
                  color: Nx.ink,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _startEditing(ClinicalNote note) {
    _editCtrl.text = note.content;
    setState(() => _editing = true);
  }

  Widget _feedbackHistory(ClinicalNote note) {
    return NxCard(
      color: Nx.surface,
      padding: const EdgeInsets.all(Nx.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            label: 'Comments to scribe',
            icon: Icons.forum_outlined,
            count: note.feedback.length,
            padding: const EdgeInsets.only(bottom: Nx.s3),
          ),
          for (final f in note.feedback)
            Padding(
              padding: const EdgeInsets.only(bottom: Nx.s2),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Nx.s3),
                decoration: BoxDecoration(
                  color: Nx.card,
                  borderRadius: BorderRadius.circular(Nx.rSm),
                  border: const Border(
                      left: BorderSide(color: Nx.primary, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.message,
                        style: const TextStyle(
                            color: Nx.secondary, fontSize: 13, height: 1.45)),
                    const SizedBox(height: 4),
                    Text(
                        DateFormat('MMM d, HH:mm')
                            .format(DateTime.fromMillisecondsSinceEpoch(f.at)),
                        style:
                            const TextStyle(color: Nx.muted, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _spinnerState(String message) {
    return const NxNoteSkeleton();
  }

  Widget _loadFailedState() {
    return NxEmptyState(
      icon: Icons.cloud_off,
      title: "Couldn't load the note",
      hint: 'Check your connection and try again.',
      action: FilledButton.icon(
        onPressed: _loadingNote ? null : _loadNote,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Retry'),
      ),
    );
  }

  Widget _busyState(Visit visit) {
    final s = styleFor(visit.status);
    final msg = switch (visit.status) {
      VisitStatus.withScribe =>
        'The scribe is drafting this note. It will appear here when ready for review.',
      VisitStatus.changesRequested =>
        'Your comments were sent. The scribe is updating the note.',
      VisitStatus.pendingUpload =>
        'Your recording is queued to upload. The note will be drafted once received.',
      _ => 'This note is being processed.',
    };

    return NxEmptyState(
      icon: s.icon,
      title: s.label,
      hint: msg,
      action: OutlinedButton.icon(
        onPressed: _loadingNote ? null : _loadNote,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Check for updates'),
      ),
    );
  }

  Widget _actionBar({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(Nx.s4),
      decoration: BoxDecoration(
        color: Nx.card,
        border: const Border(top: BorderSide(color: Nx.border)),
        boxShadow: Nx.cardShadow,
      ),
      child: SafeArea(top: false, child: child),
    );
  }

  Widget _editActions(BuildContext context, ClinicalService svc, Visit visit) {
    return _actionBar(
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Nx.secondary,
                side: const BorderSide(color: Nx.border),
              ),
              onPressed: () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: Nx.s3),
          Expanded(
            child: FilledButton.icon(
              onPressed: () async {
                final text = _editCtrl.text.trim();
                if (text.isEmpty) return;
                await svc.saveNoteEdit(visit.id, text);
                if (!context.mounted) return;
                setState(() => _editing = false);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Your edits were saved.')));
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save edits'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewActions(
      BuildContext context, ClinicalService svc, Visit visit) {
    final hasSel = _selected.isNotEmpty;
    return _actionBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasSel) ...[
            _selectionChip(),
            const SizedBox(height: Nx.s3),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _promptChanges(context, svc, visit,
                      quote: hasSel ? _selected : ''),
                  icon: Icon(
                      hasSel ? Icons.comment : Icons.forum_outlined, size: 18),
                  label: Text(
                      hasSel ? 'Comment on selection' : 'Request changes',
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: Nx.s3),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Nx.accent),
                  onPressed: () => _confirmApprove(context, svc, visit),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selectionChip() {
    final short =
        _selected.length > 90 ? '${_selected.substring(0, 90)}…' : _selected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Nx.s3, vertical: Nx.s2),
      decoration: BoxDecoration(
        color: Nx.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Nx.rSm),
        border: Border.all(color: Nx.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.format_quote, size: 14, color: Nx.primary),
          const SizedBox(width: Nx.s2),
          Expanded(
            child: Text('"$short"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    color: Nx.ink,
                    fontStyle: FontStyle.italic)),
          ),
          InkWell(
            onTap: () => setState(() => _selected = ''),
            child: const Icon(Icons.close, size: 16, color: Nx.muted),
          ),
        ],
      ),
    );
  }

  Widget _approvedFooter() {
    return _actionBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.check_circle_outline, color: Nx.accent, size: 18),
          SizedBox(width: Nx.s2),
          Text('Note approved — ready for EHR upload by scribe',
              style: TextStyle(
                  color: Nx.secondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _promptChanges(
      BuildContext context, ClinicalService svc, Visit visit,
      {String quote = ''}) async {
    final controller = TextEditingController();
    final comment = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Comments for the scribe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quote.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Nx.s3),
                decoration: const BoxDecoration(
                  color: Nx.surface,
                  border: Border(left: BorderSide(color: Nx.primary, width: 3)),
                ),
                child: Text('"$quote"',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Nx.ink,
                        fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: Nx.s3),
            ],
            const Text('Quick templates:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Nx.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _templateChip('Add Medication Dosage', controller),
                _templateChip('Expand Assessment', controller),
                _templateChip('Update Follow-up Plan', controller),
                _templateChip('Grammar & Formatting', controller),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: quote.isEmpty
                    ? 'What should the scribe change? e.g. "Add BP reading to Objective."'
                    : 'What should change about this sentence?',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send to scribe'),
          ),
        ],
      ),
    );
    if (comment != null && comment.isNotEmpty) {
      final message = quote.isEmpty ? comment : 'Re: "$quote"\n$comment';
      await svc.requestChanges(visit.id, message);
      if (mounted) setState(() => _selected = '');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sent to the scribe with your comments.')));
      }
    }
  }

  Widget _templateChip(String text, TextEditingController controller) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      backgroundColor: Nx.surface,
      side: const BorderSide(color: Nx.border),
      padding: EdgeInsets.zero,
      onPressed: () {
        HapticFeedback.selectionClick();
        if (controller.text.isEmpty) {
          controller.text = text;
        } else {
          controller.text = '${controller.text}; $text';
        }
      },
    );
  }

  Future<void> _confirmApprove(
      BuildContext context, ClinicalService svc, Visit visit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve as final?'),
        content: const Text(
            'This marks the note as the final version and hands it to the '
            'scribe for EHR upload. You won\'t be able to edit it afterwards.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Nx.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await svc.approve(visit.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note approved as final.')));
      }
    }
  }
}
