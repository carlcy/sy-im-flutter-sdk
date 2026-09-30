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
