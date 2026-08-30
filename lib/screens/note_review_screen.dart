import 'dart:async';

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
    } else if (lower.startsWith('medical codes') ||
        lower.startsWith('billing & coding') ||
        lower.startsWith('billing & codes') ||
        lower.startsWith('billing and coding') ||
        lower.startsWith('billing:') ||
        lower.startsWith('icd-10 & cpt') ||
        lower.startsWith('coding:') ||
        lower.startsWith('codes:') ||
        lower == 'billing' ||
        lower == 'codes') {
      flush();
      curKey = 'CODES';
      curTitle = 'Medical Codes & Billing';
      curColor = const Color(0xFF7C3AED);
      curIcon = Icons.receipt_long;
      final rest = t
          .replaceFirst(
              RegExp(
                  r'^(medical codes & billing|medical codes|billing & coding|billing & codes|billing and coding|billing|icd-10 & cpt codes|icd-10 & cpt|coding|codes):?',
                  caseSensitive: false),
              '')
          .trim();
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
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLoad());
  }

  void _initLoad() {
    _loadNote();
    final v = context.read<ClinicalService>().visitById(widget.visitId);
    if (v?.note == null || v!.note!.content.trim().isEmpty) {
      _startAutoPoll();
    }
  }

  void _startAutoPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final v = context.read<ClinicalService>().visitById(widget.visitId);
      if (v?.note != null && v!.note!.content.trim().isNotEmpty) {
        timer.cancel();
        _pollTimer = null;
        return;
      }
      await _loadNote(silent: true);
    });
  }

  Future<void> _loadNote({bool silent = false, bool force = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loadingNote = true;
        _loadFailed = false;
      });
    }
    final ok = await context.read<ClinicalService>().ensureNote(widget.visitId, force: force);
    if (!mounted) return;
    setState(() {
      _loadingNote = false;
      final v = context.read<ClinicalService>().visitById(widget.visitId);
      _loadFailed = !ok && (v?.note == null || v!.note!.content.trim().isEmpty);
      if (v?.note != null && v!.note!.content.trim().isNotEmpty) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
              if (visit.note != null && visit.note!.content.trim().isNotEmpty) ...[
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
                  onTap: _loadingNote ? null : () => _loadNote(force: true),
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
    final hasContent = note != null && note.content.trim().isNotEmpty;

    if (!hasContent) {
      if (_loadFailed) return _loadFailedState();
      return _busyState(visit);
    }

    final reviewable = visit.status == VisitStatus.readyForReview ||
        visit.status == VisitStatus.withScribe ||
        visit.status == VisitStatus.pendingUpload;
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
              _noteCard(note, reviewable, parsedSections, visit),
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
      ('CODES', 'Codes (ICD/CPT)', Icons.receipt_long),
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

  Widget _noteCard(ClinicalNote note, bool reviewable, List<_SoapSection> sections, Visit visit) {
    final count = visit.recordingCount;
    return NxCard(
      elevated: true,
      borderColor: _editing ? Nx.primary : Nx.border,
      padding: const EdgeInsets.all(Nx.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_editing ? Icons.edit : Icons.auto_awesome,
                  color: Nx.primary, size: 18),
              const SizedBox(width: Nx.s2),
              Text(_editing ? 'Editing note' : 'AI Clinical Note',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Nx.ink,
                      fontSize: 15)),
              const SizedBox(width: Nx.s2),
              StatusPill(
                label: 'AI Draft',
                color: Nx.accent,
                icon: Icons.auto_awesome,
              ),
              if (count > 1) ...[
                const SizedBox(width: Nx.s2),
                StatusPill(
                  label: '$count recordings',
                  color: Nx.primary,
                  icon: Icons.graphic_eq,
                ),
              ],
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
              if (sec.key == 'CODES')
                _renderCodesSection(sec.content, sec.color)
              else
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

  Widget _renderCodesSection(String content, Color color) {
    final lines = content.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...lines.map((line) {
          final t = line.trim();
          if (t.isEmpty) return const SizedBox(height: 6);
          final lower = t.toLowerCase();
          final isHeader = t.endsWith(':') ||
              lower.contains('diagnosis codes') ||
              lower.contains('procedure codes') ||
              lower.contains('billing codes') ||
              lower.contains('cpt / e&m');
          if (isHeader) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                t,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Nx.secondary,
                  letterSpacing: 0.3,
                ),
              ),
            );
          }

          // Check for bullet or code pattern: "• I10 - Essential..." or "• 99214 - Office..."
          final cleanLine = t.replaceFirst(RegExp(r'^[•\-\*]\s*'), '');
          final parts = cleanLine.split(RegExp(r'[:\-–]\s+'));
          final code = parts.isNotEmpty ? parts[0].trim() : '';
          final desc = parts.length > 1 ? parts.sublist(1).join(' - ').trim() : '';
          final isIcd = RegExp(r'^[A-Z][0-9][0-9A-Z]?(\.[0-9A-Z]{1,4})?$').hasMatch(code);
          final isCpt = RegExp(r'^[0-9]{4,5}[A-Z]?$').hasMatch(code);

          if (isIcd || isCpt) {
            final tag = isIcd ? 'ICD-10' : 'CPT';
            final tagColor = isIcd ? const Color(0xFF2563EB) : const Color(0xFF7C3AED);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Nx.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Nx.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: tagColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Nx.ink,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Nx.secondary,
                        ),
                      ),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14, color: Nx.muted),
                    tooltip: 'Copy code $code',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Code $code copied.')),
                      );
                    },
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SelectableText(
              t,
              style: const TextStyle(
                color: Nx.ink,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          );
        }),
      ],
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

  Widget _loadFailedState() {
    return NxEmptyState(
      icon: Icons.cloud_off,
      title: "Couldn't load the note",
      hint: 'Check your connection and try again.',
      action: FilledButton.icon(
        onPressed: _loadingNote ? null : () => _loadNote(force: true),
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Retry'),
      ),
    );
  }

  Widget _busyState(Visit visit) {
    final count = visit.recordingCount;
    final isUploading = visit.status == VisitStatus.pendingUpload;
    final title = isUploading ? 'Securing audio…' : 'AI Generating Clinical Note';
    final msg = isUploading
        ? 'Your audio recording is queued to upload. AI note generation will begin immediately upon upload.'
        : 'AI is analyzing ${count > 1 ? '$count consultation recordings' : 'consultation audio'} and structuring the SOAP note (Subjective, Objective, Assessment, Plan)…';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Nx.s5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Nx.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Nx.primary, size: 32),
            ),
            const SizedBox(height: Nx.s4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Nx.ink,
              ),
            ),
            const SizedBox(height: Nx.s2),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: Nx.secondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: Nx.s5),
            const SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: Nx.border,
                valueColor: AlwaysStoppedAnimation<Color>(Nx.accent),
              ),
            ),
            const SizedBox(height: Nx.s5),
            OutlinedButton.icon(
              onPressed: _loadingNote ? null : () => _loadNote(force: true),
              icon: _loadingNote
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Check for updates'),
            ),
          ],
        ),
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
