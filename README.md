# sy_im_flutter_sdk

SY IM Flutter SDK。在 Dart 里封装 [flutter_openim_sdk](https://pub.dev/packages/flutter_openim_sdk)，客户按 **pub.dev 版本号** 接入。

**当前版本：0.5.0**

客户在自己的 `pubspec.yaml` 里写下面这一行，然后执行 `flutter pub get`。不要下载、解压 `sy-im-flutter-*.zip`。

```yaml
dependencies:
  sy_im_flutter_sdk: ^0.5.0
```

暂时不能访问 pub.dev 时，用打过 tag 的 Git 依赖（tag 与版本号一致，例如 `v0.5.0`）：

```yaml
dependencies:
  sy_im_flutter_sdk:
    git:
      url: https://github.com/carlcy/sy-im-flutter-sdk.git
      ref: v0.5.0
```

本仓库的 `example/` 为了本地改 SDK 后直接运行，使用 `path: ../`。这只给本仓库开发用，客户不要复制。

## 快速开始

流程与常见 IM Flutter SDK 一致：写依赖、初始化、用业务后端签发的 Token 登录、发一条文本、监听新消息。

### 1. 添加依赖

```yaml
dependencies:
  sy_im_flutter_sdk: ^0.5.0
  path_provider: ^2.1.5
```

```bash
flutter pub get
```

`path_provider` 用来放 OpenIM 本地数据目录，由你的 App 自己声明。

### 2. 初始化

先向你的业务后端拿到 User JWT。SDK 再用它向 SY 控制面换 IM Token（`POST /api/user/im/token`）。响应里的 `imApiAddr`、`imWsAddr` 是 OpenIM 地址，客户端不要写死机器 IP。

```dart
import 'package:path_provider/path_provider.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

late SyImEngine im;

Future<void> initSyIm() async {
  final dir = await getApplicationDocumentsDirectory();
  im = await SyIm.create(
    appId: 'your_app_id',
    apiBaseUrl: 'https://syrtcapi.shengyuchenyao.cn',
  );

  im.onConnectSuccess = () {
    // 已连上 OpenIM
  };
  im.onConnecting = () {};
  im.onConnectFailed = (code, error) {};
  im.onKickedOffline = () {
    // 被踢下线后重新 login
  };
  im.onUserTokenExpired = () {
    // Token 过期：重新 getToken 再 login
  };
  im.onRecvNewMessage = (msgId, fromUserId, groupId, text) {
    // 见「5. 接收消息」
  };
  im.onRecvC2CReadReceipt = (receipts) {
    // 对方已读
  };

  final token = await im.getToken(
    userId: 'user_001',
    userJwt: userJwtFromYourServer,
  );

  await im.configureOpenIM(
    imApiAddr: token['imApiAddr'] as String,
    imWsAddr: token['imWsAddr'] as String,
    dataDir: '${dir.path}/sy_im',
  );
}
```

服务端持有 AppSecret 时，把 `userJwt` 换成 `appSecret` 即可走 `POST /api/server/im/token`。AppSecret 不要打进客户端安装包。

### 3. 登录

初始化完成后再登录。登录成功后才能发消息、拉会话、处理好友和群。

```dart
await im.login(
  userId: 'user_001',
  token: token['token'] as String,
);
```

`token` 是上一步 `getToken` 返回的 IM Token。

### 4. 发送消息

单聊填 `toUserId`，群聊填 `groupId`。

```dart
final msgId = await im.sendTextMessage(
  toUserId: 'user_002',
  text: 'hello',
);
```

### 5. 接收消息

在 `configureOpenIM` 之前设置 `onRecvNewMessage`（上面初始化示例已经设置）。新消息和离线同步下来的文本都会进这个回调。

```dart
im.onRecvNewMessage = (msgId, fromUserId, groupId, text) {
  // fromUserId 发送方
  // groupId 非空表示群消息
  // text 文本内容
};
```

未读数会跟着 OpenIM 回调自己变，不用轮询。会话列表标题上直接听 `unreadChanges`：

```dart
im.unreadChanges.listen((update) {
  final total = update.totalUnread;
  for (final conversation in update.conversations) {
    // conversation.unreadCount 是这一条会话的未读
  }
});

await im.markConversationAsRead(
  conversationId: conversations.first.conversationId,
);
// 返回时本地未读已经清零，随后再向 SDK 拉一次总数和会话列表
```

`onUnreadChanged` 是同一个快照的回调。`totalUnread` 是最近一次快照，不额外请求。单条会话的未读在 `SyImConversation.unreadCount`。

## 消息、会话和资料

这些接口都要求已经 `login`。原来的 `sendTextMessage`、`login`、`getToken` 签名不变。

```dart
await im.revokeMessage(conversationId: 'si_a_b', clientMsgId: msgId);

await im.sendAtTextMessage(
  groupId: group.groupId,
  text: '你好 @user_002',
  atUserIds: ['user_002'],
);

await im.sendCustomMessage(
  toUserId: 'user_002',
  data: '{"kind":"order","id":"1"}',
  description: '订单',
);

final hits = await im.searchMessages(keyword: 'hello');
await im.pinConversation(conversationId: 'si_a_b', pinned: true);
await im.setConversationDraft(conversationId: 'si_a_b', draft: '还没发出去');
await im.setConversationDoNotDisturb(
  conversationId: 'si_a_b',
  status: SyImRecvOpt.notReceive,
);
await im.setTyping(conversationId: 'si_a_b', typing: true);

final read = await im.getGroupMessageReadInfo(
  conversationId: 'sg_group',
  clientMsgId: msgId,
);
// read.hasReadCount / read.unreadCount
// read.readUserIds 在当前 OpenIM Flutter 绑定里为空

await im.setSelfProfile(nickname: '阿花', ex: '{"level":1}');
await im.setGroupCustomInfo(groupId: group.groupId, notification: '公告', ex: '{}');
await im.addToBlacklist(userId: 'user_009');
```

`@所有人` 使用 `syImAtAllUserId`。撤回回调是 `onMessageRevoked`，正在输入回调是 `onTypingChanged`（`SyImTypingStatus.typing` / `platformIds`，`platformIds` 为空即停止）。`sendTyping(conversationId:, focus:)` 是与 Android / iOS 同名的写法，等同 `setTyping`。

## 好友申请与群

以下接口都要求已经 `login`。原有的 `sendTextMessage`、`getConversations`、`login`、`logout`、`getToken` 签名不变。控制面 REST（`controlPlane.addFriend` / `createGroup` / `listFriends` / `history` / `revoke`）也保持原路径。

```dart
await im.addFriend(userId: 'user_002', reason: '你好');
final incoming = await im.getFriendApplications();
await im.acceptFriendApplication(userId: incoming.first.fromUserId);

final group = await im.createGroup(
  groupName: '项目群',
  memberUserIds: ['user_002'],
);
await im.inviteToGroup(groupId: group.groupId, userIds: ['user_003']);
final members = await im.getGroupMembers(groupId: group.groupId);
```

还有 `refuseFriendApplication`、`getFriends`、`joinGroup`、`kickGroupMembers`、`quitGroup`、`dismissGroup`、`getJoinedGroups`。

## 表情回应与会话标签（控制面 lite）

需要 `ImControlPlane.userJwt`。

- `reactToMessage(fromUserId:, emoji:, toUserId: / groupId:, targetClientMsgId: / targetSeq:, add:)` → `POST /api/user/im/reaction`。服务端发一条 Custom(110)（`description` 为 `sy_reaction_lite`），对端在普通新消息里收到，用 `SyImReaction.parse(customData)` 解析。**不是** OpenIM 原生回应（OpenIM 3.x 开源版没有），服务端不做聚合计数。
- 会话标签（每个用户自己的会话分组，存在 SY 服务端，与置顶无关）：`createConversationTag` / `listConversationTags` / `deleteConversationTag` / `addConversationsToTag` / `removeConversationsFromTag`。

Android、iOS 同名同参。

## 错误码

`ImControlPlane` 的请求失败时抛 `SyImControlPlaneException`（仍是 `Exception`）：`code` 为服务端业务码，`httpStatus` 为 HTTP 状态。取值在 `SyImErrorCode`，与 Android `ImErrorCode`、iOS `SyImErrorCode` 相同：

| code | 常量 | 含义 |
|---|---|---|
| 401 / 403 | `unauthorized` / `forbidden` | JWT 无效 / 无权访问该应用 |
| 3001 | `imNotEnabled` | 应用未开通 IM |
| 3003 / 3004 | `quotaMau` / `quotaMessages` | 月活 / 消息量超出套餐 |
| 4003 | `trialRetired` | 体验版已下线 |
| 4005 | `sensitiveRejected` | 敏感词拦截 |
| 4006 | `contentRejected` | 发送前内容审核拒绝或审核服务不可达 |
| 4031 / 4032 / 4033 | `credentialSuspended` / `Revoked` / `Expired` | AppId 访问凭证暂停 / 吊销 / 过期 |
| 4290 | `rateLimited` | 请求过于频繁 |

```dart
try {
  await controlPlane.getToken(userId);
} on SyImControlPlaneException catch (e) {
  if (e.isCredentialBlocked) { /* 凭证不可用 */ }
}
```

OpenIM 实时接口（登录、收发）的错误仍是 OpenIM 错误码。

## 跑本仓库示例

```bash
cd example
flutter pub get
flutter run --dart-define=SY_API_BASE=https://syrtcapi.shengyuchenyao.cn
```

示例里：粘贴 User JWT → 获取 IM Token → 初始化 → 登录 → 发送文本。OpenIM 地址以 Token 响应为准。

## 原生依赖

本包是纯 Dart 库，**不内置** AAR / xcframework，也不再提供 `SyImFlutterSdkPlugin` MethodChannel。

原生 OpenIM 由依赖 `flutter_openim_sdk: ^3.8.3+hotfix.15` 按坐标拉取：

| 平台 | 坐标 |
|------|------|
| Android | Maven Central `io.openim:core-sdk:3.8.3-patch15` |
| iOS | CocoaPods `OpenIMSDKCore` `3.8.3-hotfix.15` |

仓库里的 `android/`、`ios/` 只是 0.3.0 移除空壳插件后的占位，Flutter 不会把它编进 App。OpenIM 的 gomobile 核心以 AAR / xcframework 形式发布，上游插件已经改成坐标引用，本包不再把这些二进制打进 zip。

## 发布到 pub.dev（维护者）

客户能写 `sy_im_flutter_sdk: ^0.5.0` 之前，维护者需要把这个版本发到 pub.dev。代理不会代替你登录 pub.dev。

1. 把 `pubspec.yaml` 的 `version`、`CHANGELOG.md`、`VERSION`、本 README 里的 `^x.y.z` 改成同一个版本。
2. 在包根目录执行，确认没有 error：

```bash
dart pub publish --dry-run
```

3. 用有权限发布 `sy_im_flutter_sdk` 这个名字的 pub.dev 账号登录：

```bash
dart pub login
```

4. 发布：

```bash
dart pub publish
```

5. 打同名 tag，给 Git 依赖用：

```bash
git tag v0.5.0
git push origin v0.5.0
```

6. 不要再上传 `sy-im-flutter-0.4.2.zip` 这类压缩包给客户。集成方式只有上面的 pub.dev 行，或 `ref: v0.5.0` 的 Git 依赖。

首次发布会占用包名 `sy_im_flutter_sdk`。之后每次发版都要升版本号，pub.dev 不允许覆盖已发布版本。

## 说明

能力覆盖登录、单聊/群聊文本、已读回执、未读数、好友申请和基础群管理。离线推送要在 OpenIM 上配置 FCM / APNs 凭证。控制面默认域名是 `https://syrtcapi.shengyuchenyao.cn`，联调地址用 `--dart-define=SY_API_BASE` 覆盖，不要写进公开文档里的机器 IP。
