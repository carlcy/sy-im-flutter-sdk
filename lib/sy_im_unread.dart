import 'dart:async';

import 'openim_adapter.dart';

/// 未读变化。`totalUnread` 是全部会话未读总数，`conversations` 是当前缓存的会话列表。
class SyImUnreadUpdate {
  const SyImUnreadUpdate({
    required this.totalUnread,
    required this.conversations,
  });

  final int totalUnread;
  final List<SyImConversation> conversations;
}

/// 把 OpenIM 的总未读、会话变更和本地标已读收成同一次快照。
class SyImUnreadHub {
  final _controller = StreamController<SyImUnreadUpdate>.broadcast();

  Stream<SyImUnreadUpdate> get changes => _controller.stream;

  SyImUnreadUpdate latest = const SyImUnreadUpdate(
    totalUnread: 0,
    conversations: [],
  );

  int get totalUnread => latest.totalUnread;
  List<SyImConversation> get conversations => latest.conversations;

  void applyFullList(List<SyImConversation> list, {int? total}) {
    _set(
      conversations: List<SyImConversation>.unmodifiable(list),
      totalUnread: total ?? sumUnread(list),
    );
  }

  /// 会话变更回调通常只带变化的那几条，按 id 合并进现有列表。
  void applyDelta(List<SyImConversation> delta) {
    final merged = mergeConversations(latest.conversations, delta);
    _set(
      conversations: List<SyImConversation>.unmodifiable(merged),
      totalUnread: sumUnread(merged),
    );
  }

  void applyTotal(int total) {
    _set(conversations: latest.conversations, totalUnread: total);
  }

  void markConversationRead(String conversationId) {
    final next = [
      for (final conversation in latest.conversations)
        if (conversation.conversationId == conversationId)
          conversation.copyWith(unreadCount: 0)
        else
          conversation,
    ];
    _set(
      conversations: List<SyImConversation>.unmodifiable(next),
      totalUnread: sumUnread(next),
    );
  }

  void clear() {
    _set(conversations: const [], totalUnread: 0);
  }

  void _set({
    required List<SyImConversation> conversations,
    required int totalUnread,
  }) {
    latest = SyImUnreadUpdate(
      totalUnread: totalUnread,
      conversations: conversations,
    );
    if (!_controller.isClosed) {
      _controller.add(latest);
    }
  }
}

int sumUnread(List<SyImConversation> conversations) {
  var total = 0;
  for (final conversation in conversations) {
    total += conversation.unreadCount;
  }
  return total;
}

List<SyImConversation> mergeConversations(
  List<SyImConversation> current,
  List<SyImConversation> incoming,
) {
  final byId = <String, SyImConversation>{
    for (final conversation in current)
      conversation.conversationId: conversation,
  };
  for (final conversation in incoming) {
    byId[conversation.conversationId] = conversation;
  }
  return byId.values.toList();
}
