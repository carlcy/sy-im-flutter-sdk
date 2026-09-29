import 'package:flutter_test/flutter_test.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

void main() {
  test('sdk version is 0.5.0', () {
    expect(syImSdkVersion, '0.5.0');
    expect(syImAtAllUserId, 'AtAllTag');
    expect(SyImRecvOpt.notReceive, 1);
  });

  test('unread hub follows total, conversation delta, and mark read', () async {
    final hub = SyImUnreadHub();
    final events = <SyImUnreadUpdate>[];
    final sub = hub.changes.listen(events.add);
    addTearDown(sub.cancel);

    hub.applyFullList([
      const SyImConversation(conversationId: 'a', unreadCount: 2),
      const SyImConversation(conversationId: 'b', unreadCount: 1),
    ]);
    hub.applyTotal(9);
    hub.applyDelta([
      const SyImConversation(
        conversationId: 'a',
        unreadCount: 4,
        showName: '甲',
      ),
      const SyImConversation(conversationId: 'c', unreadCount: 3),
    ]);
    hub.markConversationRead('a');
    await Future<void>.delayed(Duration.zero);

    expect(events.map((event) => event.totalUnread).toList(), [3, 9, 8, 4]);
    final latest = events.last;
    expect(
      latest.conversations.map((c) => c.conversationId).toList(),
      ['a', 'b', 'c'],
    );
    expect(
      latest.conversations
          .firstWhere((c) => c.conversationId == 'a')
          .unreadCount,
      0,
    );
    expect(
      latest.conversations
          .firstWhere((c) => c.conversationId == 'b')
          .unreadCount,
      1,
    );
    expect(latest.conversations.first.showName, '甲');
  });

  test('full refresh can replace the sdk total without dropping fields', () {
    final hub = SyImUnreadHub();
    hub.applyFullList([
      const SyImConversation(
        conversationId: 'a',
        unreadCount: 2,
        isPinned: true,
        draftText: '草稿',
        recvMsgOpt: SyImRecvOpt.onlineOnly,
      ),
    ], total: 2);
    hub.applyFullList([
      const SyImConversation(
          conversationId: 'a', unreadCount: 0, isPinned: true),
    ], total: 0);
    expect(hub.totalUnread, 0);
    expect(hub.conversations.single.isPinned, isTrue);
    expect(hub.conversations.single.unreadCount, 0);
  });

  test('new message models keep recall, search, typing, and group read fields',
      () {
    const revoked = SyImRevokedMessage(clientMsgId: 'm1', revokerId: 'u2');
    const hit = SyImSearchHit(
      conversationId: 'c1',
      clientMsgId: 'm1',
      text: 'hello',
    );
    const typing = SyImTypingStatus(
      userId: 'u2',
      conversationId: 'c1',
      typing: true,
    );
    const read = SyImGroupReadInfo(hasReadCount: 2, unreadCount: 3);
    const profile = SyImUserProfile(userId: 'u1', ex: '{"vip":1}');
    const blocked = SyImBlacklistUser(userId: 'u9');

    expect(revoked.clientMsgId, 'm1');
    expect(hit.text, 'hello');
    expect(typing.typing, isTrue);
    expect(read.readUserIds, isEmpty);
    expect(read.hasReadCount, 2);
    expect(profile.ex, '{"vip":1}');
    expect(blocked.userId, 'u9');
  });
}
