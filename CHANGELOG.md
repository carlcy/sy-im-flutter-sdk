## 0.4.0

- Align version with Android/iOS IM SDKs.
- Publish target: github.com/carlcy/sy-im-flutter-sdk

# Changelog

## 0.3.0 — 2026-09-21

- **Breaking (cleanup):** removed legacy no-op `SyImFlutterSdkPlugin` MethodChannel shell (Android/iOS).
- Package is now a **pure Dart** library: single path `SyIm` → `OpenIMAdapter` → `flutter_openim_sdk`.
- Example + docs: one `SY_API_BASE` / HTTPS IP switch; prefer `https://47.105.48.196`.

## 0.2.0 — 2026-09-21

- Switch OpenIM dependency from broken sibling `path:` to pub.dev `flutter_openim_sdk 3.8.3+hotfix.15`.
- Example defaults prefer HTTPS IP + documented HTTP fallback via `--dart-define`.
- Package is pub-gettable from the download zip without local open_im checkout.
