import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// OpenIM → SyIm 适配层（**唯一**实时路径）。真实调用 [OpenIM.iMManager]。
///
/// 不再存在 `sy_im_flutter_sdk` 原生 MethodChannel 壳；原生通道仅来自 `flutter_openim_sdk`。
/// OpenIM API / channel 缺失时抛 [UnimplementedError]。
class OpenIMAdapter {
  OpenIMAdapter({
    required this.imApiAddr,
    required this.imWsAddr,
  });

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
  Future<void> initSdk({
    required String dataDir,
    int? platformID,
  }) async {
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
  Future<void> login({
    required String userId,
    required String token,
  }) async {
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
      final list =
          await OpenIM.iMManager.conversationManager.getAllConversationList();
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
