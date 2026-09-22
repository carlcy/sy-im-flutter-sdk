# sy_im_flutter_sdk (0.2.0)

Production-ready SY IM Flutter plugin. Real OpenIM via **pub.dev** `flutter_openim_sdk` (not a stub MethodChannel / broken path dep).

## Install

```yaml
dependencies:
  sy_im_flutter_sdk:
    path: ./sy_im_flutter_sdk
```

Pinned transitive dependency:

```yaml
flutter_openim_sdk: 3.8.3+hotfix.15   # from pub.dev
```

```bash
flutter pub get
```

## Example (token → login → send/receive text)

```bash
cd example
flutter pub get
flutter run --dart-define=SY_API_BASE=https://47.105.48.196
# cleartext fallback:
# flutter run --dart-define=SY_API_BASE=http://47.105.48.196
```

1. Paste User JWT (or use server token API with AppSecret on your backend).
2. Tap **Get IM Token** → fills OpenIM API/WS from control plane.
3. **Init** → **Login** → **Send text**.

Default OpenIM endpoints (nginx proxy):

- API: `https://47.105.48.196/openim`
- WS: `wss://47.105.48.196/msg_gateway`

## HTTPS note (honest)

| Endpoint | Public Internet |
|----------|-----------------|
| `http://47.105.48.196` | OK |
| `https://47.105.48.196` | OK (replaceable self-signed under `/etc/nginx/ssl/syrtc/`) |
| `http(s)://syrtcapi.shengyuchenyao.cn` | **Blocked** (HTTP 403 / TLS reset; LE HTTP-01 also 403) |

Replace certs when a public CA is available; clients already prefer HTTPS IP.

## Not claimed

- Not Tencent TIM full SDK parity
- Offline push needs your FCM/APNs files in OpenIM push config
