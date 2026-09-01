import 'api_client.dart';

/// A clinician's reusable note template. Mirrors the server's
/// `clinician_note_templates` row (see the API: GET/POST/DELETE
/// `/settings/clinician-templates`): `{ id, name, icon, color, accent, content }`.
class NoteTemplate {
  final String id;
  final String name;
  final String icon; // emoji glyph shown on the card
  final String color; // hex card background, e.g. #E3F2FD
  final String accent; // hex accent, e.g. #1565C0
  final String content;

  const NoteTemplate({
    required this.id,
    required this.name,
    this.icon = '📝',
    this.color = '#EEF2FF',
    this.accent = '#2563EB',
    this.content = '',
  });

  NoteTemplate copyWith({
    String? name,
    String? icon,
    String? color,
    String? accent,
    String? content,
  }) =>
      NoteTemplate(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        accent: accent ?? this.accent,
        content: content ?? this.content,
      );

  factory NoteTemplate.fromJson(Map<String, dynamic> m) => NoteTemplate(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        icon: (m['icon'] ?? '📝').toString(),
        color: (m['color'] ?? '#EEF2FF').toString(),
        accent: (m['accent'] ?? '#2563EB').toString(),
        content: (m['content'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'accent': accent,
        'content': content,
      };
}

/// The seven fixed section headers the live server's AI draft uses
/// (buildAnthropicNotePrompt), so a clinician's starting template lines up with
/// the notes they actually review and lock.
const _soapSkeleton = 'CHIEF COMPLAINT:\n\n\n'
    'HISTORY OF PRESENT ILLNESS (HPI):\n\n\n'
    'PHYSICAL EXAMINATION (PE):\n\n\n'
    'IMAGING:\n\n\n'
    'ASSESSMENT & PLAN (A&P):\n\n\n'
    'ICD-10 CODES:\n\n\n'
    'E&M CODE:\n';

/// Built-in defaults used as the on-device fallback until the server is reached
/// (mirrors the backend's own first-access seed: New Patient, Follow-Up, Virtual
/// Visit, Other). Replaced by the server's real set once it responds.
const defaultClinicianTemplates = <NoteTemplate>[
  NoteTemplate(
      id: 'new-patient',
      name: 'New Patient Visit',
      icon: '🆕',
      color: '#E3F2FD',
      accent: '#1565C0',
      content: _soapSkeleton),
  NoteTemplate(
      id: 'follow-up',
      name: 'Follow-Up Visit',
      icon: '🔁',
      color: '#E8F5E9',
      accent: '#2E7D32',
      content: _soapSkeleton),
  NoteTemplate(
      id: 'virtual-visit',
      name: 'Virtual Visit',
      icon: '💻',
      color: '#EDE7F6',
      accent: '#5E35B1',
      content: _soapSkeleton),
  NoteTemplate(
      id: 'other',
      name: 'Other',
      icon: '📝',
      color: '#FFF3E0',
      accent: '#EF6C00',
      content: _soapSkeleton),
];

/// Clinician note templates against the Notenra REST API.
///
///   GET    /settings/clinician-templates                 -> { templates:[...] }
///   POST   /settings/clinician-templates  body {templates} -> { templates:[...] }
///   DELETE /settings/clinician-templates/:id              -> { templates:[...] }
///
/// POST replaces the caller's whole set (server deletes + re-inserts), so a save
/// always sends the full list.
class ClinicianTemplatesApi {
  final ApiClient api;
  ClinicianTemplatesApi(this.api);

  Future<List<NoteTemplate>> list() async {
    final res = await api.dio.get('/settings/clinician-templates');
    return _parse(res.data);
  }

  Future<List<NoteTemplate>> save(List<NoteTemplate> templates) async {
    final res = await api.dio.post('/settings/clinician-templates', data: {
      'templates': [for (final t in templates) t.toJson()],
    });
    return _parse(res.data);
  }

  Future<List<NoteTemplate>> delete(String id) async {
    final res = await api.dio.delete('/settings/clinician-templates/$id');
    return _parse(res.data);
  }

  List<NoteTemplate> _parse(Object? data) {
    final raw = data is Map ? (data['templates'] ?? data['data']) : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => NoteTemplate.fromJson(m.cast<String, dynamic>()))
        .toList();
  }
}
