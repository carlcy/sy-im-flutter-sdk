# SY IM Flutter Example

对接本地 Go 后端 `:8080` + 官方 `flutter_openim_sdk`（path 依赖）。

| | iOS 模拟器 | Android 模拟器 | 真机 |
|--|-----------|----------------|------|
| API | `http://127.0.0.1:8080` | `http://10.0.2.2:8080` | 局域网 IP |
| IM Token | `POST /api/user/im/token`（Bearer User JWT） | 同左 | 同左 |

返回 `{ token, imApiAddr, imWsAddr }` 后：初始化 OpenIM → 登录 → 发文本 → 会话列表 stub。

```bash
cd ../../rtc-backend-go && make run
cd ../sy_im_flutter_sdk/example
flutter pub get
flutter run
```

OpenIM 仅在 API 缺失时抛 `UnimplementedError`。模拟器可测登录 UI；真实收发需 OpenIM 服务可达。
