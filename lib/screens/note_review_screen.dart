import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/clinical_models.dart';
import '../services/clinical_service.dart';
import '../status_ui.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';

/// The clinician's review of a scribe-completed note:
///   read -> small edits yourself  OR  request changes (comment to scribe)
///   OR  approve as final.
/// No "generate transcript" action; no EHR upload (the scribe does that).
///
/// The note itself is the page: state and timing sit in the header, the scribe
/// conversation collapses above the note, and the only persistent chrome is the
/// action bar — so the clinician reads a document, not a dashboard.
class NoteReviewScreen extends StatefulWidget {
  final String visitId;
  const NoteReviewScreen({super.key, required this.visitId});

  @override
  State<NoteReviewScreen> createState() => _NoteReviewScreenState();
}

class _NoteReviewScreenState extends State<NoteReviewScreen> {
  bool _editing = false;
  // The sentence/phrase the doctor has highlighted in the note, so a change
  // request can be anchored to exactly that text for the scribe.
  String _selected = '';
  late TextEditingController _editCtrl;

  // The note body is fetched on open (the list only carries status). While the
  // fetch is in flight we show a loader; if it can't be loaded we offer a retry.
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
      // A hard failure: the fetch finished but no note body arrived (offline,
      // server error, …). Show a retry instead of re-fetching forever. A
      // still-with-scribe note never reaches this path — it shows the busy
      // state — so we don't need to special-case status here.
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
              if (visit.note != null)
                HeaderIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Reload note',
                  busy: _loadingNote,
                  onTap: _loadingNote ? null : _loadNote,
                ),
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

    // The note is ready on the server but its body hasn't loaded onto the
    // device yet (still fetching, or the fetch failed). Show a loader / retry
    // rather than the "with scribe" copy, which would be misleading. Kick off
    // the fetch from here so it also recovers if the note is ever dropped (e.g.
    // a scribe revision invalidated the cached body). The _loadingNote guard
    // stops this from re-firing every rebuild.
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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s4, Nx.s4, Nx.s8),
            children: [
              if (note.feedback.isNotEmpty) ...[
                _feedbackHistory(note),
                const SizedBox(height: Nx.s3),
              ],
              _noteCard(note, reviewable),
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

  // --- The note itself ----------------------------------------------------

  Widget _noteCard(ClinicalNote note, bool reviewable) {
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
            padding: EdgeInsets.symmetric(vertical: Nx.s4),
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
          else
            SelectableText(note.content,
                onSelectionChanged: (sel, _) => setState(
                    () => _selected = sel.textInside(note.content).trim()),
                style: const TextStyle(
                    color: Nx.secondary, height: 1.6, fontSize: 14.5)),
          if (!_editing && reviewable)
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

  void _startEditing(ClinicalNote note) {
    _editCtrl.text = note.content;
    setState(() => _editing = true);
  }

  /// The back-and-forth with the scribe, newest last — a conversation thread
  /// rather than a flat bullet list, so it's clear these were your requests.
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

  // --- Non-note states ----------------------------------------------------

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
      VisitStatus.pendingUpload => 'Waiting to upload the recording…',
      VisitStatus.withScribe => 'With the scribe — completing the note…',
      VisitStatus.changesRequested =>
        'Sent back to the scribe with your comments…',
      _ => 'Working…',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Nx.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Nx.rLg),
              ),
              child: Icon(s.icon, size: 30, color: s.color),
            ),
            const SizedBox(height: Nx.s4),
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Nx.ink, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: Nx.s1),
            const Text('This updates automatically.',
                style: TextStyle(color: Nx.muted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  // --- Action bars --------------------------------------------------------

  Widget _actionBar({required Widget child}) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(Nx.s4),
        decoration: BoxDecoration(
          color: Nx.card,
          border: const Border(top: BorderSide(color: Nx.border)),
          boxShadow: Nx.cardShadow,
        ),
        child: child,
      ),
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
                  // Approving is the app's other green action: it completes the
                  // note the same way recording completes the encounter.
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
      child: const Row(
        children: [
          Icon(Icons.verified, color: Nx.accent),
          SizedBox(width: Nx.s3),
          Flexible(
            child: Text(
              'Approved as final. The scribe will upload it to the EHR.',
              style: TextStyle(color: Nx.secondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // --- Dialogs ------------------------------------------------------------

  Future<void> _promptChanges(
      BuildContext context, ClinicalService svc, Visit visit,
      {String quote = ''}) async {
    final controller = TextEditingController();
    final comment = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            quote.isEmpty ? 'Request changes' : 'Comment on selection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quote.isNotEmpty) ...[
              Container(
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
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: quote.isEmpty
                    ? 'What should the scribe change? e.g. "Add the BP reading to Objective."'
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
      // Anchor the comment to the highlighted sentence so the scribe knows
      // exactly what to change.
      final message = quote.isEmpty ? comment : 'Re: "$quote"\n$comment';
      await svc.requestChanges(visit.id, message);
      if (mounted) setState(() => _selected = '');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sent to the scribe with your comments.')));
      }
    }
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
