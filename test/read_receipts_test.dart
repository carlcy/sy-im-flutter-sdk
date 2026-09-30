import 'package:flutter_test/flutter_test.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

/// 与 Android ReadReceiptsTest、iOS SyImReadReceiptsTests 相同的期望。
void main() {
  test('conversation ids', () {
    expect(SyImReadReceipts.singleConversationId('b', 'a'), 'si_a_b');
    expect(SyImReadReceipts.singleConversationId('', 'a'), '');
    expect(SyImReadReceipts.groupConversationId('g1'), 'sg_g1');
    expect(SyImReadReceipts.groupIdOf('sg_g1'), 'g1');
    expect(SyImReadReceipts.groupIdOf('si_a_b'), isNull);
  });

  test('per-message group receipt becomes per-reader', () {
    final out = SyImReadReceipts.perReader('sg_g1', const [
      MapEntry('m1', ['u2', 'u3']),
      MapEntry('m2', ['u2']),
      MapEntry('', ['u9']),
    ]);
    expect(out.length, 2);
    expect(
        out[0],
        const SyImReadReceipt(
            conversationId: 'sg_g1',
            userId: 'u2',
            groupId: 'g1',
            msgIds: ['m1', 'm2']));
    expect(out[1].msgIds, ['m1']);
    expect(out[0].isGroup, isTrue);
    expect(
        const SyImReadReceipt(
            conversationId: 'si_a_b', userId: 'a', msgIds: ['m']).isGroup,
        isFalse);
  });

  test('merge prefers OpenIM then roster', () {
    final a = SyImReadReceipts.merge(
        clientMsgId: 'm1',
        hasReadCount: 2,
        unreadCount: 3,
        openImReaders: ['u2', 'u3'],
        roster: ['u9']);
    expect(a.source, SyImGroupReadInfo.sourceOpenIm);
    expect(a.readUserIds, ['u2', 'u3']);
    final b = SyImReadReceipts.merge(
        clientMsgId: 'm1',
        hasReadCount: 1,
        unreadCount: 3,
        roster: ['u2', 'u3']);
    expect(b.source, SyImGroupReadInfo.sourceControlPlane);
    expect(b.hasReadCount, 2);
    expect(b.unreadCount, 2);
    final c = SyImReadReceipts.merge(
        clientMsgId: 'm1', hasReadCount: 4, unreadCount: 0);
    expect(c.source, SyImGroupReadInfo.sourceNone);
    expect(c.hasReadCount, 4);
    expect(c.readUserIds, isEmpty);
  });

  test('who-read roster dedupes and request body matches server', () {
    final list = [
      {'readerUid': 'u3', 'seq': 7},
      {'readerUid': 'u2'},
      {'readerUid': 'u3'},
      {'x': 1},
    ];
    expect(SyImReadReceipts.readersFromWhoRead(list), ['u3', 'u2']);
    expect(ImControlPlane.whoReadBody('app', 'sg_g1', 7),
        {'appId': 'app', 'conversationId': 'sg_g1', 'seq': 7});
    expect(ImControlPlane.whoReadBody('app', 'sg_g1', 0).containsKey('seq'),
        isFalse);
  });
}
