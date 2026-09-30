import 'package:flutter_test/flutter_test.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

void main() {
  test('conversation unread and read receipt models keep their fields', () {
    const conversation = SyImConversation(
      conversationId: 'si_u1_u2',
      userId: 'u2',
      unreadCount: 3,
      latestText: 'hi',
    );
    const receipt = SyImReadReceipt(userId: 'u2', msgIds: ['m1'], readTime: 10);
    const application = SyImFriendApplication(
      fromUserId: 'u2',
      toUserId: 'u1',
      handleResult: 0,
    );
    const group = SyImGroup(groupId: 'g1', groupName: '项目群', memberCount: 2);

    expect(conversation.unreadCount, 3);
    expect(receipt.msgIds, ['m1']);
    expect(application.handleResult, 0);
    expect(group.memberCount, 2);
  });
}
