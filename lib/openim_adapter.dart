import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// OpenIM → SyIm 适配层（**唯一**实时路径）。真实调用 [OpenIM.iMManager]。
///
/// 不再存在 `sy_im_flutter_sdk` 原生 MethodChannel 壳；原生通道仅来自 `flutter_openim_sdk`。
/// OpenIM API / channel 缺失时抛 [UnimplementedError]。
class OpenIMAdapter {
  OpenIMAdapter({required this.imApiAddr, required this.imWsAddr});

  /// OpenIM API，例如 `http://127.0.0.1:10002`
  String imApiAddr;

  /// OpenIM WebSocket，例如 `ws://127.0.0.1:10001`
  String imWsAddr;

  bool _inited = false;
  String? _selfUserId;

  /// [getGroupMessageReadInfo] 最近一次查到的消息 seq（没查到为 -1），供控制面 who-read 使用。
  int lastGroupReadSeq = -1;

  void Function()? onConnectSuccess;
  void Function()? onConnecting;
  void Function(int? code, String? error)? onConnectFailed;
  void Function()? onKickedOffline;
  void Function()? onUserTokenExpired;
  void Function(String msgId, String fromUserId, String? groupId, String? text)?
      onRecvNewMessage;
  void Function(List<SyImReadReceipt> receipts)? onRecvC2CReadReceipt;
  void Function(SyImRevokedMessage info)? onMessageRevoked;
  void Function(SyImTypingStatus status)? onTypingChanged;
  void Function(int totalUnread)? onTotalUnreadChanged;
  void Function(List<SyImConversation> conversations)? onConversationsChanged;
  void Function()? onConversationUpdated;

  bool get isInited => _inited;

  int get _platformId {
    if (Platform.isIOS) return IMPlatform.ios;
    if (Platform.isAndroid) return IMPlatform.android;
    return IMPlatform.android;
  }

  Future<T> _call<T>(String name, Future<T> Function() run) async {
    try {
      return await run();
    } on MissingPluginException catch (e) {
      throw UnimplementedError('OpenIM.$name missing plugin: $e');
    } on UnimplementedError {
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'UNIMPLEMENTED' ||
          (e.message ?? '').toLowerCase().contains('unimplemented')) {
        throw UnimplementedError('OpenIM.$name unimplemented: ${e.message}');
      }
      rethrow;
    }
  }

  /// SyIm.create / init → OpenIM.iMManager.initSDK
  Future<void> initSdk({required String dataDir, int? platformID}) async {
    await _call('initSDK', () async {
      await OpenIM.iMManager.initSDK(
        platformID: platformID ?? _platformId,
        apiAddr: imApiAddr,
        wsAddr: imWsAddr,
        dataDir: dataDir,
        logLevel: 6,
        listener: OnConnectListener(
          onConnectSuccess: () => onConnectSuccess?.call(),
          onConnecting: () => onConnecting?.call(),
          onConnectFailed: (c, m) => onConnectFailed?.call(c, m),
          onKickedOffline: () => onKickedOffline?.call(),
          onUserTokenExpired: () => onUserTokenExpired?.call(),
        ),
      );
      await OpenIM.iMManager.messageManager.setAdvancedMsgListener(
        OnAdvancedMsgListener(
          onRecvNewMessage: (msg) => _emitIncoming(msg),
          onRecvOfflineNewMessage: (msg) => _emitIncoming(msg),
          onNewRecvMessageRevoked: (info) {
            onMessageRevoked?.call(
              SyImRevokedMessage(
                clientMsgId: info.clientMsgID ?? '',
                revokerId: info.revokerID,
                revokerNickname: info.revokerNickname,
              ),
            );
          },
          onRecvC2CReadReceipt: (list) {
            onRecvC2CReadReceipt?.call(
              list
                  .map(
                    (r) => SyImReadReceipt(
                      conversationId: SyImReadReceipts.singleConversationId(
                        _selfUserId ?? '',
                        r.userID ?? '',
                      ),
                      userId: r.userID ?? '',
                      groupId: (r.groupID ?? '').isEmpty ? null : r.groupID,
                      msgIds: List<String>.from(
                        r.msgIDList ?? const <String>[],
                      ),
                      readTime: r.readTime ?? 0,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
      await OpenIM.iMManager.conversationManager.setConversationListener(
        OnConversationListener(
          onNewConversation: (list) {
            onConversationsChanged?.call(list.map(_mapConversation).toList());
            onConversationUpdated?.call();
          },
          onConversationChanged: (list) {
            onConversationsChanged?.call(list.map(_mapConversation).toList());
            onConversationUpdated?.call();
          },
          onTotalUnreadMessageCountChanged: (count) {
            onTotalUnreadChanged?.call(count);
          },
          onInputStatusChanged: (data) {
            onTypingChanged?.call(
              SyImTypingStatus.fromOpenIm(
                userId: data.userID,
                conversationId: data.conversationID,
                platformIds: data.platformIDs,
              ),
            );
          },
        ),
      );
    });
    _inited = true;
  }

  /// SyImEngine.login → OpenIM.iMManager.login
  Future<void> login({required String userId, required String token}) async {
    await _call('login', () async {
      await OpenIM.iMManager.login(userID: userId, token: token);
      _selfUserId = userId;
    });
  }

  /// SyImEngine.logout → OpenIM.iMManager.logout
  Future<void> logout() async {
    await _call('logout', () async {
      await OpenIM.iMManager.logout();
      _selfUserId = null;
    });
  }

  /// createTextMessage + sendMessage
  Future<String> sendTextMessage({
    String? toUserId,
    String? groupId,
    required String text,
  }) async {
    return _call('sendTextMessage', () async {
      final msg = await OpenIM.iMManager.messageManager.createTextMessage(
        text: text,
      );
      final sent = await OpenIM.iMManager.messageManager.sendMessage(
        message: msg,
        userID: toUserId ?? '',
        groupID: groupId ?? '',
        offlinePushInfo: OfflinePushInfo(
          title: 'new message',
          desc: text,
          iOSBadgeCount: true,
          iOSPushSound: '+1',
        ),
      );
      return sent.clientMsgID ?? '';
    });
  }

  Future<List<SyImConversation>> getConversations() async {
    return _call('getAllConversationList', () async {
      final list =
          await OpenIM.iMManager.conversationManager.getAllConversationList();
      return list.map(_mapConversation).toList();
    });
  }

  /// 将会话标为已读，并触发单聊已读回执。群会话只清未读。
  Future<void> markConversationAsRead({required String conversationId}) async {
    await _call('markConversationMessageAsRead', () async {
      await OpenIM.iMManager.conversationManager.markConversationMessageAsRead(
        conversationID: conversationId,
      );
    });
  }

  /// 全部会话未读总数。
  Future<int> getTotalUnreadCount() async {
    return _call('getTotalUnreadMsgCount', () async {
      final raw =
          await OpenIM.iMManager.conversationManager.getTotalUnreadMsgCount();
      return _asCount(raw);
    });
  }

  /// 发起好友申请（对方需同意）。
  Future<void> addFriend({required String userId, String reason = ''}) async {
    await _call('addFriend', () async {
      await OpenIM.iMManager.friendshipManager.addFriend(
        userID: userId,
        reason: reason,
      );
    });
  }

  /// 收到的好友申请。`sentByMe` 为 true 时返回自己发出的申请。
  Future<List<SyImFriendApplication>> getFriendApplications({
    bool sentByMe = false,
  }) async {
    return _call('getFriendApplications', () async {
      final list = sentByMe
          ? await OpenIM.iMManager.friendshipManager
              .getFriendApplicationListAsApplicant()
          : await OpenIM.iMManager.friendshipManager
              .getFriendApplicationListAsRecipient();
      return list
          .map(
            (a) => SyImFriendApplication(
              fromUserId: a.fromUserID ?? '',
              toUserId: a.toUserID ?? '',
              fromNickname: a.fromNickname,
              reqMsg: a.reqMsg,
              handleResult: a.handleResult ?? 0,
            ),
          )
          .toList();
    });
  }

  Future<void> acceptFriendApplication({
    required String userId,
    String handleMsg = '',
  }) async {
    await _call('acceptFriendApplication', () async {
      await OpenIM.iMManager.friendshipManager.acceptFriendApplication(
        userID: userId,
        handleMsg: handleMsg,
      );
    });
  }

  Future<void> refuseFriendApplication({
    required String userId,
    String handleMsg = '',
  }) async {
    await _call('refuseFriendApplication', () async {
      await OpenIM.iMManager.friendshipManager.refuseFriendApplication(
        userID: userId,
        handleMsg: handleMsg,
      );
    });
  }

  Future<List<SyImFriend>> getFriends() async {
    return _call('getFriendList', () async {
      final list = await OpenIM.iMManager.friendshipManager.getFriendList();
      return list
          .map(
            (f) => SyImFriend(
              userId: _friendUserId(f),
              nickname: f.nickname,
              remark: f.remark,
            ),
          )
          .toList();
    });
  }

  /// 创建工作群。`groupId` 为空时由 OpenIM 分配。
  Future<SyImGroup> createGroup({
    required String groupName,
    String groupId = '',
    List<String> memberUserIds = const [],
  }) async {
    return _call('createGroup', () async {
      final info = await OpenIM.iMManager.groupManager.createGroup(
        groupInfo: GroupInfo(
          groupID: groupId,
          groupName: groupName,
          groupType: GroupType.work,
        ),
        memberUserIDs: memberUserIds,
      );
      return SyImGroup(
        groupId: info.groupID,
        groupName: info.groupName,
        ownerUserId: info.ownerUserID,
        memberCount: info.memberCount ?? memberUserIds.length,
      );
    });
  }

  Future<void> inviteToGroup({
    required String groupId,
    required List<String> userIds,
    String reason = '',
  }) async {
    await _call('inviteUserToGroup', () async {
      await OpenIM.iMManager.groupManager.inviteUserToGroup(
        groupID: groupId,
        userIDList: userIds,
        reason: reason,
      );
    });
  }

  Future<void> kickGroupMembers({
    required String groupId,
    required List<String> userIds,
    String reason = '',
  }) async {
    await _call('kickGroupMember', () async {
      await OpenIM.iMManager.groupManager.kickGroupMember(
        groupID: groupId,
        userIDList: userIds,
        reason: reason,
      );
    });
  }

  Future<void> joinGroup({required String groupId, String reason = ''}) async {
    await _call('joinGroup', () async {
      await OpenIM.iMManager.groupManager.joinGroup(
        groupID: groupId,
        reason: reason,
      );
    });
  }

  Future<void> quitGroup({required String groupId}) async {
    await _call('quitGroup', () async {
      await OpenIM.iMManager.groupManager.quitGroup(groupID: groupId);
    });
  }

  Future<void> dismissGroup({required String groupId}) async {
    await _call('dismissGroup', () async {
      await OpenIM.iMManager.groupManager.dismissGroup(groupID: groupId);
    });
  }

  Future<List<SyImGroup>> getJoinedGroups() async {
    return _call('getJoinedGroupList', () async {
      final list = await OpenIM.iMManager.groupManager.getJoinedGroupList();
      return list
          .map(
            (g) => SyImGroup(
              groupId: g.groupID,
              groupName: g.groupName,
              ownerUserId: g.ownerUserID,
              memberCount: g.memberCount ?? 0,
            ),
          )
          .toList();
    });
  }

  Future<List<SyImGroupMember>> getGroupMembers({
    required String groupId,
    int count = 100,
  }) async {
    return _call('getGroupMemberList', () async {
      final list = await OpenIM.iMManager.groupManager.getGroupMemberList(
        groupID: groupId,
        count: count,
      );
      return list
          .map(
            (m) => SyImGroupMember(
              groupId: m.groupID,
              userId: m.userID ?? '',
              nickname: m.nickname,
              roleLevel: m.roleLevel ?? 0,
            ),
          )
          .toList();
    });
  }

  Future<void> revokeMessage({
    required String conversationId,
    required String clientMsgId,
  }) async {
    await _call('revokeMessage', () async {
      await OpenIM.iMManager.messageManager.revokeMessage(
        conversationID: conversationId,
        clientMsgID: clientMsgId,
      );
    });
  }

  Future<String> sendAtTextMessage({
    required String groupId,
    required String text,
    required List<String> atUserIds,
    Map<String, String> atNicknames = const {},
  }) async {
    return _call('sendAtTextMessage', () async {
      final msg = await OpenIM.iMManager.messageManager.createTextAtMessage(
        text: text,
        atUserIDList: atUserIds,
        atUserInfoList: [
          for (final id in atUserIds)
            AtUserInfo(atUserID: id, groupNickname: atNicknames[id]),
        ],
      );
      return _sendCreated(message: msg, groupId: groupId, pushDesc: text);
    });
  }

  Future<String> sendCustomMessage({
    String? toUserId,
    String? groupId,
    required String data,
    String customExtension = '',
    String description = '',
  }) async {
    return _call('sendCustomMessage', () async {
      final msg = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: data,
        extension: customExtension,
        description: description,
      );
      return _sendCreated(
        message: msg,
        toUserId: toUserId,
        groupId: groupId,
        pushDesc: description.isEmpty ? data : description,
      );
    });
  }

  Future<List<SyImSearchHit>> searchMessages({
    String? conversationId,
    required String keyword,
    int count = 20,
  }) async {
    return _call('searchLocalMessages', () async {
      final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
        conversationID: conversationId,
        keywordList: [keyword],
        count: count,
      );
      final items = result.searchResultItems ?? result.findResultItems ?? [];
      final hits = <SyImSearchHit>[];
      for (final item in items) {
        for (final message in item.messageList ?? const <Message>[]) {
          hits.add(
            SyImSearchHit(
              conversationId: item.conversationID ?? conversationId ?? '',
              showName: item.showName,
              clientMsgId: message.clientMsgID ?? '',
              sendUserId: message.sendID,
              text: _messagePreview(message),
            ),
          );
        }
      }
      return hits;
    });
  }

  Future<void> pinConversation({
    required String conversationId,
    required bool pinned,
  }) async {
    await _call('pinConversation', () async {
      await OpenIM.iMManager.conversationManager.pinConversation(
        conversationID: conversationId,
        isPinned: pinned,
      );
    });
  }

  Future<void> setConversationDraft({
    required String conversationId,
    required String draft,
  }) async {
    await _call('setConversationDraft', () async {
      await OpenIM.iMManager.conversationManager.setConversationDraft(
        conversationID: conversationId,
        draftText: draft,
      );
    });
  }

  Future<void> setConversationDoNotDisturb({
    required String conversationId,
    required int status,
  }) async {
    if (status < 0 || status > 2) {
      throw ArgumentError('status must be 0, 1, or 2');
    }
    await _call('setConversation', () async {
      await OpenIM.iMManager.conversationManager.setConversation(
        conversationId,
        ConversationReq(recvMsgOpt: status),
      );
    });
  }

  Future<void> setTyping({
    required String conversationId,
    required bool typing,
  }) async {
    await _call('changeInputStates', () async {
      await OpenIM.iMManager.conversationManager.changeInputStates(
        conversationID: conversationId,
        focus: typing,
      );
    });
  }

  Future<SyImGroupReadInfo> getGroupMessageReadInfo({
    required String conversationId,
    required String clientMsgId,
  }) async {
    return _call('findMessageList', () async {
      final result = await OpenIM.iMManager.messageManager.findMessageList(
        searchParams: [
          SearchParams(
            conversationID: conversationId,
            clientMsgIDList: [clientMsgId],
          ),
        ],
      );
      final items = result.findResultItems ?? result.searchResultItems ?? [];
      for (final item in items) {
        for (final message in item.messageList ?? const <Message>[]) {
          if (message.clientMsgID != clientMsgId) continue;
          final info = message.attachedInfoElem?.groupHasReadInfo;
          lastGroupReadSeq = message.seq ?? 0;
          return SyImGroupReadInfo(
            clientMsgId: clientMsgId,
            hasReadCount: info?.hasReadCount ?? 0,
            unreadCount: info?.unreadCount ?? 0,
          );
        }
      }
      lastGroupReadSeq = -1;
      return SyImGroupReadInfo(
          clientMsgId: clientMsgId, hasReadCount: 0, unreadCount: 0);
    });
  }

  Future<SyImUserProfile> getSelfProfile() async {
    return _call('getSelfUserInfo', () async {
      final info = await OpenIM.iMManager.userManager.getSelfUserInfo();
      return SyImUserProfile(
        userId: info.userID ?? '',
        nickname: info.nickname,
        faceUrl: info.faceURL,
        ex: info.ex,
      );
    });
  }

  Future<void> setSelfProfile({
    String? nickname,
    String? faceUrl,
    String? ex,
  }) async {
    await _call('setSelfInfo', () async {
      await OpenIM.iMManager.userManager.setSelfInfo(
        nickname: nickname,
        faceURL: faceUrl,
        ex: ex,
      );
    });
  }

  Future<List<SyImUserProfile>> getUserProfiles(List<String> userIds) async {
    return _call('getUsersInfo', () async {
      final list = await OpenIM.iMManager.userManager.getUsersInfo(
        userIDList: userIds,
      );
      return list
          .map(
            (info) => SyImUserProfile(
              userId: info.userID ?? '',
              nickname: info.nickname,
              faceUrl: info.faceURL,
              ex: info.ex,
            ),
          )
          .toList();
    });
  }

  Future<void> setGroupCustomInfo({
    required String groupId,
    String? groupName,
    String? notification,
    String? ex,
  }) async {
    await _call('setGroupInfo', () async {
      await OpenIM.iMManager.groupManager.setGroupInfo(
        GroupInfo(
          groupID: groupId,
          groupName: groupName,
          notification: notification,
          ex: ex,
        ),
      );
    });
  }

  Future<void> setGroupMemberCustomInfo({
    required String groupId,
    required String userId,
    String? nickname,
    String? ex,
  }) async {
    await _call('setGroupMemberInfo', () async {
      await OpenIM.iMManager.groupManager.setGroupMemberInfo(
        groupMembersInfo: SetGroupMemberInfo(
          groupID: groupId,
          userID: userId,
          nickname: nickname,
          ex: ex,
        ),
      );
    });
  }

  Future<void> addToBlacklist({required String userId}) async {
    await _call('addBlacklist', () async {
      await OpenIM.iMManager.friendshipManager.addBlacklist(userID: userId);
    });
  }

  Future<void> removeFromBlacklist({required String userId}) async {
    await _call('removeBlacklist', () async {
      await OpenIM.iMManager.friendshipManager.removeBlacklist(userID: userId);
    });
  }

  Future<List<SyImBlacklistUser>> getBlacklist() async {
    return _call('getBlacklist', () async {
      final list = await OpenIM.iMManager.friendshipManager.getBlacklist();
      return list
          .map(
            (info) => SyImBlacklistUser(
              userId: info.blockUserID ?? info.userID ?? '',
              nickname: info.nickname,
              faceUrl: info.faceURL,
            ),
          )
          .toList();
    });
  }

  void _emitIncoming(Message msg) {
    onRecvNewMessage?.call(
      msg.clientMsgID ?? '',
      msg.sendID ?? '',
      msg.groupID,
      _messagePreview(msg),
    );
  }

  Future<String> _sendCreated({
    required Message message,
    String? toUserId,
    String? groupId,
    required String pushDesc,
  }) async {
    final sent = await OpenIM.iMManager.messageManager.sendMessage(
      message: message,
      userID: toUserId ?? '',
      groupID: groupId ?? '',
      offlinePushInfo: OfflinePushInfo(
        title: 'new message',
        desc: pushDesc,
        iOSBadgeCount: true,
        iOSPushSound: '+1',
      ),
    );
    return sent.clientMsgID ?? '';
  }
}

SyImConversation _mapConversation(ConversationInfo conversation) {
  return SyImConversation(
    conversationId: conversation.conversationID,
    userId: conversation.userID,
    groupId: conversation.groupID,
    showName: conversation.showName,
    latestText: conversation.latestMsg == null
        ? null
        : _messagePreview(conversation.latestMsg!),
    unreadCount: conversation.unreadCount,
    isPinned: conversation.isPinned ?? false,
    draftText: conversation.draftText,
    recvMsgOpt: conversation.recvMsgOpt ?? 0,
    groupAtType: conversation.groupAtType ?? 0,
    ex: conversation.ex,
  );
}

String? _messagePreview(Message message) {
  final text = message.textElem?.content;
  if (text != null && text.isNotEmpty) return text;
  final atText = message.atTextElem?.text;
  if (atText != null && atText.isNotEmpty) return atText;
  final description = message.customElem?.description;
  if (description != null && description.isNotEmpty) return description;
  return message.customElem?.data;
}

int _asCount(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw') ?? 0;
}

String _friendUserId(FriendInfo friend) {
  final id = friend.friendUserID;
  if (id != null && id.isNotEmpty) return id;
  return friend.userID ?? '';
}

class SyImConversation {
  const SyImConversation({
    required this.conversationId,
    this.userId,
    this.groupId,
    this.showName,
    this.latestText,
    this.unreadCount = 0,
    this.isPinned = false,
    this.draftText,
    this.recvMsgOpt = 0,
    this.groupAtType = 0,
    this.ex,
  });

  final String conversationId;
  final String? userId;
  final String? groupId;
  final String? showName;
  final String? latestText;
  final int unreadCount;
  final bool isPinned;
  final String? draftText;

  /// 0 正常，1 免打扰，2 仅在线接收。
  final int recvMsgOpt;

  /// 0 无，1 @我，2 @所有人，3 @所有人且@我，4 群公告。
  final int groupAtType;
  final String? ex;

  SyImConversation copyWith({int? unreadCount}) {
    return SyImConversation(
      conversationId: conversationId,
      userId: userId,
      groupId: groupId,
      showName: showName,
      latestText: latestText,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned,
      draftText: draftText,
      recvMsgOpt: recvMsgOpt,
      groupAtType: groupAtType,
      ex: ex,
    );
  }
}

/// 已读回执（单聊 + 群聊统一）。与 Android `ImReadReceipt`、iOS `SyImReadReceipt` 字段和语义相同：
///
/// - [conversationId]：OpenIM 会话 id（单聊 `si_<小 uid>_<大 uid>`，群 `sg_<groupId>`）；推导不出时为空串。
/// - [userId]：已读方。[groupId]：群聊为群 id，单聊为 null。
/// - [msgIds]：该已读方本次已读的客户端消息 id。[readTime]：毫秒，OpenIM 没给时为 0。
class SyImReadReceipt {
  const SyImReadReceipt({
    this.conversationId = '',
    this.userId = '',
    this.groupId,
    this.msgIds = const [],
    this.readTime = 0,
  });

  final String conversationId;
  final String userId;
  final String? groupId;
  final List<String> msgIds;
  final int readTime;

  bool get isGroup => (groupId ?? '').isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is SyImReadReceipt &&
      other.conversationId == conversationId &&
      other.userId == userId &&
      other.groupId == groupId &&
      other.readTime == readTime &&
      _listEq(other.msgIds, msgIds);

  @override
  int get hashCode => Object.hash(
      conversationId, userId, groupId, readTime, Object.hashAll(msgIds));

  @override
  String toString() =>
      'SyImReadReceipt($conversationId, $userId, $groupId, $msgIds, $readTime)';
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 已读回执的纯逻辑，三端规则相同（Android `ImReadReceipts`、iOS `SyImReadReceipts`）。
class SyImReadReceipts {
  SyImReadReceipts._();

  static String singleConversationId(String a, String b) {
    if (a.isEmpty || b.isEmpty) return '';
    final ids = [a, b]..sort();
    return 'si_${ids.join('_')}';
  }

  static String groupConversationId(String groupId) =>
      groupId.isEmpty ? '' : 'sg_$groupId';

  static String? groupIdOf(String conversationId) =>
      conversationId.startsWith('sg_') && conversationId.length > 3
          ? conversationId.substring(3)
          : null;

  /// 「每条消息 → 已读成员」转成「每个已读者 → 消息 id」，已读者按首次出现顺序。
  static List<SyImReadReceipt> perReader(
    String conversationId,
    List<MapEntry<String, List<String>>> perMessage,
  ) {
    final byReader = <String, List<String>>{};
    for (final e in perMessage) {
      if (e.key.isEmpty) continue;
      for (final r in e.value) {
        if (r.isEmpty) continue;
        final list = byReader.putIfAbsent(r, () => <String>[]);
        if (!list.contains(e.key)) list.add(e.key);
      }
    }
    final gid = groupIdOf(conversationId);
    return byReader.entries
        .map((e) => SyImReadReceipt(
              conversationId: conversationId,
              userId: e.key,
              groupId: gid,
              msgIds: e.value,
            ))
        .toList();
  }

  /// 控制面 `who-read` 的 `list[].readerUid` → 去重后的已读者（保持服务端顺序：最近已读在前）。
  static List<String> readersFromWhoRead(List<dynamic> list) {
    final out = <String>[];
    for (final row in list) {
      if (row is! Map) continue;
      final uid = row['readerUid'];
      if (uid is String && uid.isNotEmpty && !out.contains(uid)) out.add(uid);
    }
    return out;
  }

  /// OpenIM 有成员 id 就用 OpenIM；否则用控制面花名册（[roster] 为 null 表示没查）。
  /// 花名册人数多于 OpenIM 人数时以花名册为准，未读相应减少（不小于 0）。
  static SyImGroupReadInfo merge({
    required String clientMsgId,
    required int hasReadCount,
    required int unreadCount,
    List<String> openImReaders = const [],
    List<String>? roster,
  }) {
    if (openImReaders.isNotEmpty) {
      return SyImGroupReadInfo(
        clientMsgId: clientMsgId,
        hasReadCount: hasReadCount > openImReaders.length
            ? hasReadCount
            : openImReaders.length,
        unreadCount: unreadCount,
        readUserIds: openImReaders,
        source: SyImGroupReadInfo.sourceOpenIm,
      );
    }
    if (roster != null && roster.isNotEmpty) {
      final read = hasReadCount > roster.length ? hasReadCount : roster.length;
      final unread = unreadCount - (read - hasReadCount);
      return SyImGroupReadInfo(
        clientMsgId: clientMsgId,
        hasReadCount: read,
        unreadCount: unread < 0 ? 0 : unread,
        readUserIds: roster,
        source: SyImGroupReadInfo.sourceControlPlane,
      );
    }
    return SyImGroupReadInfo(
      clientMsgId: clientMsgId,
      hasReadCount: hasReadCount,
      unreadCount: unreadCount,
    );
  }
}

class SyImFriend {
  const SyImFriend({required this.userId, this.nickname, this.remark});

  final String userId;
  final String? nickname;
  final String? remark;
}

/// 好友申请。`handleResult`：0 未处理，1 已同意，-1 已拒绝。
class SyImFriendApplication {
  const SyImFriendApplication({
    required this.fromUserId,
    required this.toUserId,
    this.fromNickname,
    this.reqMsg,
    this.handleResult = 0,
  });

  final String fromUserId;
  final String toUserId;
  final String? fromNickname;
  final String? reqMsg;
  final int handleResult;
}

class SyImGroup {
  const SyImGroup({
    required this.groupId,
    this.groupName,
    this.ownerUserId,
    this.memberCount = 0,
  });

  final String groupId;
  final String? groupName;
  final String? ownerUserId;
  final int memberCount;
}

class SyImGroupMember {
  const SyImGroupMember({
    this.groupId,
    required this.userId,
    this.nickname,
    this.roleLevel = 0,
  });

  final String? groupId;
  final String userId;
  final String? nickname;
  final int roleLevel;
}

class SyImRevokedMessage {
  const SyImRevokedMessage({
    required this.clientMsgId,
    this.revokerId,
    this.revokerNickname,
  });

  final String clientMsgId;
  final String? revokerId;
  final String? revokerNickname;
}

class SyImSearchHit {
  const SyImSearchHit({
    required this.conversationId,
    required this.clientMsgId,
    this.showName,
    this.sendUserId,
    this.text,
  });

  final String conversationId;
  final String clientMsgId;
  final String? showName;
  final String? sendUserId;
  final String? text;
}

/// 对方输入状态。字段与 Android `ImTypingStatus`、iOS `SyImTypingStatus` 相同。
///
/// OpenIM 推的是对方正在输入的端（[platformIds]）；为空即停止输入，[typing] 为 false。
class SyImTypingStatus {
  const SyImTypingStatus({
    required this.userId,
    required this.conversationId,
    required this.typing,
    this.platformIds = const [],
  });

  /// 按 OpenIM `InputStatusChangedData` 字段构造。
  factory SyImTypingStatus.fromOpenIm({
    String? userId,
    String? conversationId,
    List<int>? platformIds,
  }) {
    final platforms = List<int>.unmodifiable(platformIds ?? const <int>[]);
    return SyImTypingStatus(
      userId: userId ?? '',
      conversationId: conversationId ?? '',
      typing: platforms.isNotEmpty,
      platformIds: platforms,
    );
  }

  final String userId;
  final String conversationId;
  final bool typing;
  final List<int> platformIds;
}

/// 群消息已读概况，三端相同。flutter_openim_sdk 3.8.3+hotfix.15 的 [GroupHasReadInfo] 只有人数，
/// 已读成员来自控制面 who-read 花名册（[source] == `controlPlane`），否则为空（`none`）。
/// 花名册只含调用过 `reportGroupMessagesRead` 的成员，不是全员已读名单。
class SyImGroupReadInfo {
  static const String sourceOpenIm = 'openim';
  static const String sourceControlPlane = 'controlPlane';
  static const String sourceNone = 'none';

  const SyImGroupReadInfo({
    this.clientMsgId = '',
    required this.hasReadCount,
    required this.unreadCount,
    this.readUserIds = const [],
    this.source = sourceNone,
  });

  final String clientMsgId;
  final int hasReadCount;
  final int unreadCount;
  final List<String> readUserIds;
  final String source;
}

class SyImUserProfile {
  const SyImUserProfile({
    required this.userId,
    this.nickname,
    this.faceUrl,
    this.ex,
  });

  final String userId;
  final String? nickname;
  final String? faceUrl;

  /// 业务自定义资料，对应 OpenIM `ex`。
  final String? ex;
}

class SyImBlacklistUser {
  const SyImBlacklistUser({
    required this.userId,
    this.nickname,
    this.faceUrl,
  });

  final String userId;
  final String? nickname;
  final String? faceUrl;
}
