/// SY IM Flutter SDK
///
/// 与 RTC 相同的 AppID 模型：`SyIm.create(appId, apiBaseUrl)`。
/// **唯一实时路径**：Dart [OpenIMAdapter] → 官方 `flutter_openim_sdk` / `OpenIM.iMManager`。
/// 无遗留 `SyImFlutterSdkPlugin` MethodChannel。
/// IM Token / imApiAddr / imWsAddr 由开发者后端签发（`/api/server/im/token` 或用户态等价接口）。
library;

export 'openim_adapter.dart';
export 'im_control_plane.dart';

import 'dart:io';

import 'openim_adapter.dart';
import 'im_control_plane.dart';

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
  }) => create(
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

  void Function()? onConnectSuccess;
  void Function()? onConnecting;
  void Function(int? code, String? error)? onConnectFailed;
  void Function()? onKickedOffline;
  void Function()? onUserTokenExpired;
  void Function(String msgId, String fromUserId, String? groupId, String? text)?
  onRecvNewMessage;
  void Function(List<SyImReadReceipt> receipts)? onRecvC2CReadReceipt;
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
    final dir =
        dataDir ??
        _dataDir ??
        Directory.systemTemp.createTempSync('sy_im').path;
    _dataDir = dir;
    final adapter = OpenIMAdapter(imApiAddr: imApiAddr, imWsAddr: imWsAddr);
    adapter.onConnectSuccess = () => onConnectSuccess?.call();
    adapter.onConnecting = () => onConnecting?.call();
    adapter.onConnectFailed = (c, m) => onConnectFailed?.call(c, m);
    adapter.onKickedOffline = () => onKickedOffline?.call();
    adapter.onUserTokenExpired = () => onUserTokenExpired?.call();
    adapter.onRecvNewMessage = (id, from, gid, text) =>
        onRecvNewMessage?.call(id, from, gid, text);
    adapter.onRecvC2CReadReceipt = (receipts) =>
        onRecvC2CReadReceipt?.call(receipts);
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
  }

  Future<void> logout() async {
    await _adapter?.logout();
    _loggedIn = false;
    _currentUserId = null;
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
    if (a == null) return const [];
    return a.getConversations();
  }

  /// 标记会话已读。单聊会向对方发送已读回执。
  Future<void> markConversationAsRead({required String conversationId}) {
    return _requireLoggedIn().markConversationAsRead(
      conversationId: conversationId,
    );
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
