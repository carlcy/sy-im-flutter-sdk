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

  void Function()? onConnectSuccess;
  void Function()? onConnecting;
  void Function(int? code, String? error)? onConnectFailed;
  void Function()? onKickedOffline;
  void Function()? onUserTokenExpired;
  void Function(String msgId, String fromUserId, String? groupId, String? text)?
  onRecvNewMessage;
  void Function(List<SyImReadReceipt> receipts)? onRecvC2CReadReceipt;
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
          onRecvNewMessage: (msg) {
            onRecvNewMessage?.call(
              msg.clientMsgID ?? '',
              msg.sendID ?? '',
              msg.groupID,
              msg.textElem?.content,
            );
          },
          onRecvOfflineNewMessage: (msg) {
            onRecvNewMessage?.call(
              msg.clientMsgID ?? '',
              msg.sendID ?? '',
              msg.groupID,
              msg.textElem?.content,
            );
          },
          onRecvC2CReadReceipt: (list) {
            onRecvC2CReadReceipt?.call(
              list
                  .map(
                    (r) => SyImReadReceipt(
                      userId: r.userID,
                      groupId: r.groupID,
                      msgIds: List<String>.from(
                        r.msgIDList ?? const <String>[],
                      ),
                      readTime: r.readTime,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
      await OpenIM.iMManager.conversationManager.setConversationListener(
        OnConversationListener(
          onNewConversation: (_) => onConversationUpdated?.call(),
          onConversationChanged: (_) => onConversationUpdated?.call(),
        ),
      );
    });
    _inited = true;
  }

  /// SyImEngine.login → OpenIM.iMManager.login
  Future<void> login({required String userId, required String token}) async {
    await _call('login', () async {
      await OpenIM.iMManager.login(userID: userId, token: token);
    });
  }

  /// SyImEngine.logout → OpenIM.iMManager.logout
  Future<void> logout() async {
    await _call('logout', () async {
      await OpenIM.iMManager.logout();
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
      final list = await OpenIM.iMManager.conversationManager
          .getAllConversationList();
      return list
          .map(
            (c) => SyImConversation(
              conversationId: c.conversationID,
              userId: c.userID,
              groupId: c.groupID,
              showName: c.showName,
              latestText: c.latestMsg?.textElem?.content,
              unreadCount: c.unreadCount,
            ),
          )
          .toList();
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
      final raw = await OpenIM.iMManager.conversationManager
          .getTotalUnreadMsgCount();
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
  });

  final String conversationId;
  final String? userId;
  final String? groupId;
  final String? showName;
  final String? latestText;
  final int unreadCount;
}

/// 单聊已读回执。
class SyImReadReceipt {
  const SyImReadReceipt({
    this.userId,
    this.groupId,
    this.msgIds = const [],
    this.readTime,
  });

  final String? userId;
  final String? groupId;
  final List<String> msgIds;
  final int? readTime;
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
