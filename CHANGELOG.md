# Changelog

## 0.5.0

- 版本与 Android / iOS IM SDK 对齐为 `0.5.0`。客户依赖写 `sy_im_flutter_sdk: ^0.5.0`。
- 未读实时更新：`unreadChanges` / `onUnreadChanged` 同时带总未读和各会话未读，来源是 OpenIM 的 `onTotalUnreadMessageCountChanged`、会话变更和新消息；`markConversationAsRead` 返回前会先把本地未读清零并再向 SDK 拉一次。
- 补充腾讯云 IM 常见能力里 OpenIM 已支持的部分：消息撤回、@ 文本、本地消息搜索、会话置顶 / 草稿 / 免打扰、正在输入、自定义消息、用户与群自定义资料、黑名单。群已读目前只能拿到已读人数和未读人数，这一版 OpenIM Flutter 绑定没有已读成员 id 列表。
- 正在输入：`SyImTypingStatus` 增加 `platformIds`（与 Android `ImTypingStatus`、iOS `SyImTypingStatus` 同字段），`SyImTypingStatus.fromOpenIm` 按平台列表判定 `typing`；新增与原生同名的 `sendTyping(conversationId:, focus:)`（等同 `setTyping`）。
- 控制面失败改抛 `SyImControlPlaneException(code, httpStatus, message)`，业务码常量 `SyImErrorCode`（4003 / 4005 / 4006 / 4031–4033 / 4290 等）与 Android、iOS、服务端一致。此前只抛 `Exception(msg)`。
- example/android：Gradle 堆调到 4G，修复 `flutter build apk` OOM。

## 0.4.3

- 客户接入改为 pub.dev 版本号 `sy_im_flutter_sdk: ^0.4.3`（或 git tag `v0.4.3`）。不再通过 zip 解压集成。
- README 快速开始改为中文：添加依赖、初始化、Token 登录、发消息、收消息。
- 在不改变原有 API 的前提下补充：会话已读与 C2C 已读回执、总未读数、好友申请（列表/同意/拒绝）、群创建/邀请/踢人/入群/退群/解散/成员列表。
- 说明原生依赖由 `flutter_openim_sdk` 以 Maven / CocoaPods 坐标拉取，本包不内置二进制。

## 0.4.2

- README / example：去掉公开 IP；默认使用域名 `syrtcapi.shengyuchenyao.cn`
- 安装说明改为优先 **pub.dev** `^0.4.2`

## 0.4.1

- Align nested tombstone Android/iOS plugin versions with package `0.4.1`.
- Prefer hyphen GitHub remote `sy-im-flutter-sdk` in docs.

## 0.4.0

- Align version with Android/iOS IM SDKs.
- Publish target: github.com/carlcy/sy-im-flutter-sdk

## 0.3.0 — 2026-09-21

- **Breaking (cleanup):** removed legacy no-op `SyImFlutterSdkPlugin` MethodChannel shell (Android/iOS).
- Package is now a **pure Dart** library: single path `SyIm` → `OpenIMAdapter` → `flutter_openim_sdk`.
- Example + docs: one `SY_API_BASE` switch; prefer production domain.

## 0.2.0 — 2026-09-21

- Switch OpenIM dependency from broken sibling `path:` to pub.dev `flutter_openim_sdk 3.8.3+hotfix.15`.
- Example defaults prefer HTTPS IP + documented HTTP fallback via `--dart-define`.
- Package is pub-gettable from the download zip without local open_im checkout.
