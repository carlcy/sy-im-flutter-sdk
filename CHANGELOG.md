# Changelog

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
- Example + docs: one `SY_API_BASE` / HTTPS IP switch; prefer `https://47.105.48.196`.

## 0.2.0 — 2026-09-21

- Switch OpenIM dependency from broken sibling `path:` to pub.dev `flutter_openim_sdk 3.8.3+hotfix.15`.
- Example defaults prefer HTTPS IP + documented HTTP fallback via `--dart-define`.
- Package is pub-gettable from the download zip without local open_im checkout.
