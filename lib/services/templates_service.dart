import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/clinician_templates.dart';
import '../secure_store.dart';

/// Coordinates the clinician's note templates over the server, with an encrypted
/// on-device cache so the feature works while offline — or while the server's
/// `/settings/clinician-templates` endpoint is unavailable (it currently 500s).
///
/// The server is the source of truth; the local cache is a fallback and a
/// hold-buffer. When a save can't reach the server the edit is kept locally and
/// [pendingSync] is set; the next [load]/save pushes the held changes.
class TemplatesService extends ChangeNotifier {
  static const _secure = SecureStore();
  static const _cacheKey = 'clinician_templates_cache';
  static const _dirtyKey = 'clinician_templates_dirty';

  final ClinicianTemplatesApi api;
  TemplatesService(this.api);

  List<NoteTemplate> _templates = const [];
  List<NoteTemplate> get templates => _templates;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// True when local edits haven't yet reached the server (offline / 500).
  bool _pendingSync = false;
  bool get pendingSync => _pendingSync;

  /// True once the server answered this session, so the UI can distinguish
  /// server truth from the on-device fallback.
  bool _serverReached = false;
  bool get serverReached => _serverReached;

  Future<void> load() async {
    _loading = true;
    _error = null;
    // Show cached/default templates immediately so the screen is never empty.
    if (_templates.isEmpty) {
      _templates = (await _readCache()) ?? defaultClinicianTemplates;
    }
    notifyListeners();
    try {
      if (await _isDirty()) {
        // Local edits are waiting — push them and adopt the server's echo.
        final saved = await api.save(_templates);
        if (saved.isNotEmpty) _templates = saved;
        await _clearDirty();
      } else {
        final server = await api.list();
        if (server.isNotEmpty) _templates = server;
      }
      _serverReached = true;
      _pendingSync = false;
      await _writeCache(_templates);
      _error = null;
    } catch (_) {
      _serverReached = false;
      _pendingSync = await _isDirty();
      _error = 'Showing your device copy — the templates server is unavailable.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Persist the full set (optimistic locally, then push). POST replaces the
  /// whole server-side set, so we always send the entire list.
  Future<void> saveAll(List<NoteTemplate> next) async {
    _templates = next;
    await _writeCache(next);
    _error = null;
    notifyListeners();
    try {
      final saved = await api.save(next);
      if (saved.isNotEmpty) _templates = saved;
      _serverReached = true;
      _pendingSync = false;
      await _clearDirty();
      await _writeCache(_templates);
    } catch (_) {
      _pendingSync = true;
      await _markDirty();
      _error = 'Saved on this device — will sync when the server is available.';
    }
    notifyListeners();
  }

  /// Insert or update a single template, then persist the whole set.
  Future<void> upsert(NoteTemplate t) {
    final next = [..._templates];
    final i = next.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      next[i] = t;
    } else {
      next.add(t);
    }
    return saveAll(next);
  }

  Future<void> deleteTemplate(String id) async {
    _templates = _templates.where((t) => t.id != id).toList();
    await _writeCache(_templates);
    _error = null;
    notifyListeners();
    try {
      final remaining = await api.delete(id);
      if (remaining.isNotEmpty) _templates = remaining;
      _serverReached = true;
      _pendingSync = false;
      await _writeCache(_templates);
    } catch (_) {
      _pendingSync = true;
      await _markDirty();
      _error = 'Removed on this device — will sync when the server is available.';
    }
    notifyListeners();
  }

  Future<void> resetToDefaults() => saveAll(defaultClinicianTemplates);

  // --- encrypted local cache ---
  Future<List<NoteTemplate>?> _readCache() async {
    final raw = await _secure.read(key: _cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => NoteTemplate.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeCache(List<NoteTemplate> t) => _secure.write(
      key: _cacheKey, value: jsonEncode([for (final x in t) x.toJson()]));

  Future<bool> _isDirty() async =>
      (await _secure.read(key: _dirtyKey)) == '1';
  Future<void> _markDirty() => _secure.write(key: _dirtyKey, value: '1');
  Future<void> _clearDirty() => _secure.delete(key: _dirtyKey);
}
