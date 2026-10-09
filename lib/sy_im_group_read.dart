import 'dart:async';

import 'openim_adapter.dart';

/// Group read-receipt event for Flutter.
///
/// Android / iOS get group receipts pushed by their OpenIM native SDKs
/// (`onRecvGroupReadReceipt`). flutter_openim_sdk 3.8.3 has no such listener, so
/// Flutter watches the messages the app cares about: it re-reads their group read
/// info (OpenIM count + optional control-plane who-read roster) when the group
/// conversation changes and on a timer, and reports only what changed.

/// What changed for one message since the last check.
class SyImGroupReadChange {
  const SyImGroupReadChange({
    required this.clientMsgId,
    required this.changed,
    this.newReaders = const [],
  });

  final String clientMsgId;

  /// Read count or reader list grew.
  final bool changed;

  /// Readers not seen before (empty when only the count is known).
  final List<String> newReaders;
}

/// Pure diff logic: the first observation of a message is the baseline (no event),
/// afterwards an event fires when the read count grows or new readers appear.
class SyImGroupReadTracker {
  final Map<String, int> _count = {};
  final Map<String, Set<String>> _readers = {};

  bool isTracking(String clientMsgId) => _count.containsKey(clientMsgId);

  SyImGroupReadChange update(SyImGroupReadInfo info) {
    final id = info.clientMsgId;
    final readers = info.readUserIds.where((u) => u.isNotEmpty).toList();
    if (!_count.containsKey(id)) {
      _count[id] = info.hasReadCount;
      _readers[id] = readers.toSet();
      return SyImGroupReadChange(clientMsgId: id, changed: false);
    }
    final known = _readers[id]!;
    final fresh = readers.where((u) => !known.contains(u)).toList();
    final grew = info.hasReadCount > _count[id]!;
    if (info.hasReadCount > _count[id]!) _count[id] = info.hasReadCount;
    known.addAll(fresh);
    return SyImGroupReadChange(
      clientMsgId: id,
      changed: grew || fresh.isNotEmpty,
      newReaders: fresh,
    );
  }

  void forget(String clientMsgId) {
    _count.remove(clientMsgId);
    _readers.remove(clientMsgId);
  }
}

typedef SyImGroupReadFetch = Future<SyImGroupReadInfo> Function(
    String conversationId, String clientMsgId);

/// Callback with the same meaning as Android `onRecvGroupReadReceipt(conversationId)`
/// and iOS `onRecvGroupReadReceipt(groupId, msgIds)`.
typedef SyImGroupReadReceiptCallback = void Function(
    String conversationId, String? groupId, List<String> msgIds);

/// Watches some messages of one group conversation. Create it with
/// `SyImEngine.watchGroupReadReceipts`; call [cancel] when the screen goes away.
class SyImGroupReadWatch {
  SyImGroupReadWatch({
    required this.conversationId,
    required List<String> clientMsgIds,
    required SyImGroupReadFetch fetch,
    required void Function(SyImGroupReadWatch watch, List<String> changedMsgIds,
            List<SyImReadReceipt> receipts)
        onChange,
    Duration interval = const Duration(seconds: 5),
    void Function(SyImGroupReadWatch watch)? onCancel,
  })  : _fetch = fetch,
        _onChange = onChange,
        _onCancel = onCancel {
    _msgIds.addAll(clientMsgIds.where((m) => m.isNotEmpty));
    if (interval > Duration.zero) {
      _timer = Timer.periodic(interval, (_) => unawaited(check()));
    }
  }

  final String conversationId;
  final List<String> _msgIds = [];
  final SyImGroupReadFetch _fetch;
  final void Function(SyImGroupReadWatch, List<String>, List<SyImReadReceipt>)
      _onChange;
  final void Function(SyImGroupReadWatch)? _onCancel;
  final SyImGroupReadTracker _tracker = SyImGroupReadTracker();
  Timer? _timer;
  bool _cancelled = false;
  bool _busy = false;

  List<String> get clientMsgIds => List.unmodifiable(_msgIds);
  bool get isCancelled => _cancelled;

  /// Start watching more messages (e.g. ones just sent).
  void addMessages(List<String> clientMsgIds) {
    for (final m in clientMsgIds) {
      if (m.isNotEmpty && !_msgIds.contains(m)) _msgIds.add(m);
    }
  }

  void removeMessages(List<String> clientMsgIds) {
    for (final m in clientMsgIds) {
      _msgIds.remove(m);
      _tracker.forget(m);
    }
  }

  /// Re-read every watched message once. Overlapping calls are skipped; a failed
  /// fetch for one message does not stop the others.
  Future<void> check() async {
    if (_cancelled || _busy) return;
    _busy = true;
    try {
      final changed = <String>[];
      final perMessage = <MapEntry<String, List<String>>>[];
      for (final id in List<String>.from(_msgIds)) {
        SyImGroupReadInfo info;
        try {
          info = await _fetch(conversationId, id);
        } catch (_) {
          continue;
        }
        if (_cancelled) return;
        final c = _tracker.update(info.clientMsgId.isEmpty
            ? SyImGroupReadInfo(
                clientMsgId: id,
                hasReadCount: info.hasReadCount,
                unreadCount: info.unreadCount,
                readUserIds: info.readUserIds,
                source: info.source)
            : info);
        if (!c.changed) continue;
        changed.add(id);
        if (c.newReaders.isNotEmpty) perMessage.add(MapEntry(id, c.newReaders));
      }
      if (changed.isNotEmpty) {
        _onChange(this, changed,
            SyImReadReceipts.perReader(conversationId, perMessage));
      }
    } finally {
      _busy = false;
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    _onCancel?.call(this);
  }
}
