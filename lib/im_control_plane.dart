import 'dart:convert';

import 'package:http/http.dart' as http;

/// SY IM 控制面 REST（非 OpenIM 原生 SDK）。
///
/// - [getToken] → `/api/user/im/token` 或 `/api/server/im/token`
/// - friends / groups / send / history / revoke → `/api/user/im/*`
///
/// 已读、总未读、好友申请同意/拒绝、群成员管理走登录后的 OpenIM 实时接口
/// （[OpenIMAdapter]）。本类只覆盖控制面 REST，原有路径保持不变。
class ImControlPlane {
  ImControlPlane({
    required this.apiBaseUrl,
    required this.appId,
    this.userJwt,
    this.appSecret,
  });

  final String apiBaseUrl;
  final String appId;
  String? userJwt;
  String? appSecret;

  String get _base => apiBaseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<Map<String, dynamic>> getToken({required String userId}) async {
    final jwt = userJwt;
    final secret = appSecret;
    late Uri uri;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-App-Id': appId,
    };
    if (jwt != null && jwt.isNotEmpty) {
      uri = Uri.parse('$_base/api/user/im/token');
      headers['Authorization'] = 'Bearer $jwt';
    } else if (secret != null && secret.isNotEmpty) {
      uri = Uri.parse('$_base/api/server/im/token');
      headers['X-App-Secret'] = secret;
    } else {
      throw StateError('set userJwt or appSecret before getToken');
    }
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'appId': appId, 'userId': userId}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> addFriend({
    required String fromUserId,
    required String toUserId,
    String reqMsg = '',
  }) =>
      _userPost('/api/user/im/friends/add', {
        'appId': appId,
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        'reqMsg': reqMsg,
      });

  Future<Map<String, dynamic>> listFriends({required String ownerUserId}) =>
      _userPost('/api/user/im/friends/list', {
        'appId': appId,
        'ownerUserId': ownerUserId,
      });

  Future<Map<String, dynamic>> createGroup({
    required String ownerUserId,
    required String groupName,
    List<String> memberUserIds = const [],
  }) =>
      _userPost('/api/user/im/groups/create', {
        'appId': appId,
        'ownerUserId': ownerUserId,
        'groupName': groupName,
        'memberUserIds': memberUserIds,
      });

  Future<Map<String, dynamic>> listGroups({required String ownerUserId}) =>
      _userPost('/api/user/im/groups/list', {
        'appId': appId,
        'ownerUserId': ownerUserId,
      });

  Future<Map<String, dynamic>> send({
    required String fromUserId,
    String? toUserId,
    String? groupId,
    String contentType = 'text',
    required dynamic content,
  }) {
    final body = <String, dynamic>{
      'appId': appId,
      'fromUserId': fromUserId,
      'contentType': contentType,
      'content': content,
    };
    if (toUserId != null) body['toUserId'] = toUserId;
    if (groupId != null) body['groupId'] = groupId;
    return _userPost('/api/user/im/send', body);
  }

  Future<Map<String, dynamic>> history({
    required String userId,
    String? conversationId,
    String? peerUserId,
    String? groupId,
    int count = 20,
  }) {
    final body = <String, dynamic>{
      'appId': appId,
      'userId': userId,
      'count': count,
    };
    if (conversationId != null) body['conversationId'] = conversationId;
    if (peerUserId != null) body['peerUserId'] = peerUserId;
    if (groupId != null) body['groupId'] = groupId;
    return _userPost('/api/user/im/messages/history', body);
  }

  Future<Map<String, dynamic>> revoke({
    required String userId,
    required String conversationId,
    required int seq,
  }) =>
      _userPost('/api/user/im/messages/revoke', {
        'appId': appId,
        'userId': userId,
        'conversationId': conversationId,
        'seq': seq,
      });

  /// 对一条消息加 / 取消表情回应。`POST /api/user/im/reaction`。
  ///
  /// 服务端以 Custom(110) 消息发出（`data` 里 `sy=reaction_lite`），对端按普通自定义消息收到，
  /// 用 [SyImReaction.parse] 解析。不是 OpenIM 原生回应接口，也没有服务端聚合计数。
  /// 单聊传 [toUserId]，群聊传 [groupId]；目标消息用 [targetClientMsgId] 或 [targetSeq]。
  Future<Map<String, dynamic>> reactToMessage({
    required String fromUserId,
    required String emoji,
    String? toUserId,
    String? groupId,
    String? targetClientMsgId,
    int targetSeq = 0,
    String? targetSenderId,
    bool add = true,
  }) =>
      _userPost(
        '/api/user/im/reaction',
        SyImReaction.requestBody(
          appId: appId,
          fromUserId: fromUserId,
          emoji: emoji,
          toUserId: toUserId,
          groupId: groupId,
          targetClientMsgId: targetClientMsgId,
          targetSeq: targetSeq,
          targetSenderId: targetSenderId,
          add: add,
        ),
      );

  /// 新建会话标签（每个用户自己的分组，存在 SY 服务端）。返回值含 `tag`。
  Future<Map<String, dynamic>> createConversationTag({
    required String ownerUserId,
    required String name,
    String color = '',
    String remark = '',
  }) =>
      _userPost('/api/user/im/conversations/tags/create', {
        'appId': appId,
        'ownerUserId': ownerUserId,
        'name': name,
        'color': color,
        'remark': remark,
      });

  /// 列出会话标签。`list` 每项含 `id` / `name` / `memberCount` / `members`。
  Future<Map<String, dynamic>> listConversationTags({
    required String ownerUserId,
  }) =>
      _userPost('/api/user/im/conversations/tags/list', {
        'appId': appId,
        'ownerUserId': ownerUserId,
      });

  /// 删除会话标签。
  Future<Map<String, dynamic>> deleteConversationTag({
    required String ownerUserId,
    required int tagId,
  }) =>
      _userPost('/api/user/im/conversations/tags/delete', {
        'appId': appId,
        'ownerUserId': ownerUserId,
        'tagId': tagId,
      });

  /// 把会话加入标签。
  Future<Map<String, dynamic>> addConversationsToTag({
    required String ownerUserId,
    required int tagId,
    required List<String> conversationIds,
  }) =>
      _userPost('/api/user/im/conversations/tags/members', {
        'appId': appId,
        'ownerUserId': ownerUserId,
        'tagId': tagId,
        'action': 'add',
        'conversationIds': conversationIds,
      });

  /// 把会话移出标签。
  Future<Map<String, dynamic>> removeConversationsFromTag({
    required String ownerUserId,
    required int tagId,
    required List<String> conversationIds,
  }) =>
      _userPost('/api/user/im/conversations/tags/members', {
        'appId': appId,
        'ownerUserId': ownerUserId,
        'tagId': tagId,
        'action': 'remove',
        'conversationIds': conversationIds,
      });

  Future<Map<String, dynamic>> _userPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final jwt = userJwt;
    if (jwt == null || jwt.isEmpty) {
      throw StateError('userJwt required for $path');
    }
    final res = await http.post(
      Uri.parse('$_base$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
        'X-App-Id': appId,
      },
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) =>
      decodeControlPlaneResponse(res.statusCode, res.body);
}

/// 解析控制面响应。非 2xx 或业务码非 0 时抛 [SyImControlPlaneException]。
Map<String, dynamic> decodeControlPlaneResponse(int httpStatus, String body) {
  Object? parsed;
  try {
    parsed = jsonDecode(body.isEmpty ? '{}' : body);
  } on FormatException {
    parsed = null;
  }
  final ok = httpStatus >= 200 && httpStatus < 300;
  if (parsed is! Map) {
    if (ok) {
      throw SyImControlPlaneException(-1, httpStatus, 'unexpected response');
    }
    throw SyImControlPlaneException(httpStatus, httpStatus, 'HTTP $httpStatus');
  }
  final m = Map<String, dynamic>.from(parsed);
  final rawCode = m['code'];
  final code = rawCode is num ? rawCode.toInt() : (ok ? 0 : httpStatus);
  if (!ok || code != 0) {
    final msg = m['msg']?.toString();
    throw SyImControlPlaneException(code, httpStatus,
        (msg == null || msg.isEmpty) ? 'HTTP $httpStatus' : msg);
  }
  final data = m['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data == null) return <String, dynamic>{};
  return <String, dynamic>{'value': data};
}

/// SY 控制面（`/api/user/im/*`、`/api/server/im/token`）返回的业务码。
///
/// 与 Android `ImErrorCode`、iOS `SyImErrorCode` 取值相同，与服务端 `errcode` 包一致。
/// OpenIM SDK 自己的错误码（登录、实时收发）不在此列，原样透传。
class SyImErrorCode {
  SyImErrorCode._();

  /// 未登录或 User JWT 无效。
  static const int unauthorized = 401;

  /// 无权访问该应用。
  static const int forbidden = 403;

  /// 应用未开通 IM。
  static const int imNotEnabled = 3001;

  /// 月活超出套餐。
  static const int quotaMau = 3003;

  /// 消息量超出套餐。
  static const int quotaMessages = 3004;

  /// 体验版已下线。
  static const int trialRetired = 4003;

  /// 敏感词拦截（拒绝模式）。
  static const int sensitiveRejected = 4005;

  /// 发送前内容审核拒绝，或审核服务不可达（阻断模式）。
  static const int contentRejected = 4006;

  /// AppId 的访问凭证已暂停。
  static const int credentialSuspended = 4031;

  /// AppId 的访问凭证已吊销。
  static const int credentialRevoked = 4032;

  /// AppId 的访问凭证已过期。
  static const int credentialExpired = 4033;

  /// 请求过于频繁。
  static const int rateLimited = 4290;

  static bool isCredentialBlocked(int code) =>
      code == credentialSuspended ||
      code == credentialRevoked ||
      code == credentialExpired;

  /// 消息被内容策略拦截（敏感词或发送前审核）。
  static bool isContentRejected(int code) =>
      code == sensitiveRejected || code == contentRejected;
}

/// 控制面请求失败。[code] 为响应体业务码（见 [SyImErrorCode]），响应体没有 code 时为 HTTP 状态码。
/// 仍是 [Exception]，已有的 `on Exception` 可以接住。
class SyImControlPlaneException implements Exception {
  SyImControlPlaneException(this.code, this.httpStatus, this.message);

  final int code;
  final int httpStatus;
  final String message;

  bool get isCredentialBlocked => SyImErrorCode.isCredentialBlocked(code);
  bool get isContentRejected => SyImErrorCode.isContentRejected(code);

  @override
  String toString() =>
      'SyImControlPlaneException($code, http $httpStatus): $message';
}

/// 表情回应（lite）。服务端 `POST /api/user/im/reaction` 发出的 Custom(110) 消息，`data` 为
/// `{"sy":"reaction_lite","action":"add|remove","emoji":"👍","target":{"seq":..,"clientMsgId":..,"senderId":..}}`。
/// 与 Android `ImReaction`、iOS `SyImReaction` 解析规则相同。
class SyImReaction {
  const SyImReaction({
    required this.emoji,
    required this.added,
    required this.targetClientMsgId,
    required this.targetSeq,
    required this.targetSenderId,
  });

  static const String description = 'sy_reaction_lite';

  final String emoji;
  final bool added;
  final String targetClientMsgId;
  final int targetSeq;
  final String targetSenderId;

  /// 解析自定义消息的 `data` 字符串；不是回应消息时返回 null。
  static SyImReaction? parse(String? customData) {
    if (customData == null || customData.trim().isEmpty) return null;
    Object? obj;
    try {
      obj = jsonDecode(customData);
    } on FormatException {
      return null;
    }
    if (obj is! Map || obj['sy'] != 'reaction_lite') return null;
    final emoji = (obj['emoji']?.toString() ?? '').trim();
    if (emoji.isEmpty) return null;
    final target = obj['target'] is Map ? obj['target'] as Map : const {};
    final seq = target['seq'];
    return SyImReaction(
      emoji: emoji,
      added: obj['action'] != 'remove',
      targetClientMsgId: target['clientMsgId']?.toString() ?? '',
      targetSeq: seq is num ? seq.toInt() : 0,
      targetSenderId: target['senderId']?.toString() ?? '',
    );
  }

  /// `POST /api/user/im/reaction` 的请求体（与服务端 `ReactReq` 字段一致）。
  static Map<String, dynamic> requestBody({
    required String appId,
    required String fromUserId,
    required String emoji,
    String? toUserId,
    String? groupId,
    String? targetClientMsgId,
    int targetSeq = 0,
    String? targetSenderId,
    bool add = true,
  }) {
    final body = <String, dynamic>{
      'appId': appId,
      'fromUserId': fromUserId,
      'emoji': emoji,
      'action': add ? 'add' : 'remove',
    };
    if (groupId != null && groupId.isNotEmpty) {
      body['groupId'] = groupId;
    } else {
      body['toUserId'] = toUserId ?? '';
    }
    if (targetClientMsgId != null && targetClientMsgId.isNotEmpty) {
      body['targetClientMsgId'] = targetClientMsgId;
    }
    if (targetSeq > 0) body['targetSeq'] = targetSeq;
    if (targetSenderId != null && targetSenderId.isNotEmpty) {
      body['targetSenderId'] = targetSenderId;
    }
    return body;
  }
}
