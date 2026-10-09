/// SY IM Flutter SDK
///
/// 与 RTC 相同的 AppID 模型：`SyIm.create(appId, apiBaseUrl)`。
/// **唯一实时路径**：Dart [OpenIMAdapter] → 官方 `flutter_openim_sdk` / `OpenIM.iMManager`。
/// 无遗留 `SyImFlutterSdkPlugin` MethodChannel。
/// IM Token / imApiAddr / imWsAddr 由开发者后端签发（`/api/server/im/token` 或用户态等价接口）。
library;

export 'openim_adapter.dart';
export 'im_control_plane.dart';
export 'sy_im_unread.dart';
export 'sy_im_group_read.dart';

import 'dart:async';
import 'dart:io';

import 'openim_adapter.dart';
import 'im_control_plane.dart';
import 'sy_im_unread.dart';
import 'sy_im_group_read.dart';

/// 与 Android / iOS IM SDK 对齐的版本号。
const String syImSdkVersion = '0.5.0';

/// `@所有人` 时放进 [SyImEngine.sendAtTextMessage] 的 `atUserIds`。
const String syImAtAllUserId = 'AtAllTag';

/// 会话免打扰。0 正常，1 不接收，2 仅在线接收。
class SyImRecvOpt {
  static const int normal = 0;
  static const int notReceive = 1;
  static const int onlineOnly = 2;
}

/// 全局入口，对齐 RTC `SyRtcEngine.create`。
class SyIm {
  SyIm._();

  static SyImEngine? _engine;

  /// 创建引擎。若提供 [imApiAddr]/[imWsAddr] 则立即 `initSDK`。
  static Future<SyImEngine> create({
    required String appId,
    required String apiBaseUrl,
    String? imApiAddr,
    String? imWsAddr,
    String? dataDir,
  }) async {
    if (_engine != null) {
      return _engine!;
    }
    final engine = SyImEngine._(appId: appId, apiBaseUrl: apiBaseUrl);
    await engine._prepare(
      imApiAddr: imApiAddr,
      imWsAddr: imWsAddr,
      dataDir: dataDir,
    );
    _engine = engine;
    return engine;
  }

  static Future<SyImEngine> init({
    required String appId,
    required String apiBaseUrl,
    String? imApiAddr,
    String? imWsAddr,
    String? dataDir,
  }) =>
      create(
        appId: appId,
        apiBaseUrl: apiBaseUrl,
        imApiAddr: imApiAddr,
        imWsAddr: imWsAddr,
        dataDir: dataDir,
      );

  static SyImEngine? get instance => _engine;

  /// For example / tests.
  static void reset() {
    _engine = null;
  }
}

class SyImEngine {
  SyImEngine._({required this.appId, required this.apiBaseUrl});

  final String appId;
  final String apiBaseUrl;

  OpenIMAdapter? _adapter;
  bool _initialized = false;
  bool _loggedIn = false;
  String? _currentUserId;
  String? _dataDir;
  final SyImUnreadHub _unread = SyImUnreadHub();

  /// 总未读和各会话未读。由总未读回调、会话变更、新消息和 markRead 推动。
  Stream<SyImUnreadUpdate> get unreadChanges => _unread.changes;

  /// 最近一次未读快照里的总数，不额外请求网络。
  int get totalUnread => _unread.totalUnread;

  void Function()? onConnectSuccess;
  void Function()? onConnecting;
  void Function(int? code, String? error)? onConnectFailed;
  void Function()? onKickedOffline;
  void Function()? onUserTokenExpired;
  void Function(String msgId, String fromUserId, String? groupId, String? text)?
      onRecvNewMessage;
  void Function(List<SyImReadReceipt> receipts)? onRecvC2CReadReceipt;

  /// 已读回执（三端统一名）。单聊来自 OpenIM 推送；群聊来自 [watchGroupReadReceipts]
  /// 发现的新已读者（需要控制面花名册才有成员 id）。与 [onRecvC2CReadReceipt] 同时回调。
  void Function(List<SyImReadReceipt> receipts)? onRecvReadReceipts;

  /// 群已读回执，与 Android `onRecvGroupReadReceipt(conversationId)`、
  /// iOS `onRecvGroupReadReceipt(groupId, msgIds)` 对应：被关注的群消息已读人数增加或出现新已读者时回调。
  /// flutter_openim_sdk 3.8.3 没有群回执推送，所以只覆盖 [watchGroupReadReceipts] 关注的消息。
  SyImGroupReadReceiptCallback? onRecvGroupReadReceipt;
  final List<SyImGroupReadWatch> _groupReadWatches = [];
  void Function(SyImRevokedMessage info)? onMessageRevoked;
  void Function(SyImTypingStatus status)? onTypingChanged;
  void Function(SyImUnreadUpdate update)? onUnreadChanged;
  void Function()? onConversationUpdated;

  Future<void> _prepare({
    String? imApiAddr,
    String? imWsAddr,
    String? dataDir,
  }) async {
    _dataDir = dataDir;
    if (imApiAddr != null &&
        imApiAddr.isNotEmpty &&
        imWsAddr != null &&
        imWsAddr.isNotEmpty) {
      await configureOpenIM(
        imApiAddr: imApiAddr,
        imWsAddr: imWsAddr,
        dataDir: dataDir,
      );
    }
  }

  /// 在拿到控制面 `imApiAddr`/`imWsAddr` 后初始化 OpenIM。
  Future<void> configureOpenIM({
    required String imApiAddr,
    required String imWsAddr,
    String? dataDir,
  }) async {
    final dir = dataDir ??
        _dataDir ??
        Directory.systemTemp.createTempSync('sy_im').path;
    _dataDir = dir;
    final adapter = OpenIMAdapter(imApiAddr: imApiAddr, imWsAddr: imWsAddr);
    adapter.onConnectSuccess = () => onConnectSuccess?.call();
    adapter.onConnecting = () => onConnecting?.call();
    adapter.onConnectFailed = (c, m) => onConnectFailed?.call(c, m);
    adapter.onKickedOffline = () => onKickedOffline?.call();
    adapter.onUserTokenExpired = () => onUserTokenExpired?.call();
    adapter.onRecvNewMessage = (id, from, gid, text) {
      onRecvNewMessage?.call(id, from, gid, text);
      unawaited(_syncUnreadFromSdk());
    };
    adapter.onRecvC2CReadReceipt = (receipts) {
      onRecvC2CReadReceipt?.call(receipts);
      onRecvReadReceipts?.call(receipts);
    };
    adapter.onMessageRevoked = (info) => onMessageRevoked?.call(info);
    adapter.onTypingChanged = (status) => onTypingChanged?.call(status);
    adapter.onTotalUnreadChanged = (total) {
      _publishUnread(() => _unread.applyTotal(total));
    };
    adapter.onConversationsChanged = (conversations) {
      _publishUnread(() => _unread.applyDelta(conversations));
      _checkGroupReadWatches(conversations.map((c) => c.conversationId));
    };
    adapter.onConversationUpdated = () => onConversationUpdated?.call();
    await adapter.initSdk(dataDir: dir);
    _adapter = adapter;
    _initialized = true;
  }

  Future<void> login({required String userId, required String token}) async {
    final a = _adapter;
    if (a == null || !_initialized) {
      throw StateError(
        'call configureOpenIM (imApiAddr/imWsAddr) before login',
      );
    }
    await a.login(userId: userId, token: token);
    _currentUserId = userId;
    _loggedIn = true;
    await _syncUnreadFromSdk();
  }

  Future<void> logout() async {
    for (final w in List<SyImGroupReadWatch>.from(_groupReadWatches)) {
      w.cancel();
    }
    await _adapter?.logout();
    _loggedIn = false;
    _currentUserId = null;
    _publishUnread(_unread.clear);
  }

  Future<String> sendTextMessage({
    String? toUserId,
    String? groupId,
    required String text,
  }) async {
    if (!_loggedIn) {
      throw StateError('login required');
    }
    if ((toUserId == null || toUserId.isEmpty) &&
        (groupId == null || groupId.isEmpty)) {
      throw ArgumentError('provide toUserId or groupId');
    }
    return _adapter!.sendTextMessage(
      toUserId: toUserId,
      groupId: groupId,
      text: text,
    );
  }

  Future<List<SyImConversation>> getConversations() async {
    final a = _adapter;
    if (a == null) return _unread.conversations;
    final list = await a.getConversations();
    _publishUnread(() => _unread.applyFullList(list));
    return list;
  }

  /// 标记会话已读。单聊会向对方发送已读回执，并立刻刷新未读。
  Future<void> markConversationAsRead({required String conversationId}) async {
    await _requireLoggedIn().markConversationAsRead(
      conversationId: conversationId,
    );
    _publishUnread(() => _unread.markConversationRead(conversationId));
    await _syncUnreadFromSdk();
  }

  /// 全部会话未读总数。单会话未读见 [SyImConversation.unreadCount]。
  Future<int> getTotalUnreadCount() {
    return _requireLoggedIn().getTotalUnreadCount();
  }

  Future<void> addFriend({required String userId, String reason = ''}) {
    return _requireLoggedIn().addFriend(userId: userId, reason: reason);
  }

  Future<List<SyImFriendApplication>> getFriendApplications({
    bool sentByMe = false,
  }) {
    return _requireLoggedIn().getFriendApplications(sentByMe: sentByMe);
  }

  Future<void> acceptFriendApplication({
    required String userId,
    String handleMsg = '',
  }) {
    return _requireLoggedIn().acceptFriendApplication(
      userId: userId,
      handleMsg: handleMsg,
    );
  }

  Future<void> refuseFriendApplication({
    required String userId,
    String handleMsg = '',
  }) {
    return _requireLoggedIn().refuseFriendApplication(
      userId: userId,
      handleMsg: handleMsg,
    );
  }

  Future<List<SyImFriend>> getFriends() {
    return _requireLoggedIn().getFriends();
  }

  Future<SyImGroup> createGroup({
    required String groupName,
    String groupId = '',
    List<String> memberUserIds = const [],
  }) {
    return _requireLoggedIn().createGroup(
      groupName: groupName,
      groupId: groupId,
      memberUserIds: memberUserIds,
    );
  }

  Future<void> inviteToGroup({
    required String groupId,
    required List<String> userIds,
    String reason = '',
  }) {
    return _requireLoggedIn().inviteToGroup(
      groupId: groupId,
      userIds: userIds,
      reason: reason,
    );
  }

  Future<void> kickGroupMembers({
    required String groupId,
    required List<String> userIds,
    String reason = '',
  }) {
    return _requireLoggedIn().kickGroupMembers(
      groupId: groupId,
      userIds: userIds,
      reason: reason,
    );
  }

  Future<void> joinGroup({required String groupId, String reason = ''}) {
    return _requireLoggedIn().joinGroup(groupId: groupId, reason: reason);
  }

  Future<void> quitGroup({required String groupId}) {
    return _requireLoggedIn().quitGroup(groupId: groupId);
  }

  Future<void> dismissGroup({required String groupId}) {
    return _requireLoggedIn().dismissGroup(groupId: groupId);
  }

  Future<List<SyImGroup>> getJoinedGroups() {
    return _requireLoggedIn().getJoinedGroups();
  }

  Future<List<SyImGroupMember>> getGroupMembers({
    required String groupId,
    int count = 100,
  }) {
    return _requireLoggedIn().getGroupMembers(groupId: groupId, count: count);
  }

  Future<void> revokeMessage({
    required String conversationId,
    required String clientMsgId,
  }) {
    return _requireLoggedIn().revokeMessage(
      conversationId: conversationId,
      clientMsgId: clientMsgId,
    );
  }

  Future<String> sendAtTextMessage({
    required String groupId,
    required String text,
    required List<String> atUserIds,
    Map<String, String> atNicknames = const {},
  }) {
    return _requireLoggedIn().sendAtTextMessage(
      groupId: groupId,
      text: text,
      atUserIds: atUserIds,
      atNicknames: atNicknames,
    );
  }

  Future<String> sendCustomMessage({
    String? toUserId,
    String? groupId,
    required String data,
    String customExtension = '',
    String description = '',
  }) {
    if ((toUserId == null || toUserId.isEmpty) &&
        (groupId == null || groupId.isEmpty)) {
      throw ArgumentError('provide toUserId or groupId');
    }
    return _requireLoggedIn().sendCustomMessage(
      toUserId: toUserId,
      groupId: groupId,
      data: data,
      customExtension: customExtension,
      description: description,
    );
  }

  Future<List<SyImSearchHit>> searchMessages({
    String? conversationId,
    required String keyword,
    int count = 20,
  }) {
    return _requireLoggedIn().searchMessages(
      conversationId: conversationId,
      keyword: keyword,
      count: count,
    );
  }

  Future<void> pinConversation({
    required String conversationId,
    required bool pinned,
  }) {
    return _requireLoggedIn().pinConversation(
      conversationId: conversationId,
      pinned: pinned,
    );
  }

  Future<void> setConversationDraft({
    required String conversationId,
    required String draft,
  }) {
    return _requireLoggedIn().setConversationDraft(
      conversationId: conversationId,
      draft: draft,
    );
  }

  Future<void> setConversationDoNotDisturb({
    required String conversationId,
    required int status,
  }) {
    return _requireLoggedIn().setConversationDoNotDisturb(
      conversationId: conversationId,
      status: status,
    );
  }

  /// 发送正在输入（OpenIM `changeInputStates`）。对端回调 [onTypingChanged]。
  Future<void> setTyping({
    required String conversationId,
    required bool typing,
  }) {
    return _requireLoggedIn().setTyping(
      conversationId: conversationId,
      typing: typing,
    );
  }

  /// 与 Android / iOS `sendTyping(conversationId, focus)` 同名，等同 [setTyping]。
  Future<void> sendTyping({
    required String conversationId,
    required bool focus,
  }) =>
      setTyping(conversationId: conversationId, typing: focus);

  /// 群消息已读概况，三端同名同义。OpenIM Flutter 绑定只给人数；传入带 userJwt 的 [controlPlane] 时，
  /// 再查控制面 who-read 花名册补已读成员（[SyImGroupReadInfo.source] == `controlPlane`）。
  /// 花名册只含调用过 [reportGroupMessagesRead] 的成员；查询失败时退回只有人数。
  Future<SyImGroupReadInfo> getGroupMessageReadInfo({
    required String conversationId,
    required String clientMsgId,
    ImControlPlane? controlPlane,
  }) async {
    final a = _requireLoggedIn();
    final info = await a.getGroupMessageReadInfo(
      conversationId: conversationId,
      clientMsgId: clientMsgId,
    );
    final seq = a.lastGroupReadSeq;
    final cp = controlPlane;
    if (cp == null ||
        (cp.userJwt ?? '').isEmpty ||
        seq < 0 ||
        info.readUserIds.isNotEmpty) {
      return info;
    }
    List<String>? roster;
    try {
      roster = await cp.whoRead(conversationId: conversationId, seq: seq);
    } catch (_) {
      roster = null;
    }
    return SyImReadReceipts.merge(
      clientMsgId: clientMsgId,
      hasReadCount: info.hasReadCount,
      unreadCount: info.unreadCount,
      roster: roster,
    );
  }

  /// 关注一个群会话里的消息（通常是自己发的），已读变化时回调 [onRecvGroupReadReceipt]，
  /// 有新已读者时再回调 [onRecvReadReceipts]。会话变化时立即检查，另按 [interval] 兜底轮询
  /// （`Duration.zero` 关闭轮询）。首次检查只记基线，不回调。不用时调用 [SyImGroupReadWatch.cancel]，
  /// [logout] 会全部取消。
  SyImGroupReadWatch watchGroupReadReceipts({
    required String conversationId,
    required List<String> clientMsgIds,
    ImControlPlane? controlPlane,
    Duration interval = const Duration(seconds: 5),
  }) {
    _requireLoggedIn();
    late final SyImGroupReadWatch watch;
    watch = SyImGroupReadWatch(
      conversationId: conversationId,
      clientMsgIds: clientMsgIds,
      interval: interval,
      fetch: (cid, mid) => getGroupMessageReadInfo(
          conversationId: cid, clientMsgId: mid, controlPlane: controlPlane),
      onChange: (w, changed, receipts) {
        onRecvGroupReadReceipt?.call(
            w.conversationId, SyImReadReceipts.groupIdOf(w.conversationId), changed);
        if (receipts.isNotEmpty) onRecvReadReceipts?.call(receipts);
      },
      onCancel: _groupReadWatches.remove,
    );
    _groupReadWatches.add(watch);
    unawaited(watch.check());
    return watch;
  }

  void _checkGroupReadWatches(Iterable<String> conversationIds) {
    final ids = conversationIds.toSet();
    for (final w in List<SyImGroupReadWatch>.from(_groupReadWatches)) {
      if (ids.contains(w.conversationId)) unawaited(w.check());
    }
  }

  /// 把本端已读的群消息 seq 写入控制面花名册（供其他成员的 [getGroupMessageReadInfo]）。
  Future<void> reportGroupMessagesRead({
    required ImControlPlane controlPlane,
    required String conversationId,
    required List<int> seqs,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) throw StateError('login required');
    await controlPlane.reportGroupMessagesRead(
        userId: uid, conversationId: conversationId, seqs: seqs);
  }

  Future<SyImUserProfile> getSelfProfile() {
    return _requireLoggedIn().getSelfProfile();
  }

  Future<void> setSelfProfile({
    String? nickname,
    String? faceUrl,
    String? ex,
  }) {
    return _requireLoggedIn().setSelfProfile(
      nickname: nickname,
      faceUrl: faceUrl,
      ex: ex,
    );
  }

  Future<List<SyImUserProfile>> getUserProfiles(List<String> userIds) {
    return _requireLoggedIn().getUserProfiles(userIds);
  }

  Future<void> setGroupCustomInfo({
    required String groupId,
    String? groupName,
    String? notification,
    String? ex,
  }) {
    return _requireLoggedIn().setGroupCustomInfo(
      groupId: groupId,
      groupName: groupName,
      notification: notification,
      ex: ex,
    );
  }

  Future<void> setGroupMemberCustomInfo({
    required String groupId,
    required String userId,
    String? nickname,
    String? ex,
  }) {
    return _requireLoggedIn().setGroupMemberCustomInfo(
      groupId: groupId,
      userId: userId,
      nickname: nickname,
      ex: ex,
    );
  }

  Future<void> addToBlacklist({required String userId}) {
    return _requireLoggedIn().addToBlacklist(userId: userId);
  }

  Future<void> removeFromBlacklist({required String userId}) {
    return _requireLoggedIn().removeFromBlacklist(userId: userId);
  }

  Future<List<SyImBlacklistUser>> getBlacklist() {
    return _requireLoggedIn().getBlacklist();
  }

  void _publishUnread(void Function() change) {
    change();
    onUnreadChanged?.call(_unread.latest);
  }

  Future<void> _syncUnreadFromSdk() async {
    final a = _adapter;
    if (a == null || !_loggedIn) return;
    try {
      final list = await a.getConversations();
      final total = await a.getTotalUnreadCount();
      _publishUnread(() => _unread.applyFullList(list, total: total));
    } catch (_) {
      // 未读同步失败时保留上一份快照，不把登录或收消息变成失败。
    }
  }

  OpenIMAdapter _requireLoggedIn() {
    if (!_loggedIn) {
      throw StateError('login required');
    }
    final a = _adapter;
    if (a == null) {
      throw StateError('login required');
    }
    return a;
  }

  bool get isLoggedIn => _loggedIn;
  String? get currentUserId => _currentUserId;
  bool get isOpenIMReady => _initialized;

  /// 控制面 REST（getToken / friends / groups / send / history / revoke）。
  ImControlPlane controlPlane({String? userJwt, String? appSecret}) =>
      ImControlPlane(
        apiBaseUrl: apiBaseUrl,
        appId: appId,
        userJwt: userJwt,
        appSecret: appSecret,
      );

  /// 便捷：控制面 getToken。
  Future<Map<String, dynamic>> getToken({
    required String userId,
    String? userJwt,
    String? appSecret,
  }) {
    return controlPlane(
      userJwt: userJwt,
      appSecret: appSecret,
    ).getToken(userId: userId);
  }
}
