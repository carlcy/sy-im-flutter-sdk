# SY IM Flutter Example

这个示例演示客户接入方式：在 `pubspec.yaml` 声明 SDK，用 User JWT 换 IM Token，再初始化、登录、发文本、收消息。

客户项目写：

```yaml
dependencies:
  sy_im_flutter_sdk: ^0.4.3
```

本 example 为本地开发保留 `path: ../`，不要把 path 或 zip 解压路径交给客户。

```bash
cd example
flutter pub get
flutter run --dart-define=SY_API_BASE=https://syrtcapi.shengyuchenyao.cn
```

1. 粘贴 User JWT
2. 获取 IM Token（SDK 调 `POST /api/user/im/token`）
3. 初始化 → 登录 → 发送文本
4. 可选：总未读、标记已读、好友申请、建群

OpenIM API / WS 使用 Token 响应里的 `imApiAddr`、`imWsAddr`。
