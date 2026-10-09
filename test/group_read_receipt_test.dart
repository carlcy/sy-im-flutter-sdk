import 'package:flutter_test/flutter_test.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

SyImGroupReadInfo info(String id, int read, [List<String> readers = const []]) =>
    SyImGroupReadInfo(
        clientMsgId: id, hasReadCount: read, unreadCount: 5 - read, readUserIds: readers);

void main() {
  test('tracker: first sight is the baseline, then count growth / new readers fire', () {
    final t = SyImGroupReadTracker();
    expect(t.update(info('m1', 1, ['u1'])).changed, isFalse);
    expect(t.update(info('m1', 1, ['u1'])).changed, isFalse);
    final c = t.update(info('m1', 2, ['u1', 'u2']));
    expect(c.changed, isTrue);
    expect(c.newReaders, ['u2']);
    // Count only (no roster) still counts as a change.
    final d = t.update(info('m1', 3, ['u1', 'u2']));
    expect(d.changed, isTrue);
    expect(d.newReaders, isEmpty);
    // A lower count (stale read) is not a change and does not lower the baseline.
    expect(t.update(info('m1', 2)).changed, isFalse);
    expect(t.update(info('m1', 3)).changed, isFalse);
    t.forget('m1');
    expect(t.isTracking('m1'), isFalse);
  });

  test('watch: reports changed message ids and per-reader receipts', () async {
    final state = <String, SyImGroupReadInfo>{
      'm1': info('m1', 0),
      'm2': info('m2', 1, ['u1']),
    };
    final events = <List<String>>[];
    final receipts = <List<SyImReadReceipt>>[];
    final w = SyImGroupReadWatch(
      conversationId: 'sg_123',
      clientMsgIds: ['m1', 'm2', ''],
      interval: Duration.zero,
      fetch: (cid, mid) async {
        expect(cid, 'sg_123');
        if (mid == 'bad') throw StateError('boom');
        return state[mid]!;
      },
      onChange: (_, changed, r) {
        events.add(changed);
        receipts.add(r);
      },
    );
    expect(w.clientMsgIds, ['m1', 'm2']);
    await w.check(); // baseline
    expect(events, isEmpty);

    state['m1'] = info('m1', 1, ['u2']);
    state['m2'] = info('m2', 2, ['u1', 'u2']);
    w.addMessages(['bad']);
    await w.check();
    expect(events.single, ['m1', 'm2']);
    expect(receipts.single, [
      const SyImReadReceipt(
          conversationId: 'sg_123', userId: 'u2', groupId: '123', msgIds: ['m1', 'm2']),
    ]);

    await w.check(); // nothing new
    expect(events.length, 1);

    var cancelled = 0;
    final w2 = SyImGroupReadWatch(
        conversationId: 'sg_1',
        clientMsgIds: ['m1'],
        interval: Duration.zero,
        fetch: (_, __) async => info('m1', 4),
        onChange: (_, __, ___) => events.add(['x']),
        onCancel: (_) => cancelled++);
    w2.cancel();
    w2.cancel();
    await w2.check();
    expect(cancelled, 1);
    expect(w2.isCancelled, isTrue);
    expect(events.length, 1);
  });

  test('watchGroupReadReceipts requires login', () async {
    SyIm.reset();
    final engine = await SyIm.create(appId: 'a', apiBaseUrl: 'http://x');
    addTearDown(SyIm.reset);
    expect(
        () => engine.watchGroupReadReceipts(conversationId: 'sg_1', clientMsgIds: ['m1']),
        throwsStateError);
  });
}
