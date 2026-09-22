import 'dart:convert';

import 'package:http/http.dart' as http;

/// SY IM 控制面 REST（非 OpenIM 原生 SDK）。
///
/// - [getToken] → `/api/user/im/token` 或 `/api/server/im/token`
/// - friends / groups / send / history / revoke → `/api/user/im/*`
///
/// 实时收发请用 [OpenIMAdapter] / `flutter_openim_sdk`。不宣称腾讯云 TIM 全对等。
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

  Map<String, dynamic> _decode(http.Response res) {
    final map = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (map is! Map) {
      throw Exception('unexpected response');
    }
    final m = Map<String, dynamic>.from(map);
    final code = m['code'] as int? ?? (res.statusCode >= 200 && res.statusCode < 300 ? 0 : -1);
    if (res.statusCode < 200 || res.statusCode >= 300 || code != 0) {
      throw Exception(m['msg'] ?? 'HTTP ${res.statusCode}');
    }
    final data = m['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data == null) return <String, dynamic>{};
    return <String, dynamic>{'value': data};
  }
}
