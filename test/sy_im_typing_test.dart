import 'package:flutter_test/flutter_test.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

void main() {
  test('typing status from OpenIM platforms matches Android/iOS semantics', () {
    final on = SyImTypingStatus.fromOpenIm(
      userId: 'u2',
      conversationId: 'si_u1_u2',
      platformIds: [2, 5],
    );
    expect(on.typing, isTrue);
    expect(on.platformIds, [2, 5]);
    expect(on.userId, 'u2');
    final off = SyImTypingStatus.fromOpenIm(userId: 'u2', conversationId: 'c');
    expect(off.typing, isFalse);
    expect(off.platformIds, isEmpty);
  });
}
