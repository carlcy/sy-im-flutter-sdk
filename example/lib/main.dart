import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

String defaultApiBase() {
  // --dart-define=SY_API_BASE=https://你的控制面域名
  const override = String.fromEnvironment('SY_API_BASE', defaultValue: '');
  if (override.isNotEmpty) return override;
  return const String.fromEnvironment(
    'SY_API_HTTPS',
    defaultValue: 'https://syrtcapi.shengyuchenyao.cn',
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
  final _imApi = TextEditingController(
    text: 'https://syrtcapi.shengyuchenyao.cn/openim',
  );
  final _imWs = TextEditingController(
    text: 'wss://syrtcapi.shengyuchenyao.cn/msg_gateway',
  );
  final _peer = TextEditingController(text: 'u1002');
  final _text = TextEditingController(text: 'hello from flutter');

  final _logs = <String>[];
  final _convLines = <String>[];
  List<SyImConversation> _conversations = const [];
  SyImEngine? _engine;
  StreamSubscription<SyImUnreadUpdate>? _unreadSub;
  int _totalUnread = 0;
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
      _log('填写 User JWT 后由 SDK 请求 POST /api/user/im/token');
      return;
    }
    try {
      final data = await ImControlPlane(
        apiBaseUrl: _apiBase.text.trim(),
        appId: _appId.text.trim(),
        userJwt: jwt,
      ).getToken(userId: _userId.text.trim());
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
      eng.onRecvC2CReadReceipt = (receipts) {
        for (final r in receipts) {
          _log('read by ${r.userId}: ${r.msgIds.join(",")}');
        }
      };
      eng.onMessageRevoked = (info) => _log('revoked ${info.clientMsgId}');
      eng.onTypingChanged = (status) {
        _log('typing ${status.userId} ${status.typing}');
      };
      _listenUnread(eng);
      eng.onConversationUpdated = () {};
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
      if (!mounted) return;
      setState(() {
        _totalUnread = _engine?.totalUnread ?? _totalUnread;
        _applyConversations(list);
      });
    } on UnimplementedError catch (e) {
      _log('conversations Unimplemented: $e');
    } catch (e) {
      _log('conversations error: $e');
    }
  }

  Future<void> _logUnread() async {
    final eng = _engine;
    if (eng == null) return;
    try {
      final n = eng.totalUnread;
      _log('unread total $n');
    } catch (e) {
      _log('unread error: $e');
    }
  }

  Future<void> _markRead() async {
    final eng = _engine;
    if (eng == null) return;
    if (_conversations.isEmpty) {
      _log('先刷新会话');
      return;
    }
    final id = _conversations.first.conversationId;
    try {
      await eng.markConversationAsRead(conversationId: id);
      _log('marked read $id');
      await _refreshConvs();
    } catch (e) {
      _log('mark read error: $e');
    }
  }

  Future<void> _addFriend() async {
    final eng = _engine;
    if (eng == null) return;
    try {
      await eng.addFriend(userId: _peer.text.trim(), reason: 'hello');
      _log('friend request sent');
    } catch (e) {
      _log('add friend error: $e');
    }
  }

  Future<void> _acceptFriend() async {
    final eng = _engine;
    if (eng == null) return;
    try {
      final apps = await eng.getFriendApplications();
      if (apps.isEmpty) {
        _log('no incoming friend requests');
        return;
      }
      await eng.acceptFriendApplication(userId: apps.first.fromUserId);
      _log('accepted ${apps.first.fromUserId}');
    } catch (e) {
      _log('accept friend error: $e');
    }
  }

  Future<void> _createGroup() async {
    final eng = _engine;
    if (eng == null) return;
    try {
      final group = await eng.createGroup(
        groupName: 'demo',
        memberUserIds: [_peer.text.trim()],
      );
      _log('group ${group.groupId} ${group.groupName}');
    } catch (e) {
      _log('create group error: $e');
    }
  }

  void _listenUnread(SyImEngine engine) {
    _unreadSub?.cancel();
    _unreadSub = engine.unreadChanges.listen((update) {
      if (!mounted) return;
      setState(() {
        _totalUnread = update.totalUnread;
        _applyConversations(update.conversations);
      });
    });
  }

  void _applyConversations(List<SyImConversation> list) {
    _conversations = list;
    _convLines
      ..clear()
      ..addAll(
        list.map((c) {
          final pin = c.isPinned ? '[置顶] ' : '';
          final draft = (c.draftText != null && c.draftText!.isNotEmpty)
              ? ' [草稿]${c.draftText}'
              : '';
          return '$pin${c.showName ?? c.conversationId}: ${c.latestText ?? ""}$draft unread=${c.unreadCount}';
        }),
      );
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
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
      appBar: AppBar(
        title: Text('SY IM $syImSdkVersion'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Badge(
                  key: const Key('total-unread-badge'),
                  isLabelVisible: _totalUnread > 0,
                  label: Text('$_totalUnread'),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
                const SizedBox(width: 8),
                Text('未读 $_totalUnread', key: const Key('total-unread-text')),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '依赖写 sy_im_flutter_sdk: ^$syImSdkVersion。先用 User JWT 换 IM Token，'
            '再用返回的 OpenIM 地址初始化并登录。',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          _field('API Base', _apiBase),
          _field('AppId', _appId),
          _field('User ID', _userId),
          _field('User JWT', _jwt, obscure: true),
          _field('IM Token', _token, obscure: true),
          _field('OpenIM API', _imApi),
          _field('OpenIM WS', _imWs),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _fetchToken,
                child: const Text('获取 IM Token'),
              ),
              FilledButton(onPressed: _init, child: const Text('初始化')),
              FilledButton(onPressed: _login, child: const Text('登录')),
              FilledButton(onPressed: _logout, child: const Text('登出')),
            ],
          ),
          _field('To user', _peer),
          _field('Text', _text),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _send, child: const Text('发送文本')),
              OutlinedButton(
                onPressed: _refreshConvs,
                child: const Text('刷新会话'),
              ),
              OutlinedButton(onPressed: _logUnread, child: const Text('总未读')),
              OutlinedButton(onPressed: _markRead, child: const Text('标记已读')),
              OutlinedButton(onPressed: _addFriend, child: const Text('好友申请')),
              OutlinedButton(
                onPressed: _acceptFriend,
                child: const Text('同意好友'),
              ),
              OutlinedButton(onPressed: _createGroup, child: const Text('建群')),
            ],
          ),
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
