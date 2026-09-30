# Removed (0.3.0+)

`SyImFlutterSdkPlugin` MethodChannel 空壳已删除。
实时 IM 走 Dart `SyIm` / `OpenIMAdapter`，原生库由 `flutter_openim_sdk` 按坐标引入：

- Android：Maven Central `io.openim:core-sdk:3.8.3-patch15`
- iOS：CocoaPods `OpenIMSDKCore` `3.8.3-hotfix.15`

本目录没有插件代码，也没有随包分发的 AAR。
