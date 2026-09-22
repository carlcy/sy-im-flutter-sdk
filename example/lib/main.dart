import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

String defaultApiBase() {
  // Single switch (all platforms): --dart-define=SY_API_BASE=...
  // Domain syrtcapi.shengyuchenyao.cn is ICP/WAF-blocked (HTTP 403). Prefer IP HTTPS.
  const override = String.fromEnvironment('SY_API_BASE', defaultValue: '');
  if (override.isNotEmpty) return override;
  return const String.fromEnvironment(
    'SY_API_HTTPS',
    defaultValue: 'https://47.105.48.196',
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SY IM Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ImDemoPage(),
    );
  }
}

class ImDemoPage extends StatefulWidget {
  const ImDemoPage({super.key});

  @override
  State<ImDemoPage> createState() => _ImDemoPageState();
}

class _ImDemoPageState extends State<ImDemoPage> {
  late final _apiBase = TextEditingController(text: defaultApiBase());
  final _appId = TextEditingController(text: 'your_app_id');
  final _userId = TextEditingController(text: 'u1001');
  final _jwt = TextEditingController();
  final _token = TextEditingController();
  final _imApi = TextEditingController(text: 'https://47.105.48.196/openim');
  final _imWs = TextEditingController(text: 'wss://47.105.48.196/msg_gateway');
  final _peer = TextEditingController(text: 'u1002');
  final _text = TextEditingController(text: 'hello from flutter');

  final _logs = <String>[];
  final _convLines = <String>[];
  SyImEngine? _engine;
  String _status = '未初始化';

  void _log(String msg) {
    setState(() {
      _logs.insert(0, msg);
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  Future<void> _fetchToken() async {
    final jwt = _jwt.text.trim();
    if (jwt.isEmpty) {
      _log('填写 User JWT 后请求 POST /api/user/im/token');
      return;
    }
    final uri = Uri.parse('${_apiBase.text.trim()}/api/user/im/token');
    _log('POST $uri');
    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'appId': _appId.text.trim(),
              'userId': _userId.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['code'] != 0) {
        _log('im/token fail ${json['code']} ${json['msg']}');
        return;
      }
      final data = json['data'] as Map<String, dynamic>;
      setState(() {
        _token.text = '${data['token'] ?? ''}';
        if ((data['imApiAddr'] as String?)?.isNotEmpty == true) {
          _imApi.text = data['imApiAddr'] as String;
        }
        if ((data['imWsAddr'] as String?)?.isNotEmpty == true) {
          _imWs.text = data['imWsAddr'] as String;
        }
      });
      _log('im/token ok');
    } catch (e) {
      _log('im/token error: $e');
    }
  }

  Future<void> _init() async {
    try {
      SyIm.reset();
      final dir = await getApplicationDocumentsDirectory();
      final eng = await SyIm.create(
        appId: _appId.text.trim(),
        apiBaseUrl: _apiBase.text.trim(),
      );
      eng.onConnectSuccess = () => _log('event: connect success');
      eng.onConnectFailed = (c, m) => _log('event: connect failed $c $m');
      eng.onRecvNewMessage = (id, from, gid, text) {
        _log('recv $from: $text');
      };
      eng.onConversationUpdated = () => _refreshConvs();
      await eng.configureOpenIM(
        imApiAddr: _imApi.text.trim(),
        imWsAddr: _imWs.text.trim(),
        dataDir: '${dir.path}/sy_im',
      );
      setState(() {
        _engine = eng;
        _status = 'OpenIM 已初始化';
      });
      _log('configureOpenIM ok');
    } on UnimplementedError catch (e) {
      setState(() => _status = 'OpenIM API 未实现');
      _log('Unimplemented: $e');
    } catch (e) {
      setState(() => _status = '初始化失败');
      _log('init error: $e');
    }
  }

  Future<void> _login() async {
    final eng = _engine;
    if (eng == null) {
      _log('先初始化');
      return;
    }
    try {
      await eng.login(userId: _userId.text.trim(), token: _token.text.trim());
      setState(() => _status = '已登录 ${_userId.text.trim()}');
      _log('login ok');
      await _refreshConvs();
    } on UnimplementedError catch (e) {
      _log('login Unimplemented: $e');
    } catch (e) {
      _log('login error: $e');
    }
  }

  Future<void> _send() async {
    final eng = _engine;
    if (eng == null) return;
    try {
      final id = await eng.sendTextMessage(
        toUserId: _peer.text.trim(),
        text: _text.text.trim(),
      );
      _log('sent $id');
      await _refreshConvs();
    } on UnimplementedError catch (e) {
      _log('send Unimplemented: $e');
    } catch (e) {
      _log('send error: $e');
    }
  }

  Future<void> _logout() async {
    try {
      await _engine?.logout();
      setState(() => _status = '已登出');
      _log('logout ok');
    } catch (e) {
      _log('logout error: $e');
    }
  }

  Future<void> _refreshConvs() async {
    try {
      final list = await _engine?.getConversations() ?? [];
      setState(() {
        _convLines
          ..clear()
          ..addAll(list.map((c) =>
              '${c.showName ?? c.conversationId}: ${c.latestText ?? ""} unread=${c.unreadCount}'));
      });
    } on UnimplementedError catch (e) {
      _log('conversations Unimplemented: $e');
    } catch (e) {
      _log('conversations error: $e');
    }
  }

  @override
  void dispose() {
    _apiBase.dispose();
    _appId.dispose();
    _userId.dispose();
    _jwt.dispose();
    _token.dispose();
    _imApi.dispose();
    _imWs.dispose();
    _peer.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SY IM Example')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Go 后端 :8080 — iOS 模拟器用 127.0.0.1，Android 模拟器用 10.0.2.2，真机用局域网 IP。'
            '先获取 IM Token，再初始化 OpenIM 并登录。',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          _field('API Base', _apiBase),
          _field('AppId', _appId),
          _field('User ID', _userId),
          _field('User JWT', _jwt, obscure: true),
          _field('IM Token', _token, obscure: true),
          _field('OpenIM API', _imApi),
          _field('OpenIM WS', _imWs),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: _fetchToken, child: const Text('获取 IM Token')),
            FilledButton(onPressed: _init, child: const Text('初始化')),
            FilledButton(onPressed: _login, child: const Text('登录')),
            FilledButton(onPressed: _logout, child: const Text('登出')),
          ]),
          _field('To user', _peer),
          _field('Text', _text),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: _send, child: const Text('发送文本')),
            OutlinedButton(onPressed: _refreshConvs, child: const Text('刷新会话')),
          ]),
          const SizedBox(height: 8),
          const Text('会话', style: TextStyle(fontWeight: FontWeight.w600)),
          Container(
            height: 100,
            padding: const EdgeInsets.all(8),
            color: Colors.black12,
            child: ListView(
              children: _convLines.isEmpty
                  ? [const Text('(empty)')]
                  : _convLines.map((e) => Text(e)).toList(),
            ),
          ),
          const SizedBox(height: 8),
          const Text('日志', style: TextStyle(fontWeight: FontWeight.w600)),
          Container(
            height: 140,
            padding: const EdgeInsets.all(8),
            color: Colors.black12,
            child: ListView(
              children: _logs
                  .map((e) => Text(e, style: const TextStyle(fontSize: 12)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
