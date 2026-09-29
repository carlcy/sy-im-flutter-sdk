# sy_im_flutter_sdk example

客户集成写版本号，不要解压 zip：

```yaml
dependencies:
  sy_im_flutter_sdk: ^0.4.3
```

本目录的 `pubspec.yaml` 使用 `path: ../`，只为在本仓库里改 SDK 后直接运行。

```bash
flutter pub get
flutter run --dart-define=SY_API_BASE=https://syrtcapi.shengyuchenyao.cn
```

控制面与 OpenIM 网关地址以 Token 响应为准。
