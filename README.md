# sy_im_flutter_sdk

SY IM Flutter SDK：Dart `OpenIMAdapter` 封装 [flutter_openim_sdk](https://pub.dev/packages/flutter_openim_sdk)（无遗留 MethodChannel 空壳）。

**当前版本：0.4.2**

## 安装（推荐 pub.dev）

```yaml
dependencies:
  sy_im_flutter_sdk: ^0.4.2
```

```bash
flutter pub get
```

Git 备选（一般不需要）：

```yaml
dependencies:
  sy_im_flutter_sdk:
    git:
      url: https://github.com/carlcy/sy-im-flutter-sdk.git
      ref: v0.4.2
```

## 控制面与 OpenIM 地址

生产请使用**域名**（由 Token 响应中的 `imApiAddr` / `imWsAddr` 下发，勿在客户端写死机器 IP）：

| 用途 | 地址 |
|------|------|
| 控制面 API | `https://syrtcapi.shengyuchenyao.cn` |
| OpenIM API（典型） | Token 返回的 `imApiAddr`（如 `…/openim`） |
| OpenIM WS（典型） | Token 返回的 `imWsAddr`（如 `…/msg_gateway/`） |

Example：

```bash
cd example
flutter pub get
flutter run --dart-define=SY_API_BASE=https://syrtcapi.shengyuchenyao.cn
```

1. 粘贴 User JWT（或由你的后端用 AppSecret 调 `POST /api/server/im/token`）
2. **Get IM Token** → 用控制面返回的 OpenIM API/WS
3. **Init** → **Login** → **Send text**

## 诚实说明

- 非腾讯云 TIM 全 SDK 对等
- 离线推送需你在 OpenIM 配置 FCM / APNs 等凭证
- 不在文档中公开服务器 IP；联调 IP 仅限内部运维，不写进公开包说明
