import 'package:flutter_test/flutter_test.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

void main() {
  const data =
      '{"sy":"reaction_lite","action":"add","emoji":"👍","target":{"seq":12,"clientMsgId":"c1","senderId":"u2"}}';

  test('parses server reaction payload', () {
    final r = SyImReaction.parse(data)!;
    expect(r.emoji, '👍');
    expect(r.added, isTrue);
    expect(r.targetClientMsgId, 'c1');
    expect(r.targetSeq, 12);
    expect(r.targetSenderId, 'u2');
    expect(SyImReaction.parse(data.replaceAll('"add"', '"remove"'))!.added,
        isFalse);
  });

  test('ignores other custom messages', () {
    expect(SyImReaction.parse(null), isNull);
    expect(SyImReaction.parse('not json'), isNull);
    expect(SyImReaction.parse('{"sy":"call_invite"}'), isNull);
    expect(SyImReaction.parse('{"sy":"reaction_lite","emoji":""}'), isNull);
  });

  test('request body matches backend ReactReq', () {
    final group = SyImReaction.requestBody(
        appId: 'app',
        fromUserId: 'u1',
        emoji: '👍',
        groupId: 'g1',
        targetClientMsgId: 'c1',
        targetSenderId: 'u2',
        add: false);
    expect(group['groupId'], 'g1');
    expect(group.containsKey('toUserId'), isFalse);
    expect(group['action'], 'remove');
    expect(group.containsKey('targetSeq'), isFalse);
    final single = SyImReaction.requestBody(
        appId: 'app',
        fromUserId: 'u1',
        emoji: '❤️',
        toUserId: 'u3',
        targetSeq: 7);
    expect(single['toUserId'], 'u3');
    expect(single['targetSeq'], 7);
    expect(single['action'], 'add');
  });
}
